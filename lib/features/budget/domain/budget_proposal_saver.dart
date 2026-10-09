import '../../../core/persistence/unit_of_work.dart';
import 'budget_proposal.dart';
import 'budget_proposal_calculator.dart';
import 'budget_proposal_editor.dart';
import 'budget_repository.dart';

enum BudgetProposalSaveFailureCode {
  staleReview,
  invalidReview,
  confirmationRequired,
  persistence,
}

final class BudgetProposalSaveFailure implements Exception {
  const BudgetProposalSaveFailure(this.message, {required this.code});
  final String message;
  final BudgetProposalSaveFailureCode code;
  @override
  String toString() => message;
}

enum BudgetProposalConfirmation { saveProposal, replaceItems }

enum BudgetProposalChangeKind { added, updated, unchanged, removed }

/// Una fila por UUID/mes, con ruta completa y ausencia distinta de cero.
final class BudgetProposalChange {
  const BudgetProposalChange({
    required this.month,
    required this.categoryId,
    required this.categoryPath,
    required this.before,
    required this.after,
  });
  final BudgetMonth month;
  final String categoryId, categoryPath;
  final BudgetRecord? before;
  final BudgetInput? after;

  BudgetProposalChangeKind get kind => before == null
      ? BudgetProposalChangeKind.added
      : after == null
      ? BudgetProposalChangeKind.removed
      : before!.data.amountCents == after!.amountCents
      ? BudgetProposalChangeKind.unchanged
      : BudgetProposalChangeKind.updated;
}

/// Revisión emitida por el coordinador, inmutable y válida solo en esta sesión.
/// Construir un SavePlan público no permite saltarse la revisión/confirmación.
final class BudgetProposalReview {
  BudgetProposalReview._(
    this._owner,
    this.plan,
    Iterable<BudgetProposalChange> changes,
  ) : changes = List.unmodifiable(changes);
  final Object _owner;
  final BudgetProposalSavePlan plan;
  final List<BudgetProposalChange> changes;
  Future<BudgetProposalSaveResult>? _pending;
  BudgetProposalSaveResult? _saved;
  bool _invalidated = false;

  bool get requiresReplacement => plan.before.isNotEmpty;
  BudgetProposalConfirmation get requiredConfirmation => requiresReplacement
      ? BudgetProposalConfirmation.replaceItems
      : BudgetProposalConfirmation.saveProposal;
  String get confirmationLabel =>
      requiresReplacement ? 'Sustituir partidas' : 'Guardar propuesta';
}

final class BudgetProposalSaveResult {
  BudgetProposalSaveResult(Iterable<BudgetRecord> records)
    : records = List.unmodifiable(records);
  final List<BudgetRecord> records;
}

/// Motor, repositorio y UnitOfWork deben compartir conexión. No incorpora SQL
/// ni persistencia del borrador. La confirmación se refiere a una revisión exacta.
final class BudgetProposalSaver {
  BudgetProposalSaver({
    required this._calculator,
    required this._budgets,
    required this._unitOfWork,
  });
  final BudgetProposalCalculator _calculator;
  final BudgetRepository _budgets;
  final UnitOfWork _unitOfWork;
  final Object _owner = Object();
  static const _validator = BudgetProposalDraftValidator();
  static const _staleFailure = BudgetProposalSaveFailure(
    'Los datos de la fuente, el árbol o las partidas destino han cambiado. '
    'Calcula y revisa una propuesta nueva; no se ha guardado ninguna partida.',
    code: BudgetProposalSaveFailureCode.staleReview,
  );

  Future<BudgetProposalReview> review(BudgetProposalDraft draft) => _guard(
    () => _unitOfWork.run(() async {
      final fresh = await _revalidate(draft);
      final before = _scopedBasis(fresh.basis, draft).targetBudgets;
      final oldByKey = {for (final b in before) _key(b.data): b};
      // La propuesta modifica importes; los textos históricos de un nodo/mes
      // existente pertenecen a esa partida y se conservan exactamente.
      final after = draft.allocations.map((a) {
        final old = oldByKey[_key(a)];
        return old == null
            ? a
            : BudgetInput(
                month: a.month,
                categoryId: a.categoryId,
                amountCents: a.amountCents,
                concept: old.data.concept,
                discretion: old.data.discretion,
              );
      }).toList();
      final newByKey = {for (final a in after) _key(a): a};
      final categories = {for (final c in fresh.basis.categories) c.node.id: c};
      final changes =
          <BudgetProposalChange>[
            for (final key in {...oldByKey.keys, ...newByKey.keys})
              BudgetProposalChange(
                month: newByKey[key]?.month ?? oldByKey[key]!.data.month,
                categoryId: key.$1,
                categoryPath: categories[key.$1]!.path,
                before: oldByKey[key],
                after: newByKey[key],
              ),
          ]..sort((a, b) {
            final month = a.month.value.compareTo(b.month.value);
            if (month != 0) return month;
            final path = a.categoryPath.compareTo(b.categoryPath);
            return path != 0 ? path : a.categoryId.compareTo(b.categoryId);
          });
      return BudgetProposalReview._(
        _owner,
        BudgetProposalSavePlan(draft: draft, before: before, after: after),
        changes,
      );
    }),
  );

  /// El consumidor invoca tras la acción explícita indicada por la revisión.
  /// Doble envío comparte la operación; un éxito repetido devuelve el mismo
  /// acuse sin escribir. Un fallo permite un reintento manual de la revisión.
  Future<BudgetProposalSaveResult> save(
    BudgetProposalReview review, {
    required BudgetProposalConfirmation confirmation,
  }) async {
    if (!identical(review._owner, _owner)) {
      throw const BudgetProposalSaveFailure(
        'La revisión no pertenece a esta sesión. Revisa la propuesta de nuevo.',
        code: BudgetProposalSaveFailureCode.invalidReview,
      );
    }
    if (confirmation != review.requiredConfirmation) {
      throw BudgetProposalSaveFailure(
        'Confirma «${review.confirmationLabel}» para guardar esta propuesta.',
        code: BudgetProposalSaveFailureCode.confirmationRequired,
      );
    }
    if (review._saved != null) return review._saved!;
    if (review._invalidated) throw _staleFailure;
    if (review._pending != null) return review._pending!;
    final pending = _guard(
      () => _unitOfWork.run(() async {
        final plan = review.plan;
        await _revalidate(plan.draft);
        final afterByKey = {for (final a in plan.after) _key(a): a};
        final beforeByKey = {for (final b in plan.before) _key(b.data): b};
        // Eliminar primero todas las retiradas libera padre/descendientes antes
        // de crear. delete conserva el registro de importación y su huella CSV.
        for (final old in plan.before) {
          if (!afterByKey.containsKey(_key(old.data))) {
            await _budgets.delete(old.id);
          }
        }
        final records = <BudgetRecord>[];
        for (final data in plan.after) {
          final old = beforeByKey[_key(data)];
          records.add(
            old == null
                ? await _budgets.create(data)
                : old.data.amountCents == data.amountCents
                ? old
                : await _budgets.edit(old.id, data),
          );
        }
        return BudgetProposalSaveResult(records);
      }),
    );
    review._pending = pending;
    try {
      final result = await pending;
      review._saved = result;
      return result;
    } on BudgetProposalSaveFailure catch (error) {
      if (error.code == BudgetProposalSaveFailureCode.staleReview) {
        review._invalidated = true;
      }
      rethrow;
    } finally {
      review._pending = null;
    }
  }

  Future<BudgetProposalDraft> _revalidate(BudgetProposalDraft draft) async {
    _validator.validate(draft);
    final BudgetProposalDraft fresh;
    try {
      fresh = await _calculator.calculate(draft.sourceYear);
    } on BudgetProposalFailure catch (error) {
      // Una fuente que ahora desborda tampoco autoriza aplicar cifras viejas.
      if (error.code == BudgetProposalFailureCode.overflow) throw _staleFailure;
      rethrow;
    }
    if (!_scopedBasis(
      draft.basis,
      draft,
    ).hasSameRelevantData(_scopedBasis(fresh.basis, draft))) {
      throw _staleFailure;
    }
    // El constructor público no certifica las filas fuente ni sus avisos:
    // validar signos con las filas calculadas de los datos recién leídos.
    _validator.validate(
      BudgetProposalDraft(
        sourceYear: draft.sourceYear,
        targetYear: draft.targetYear,
        sourceRows: fresh.sourceRows,
        allocations: draft.allocations,
        includedScopes: draft.includedScopes,
        excludedReals: fresh.excludedReals,
        basis: fresh.basis,
        signsReviewed: draft.signsReviewed,
      ),
    );
    for (final data in draft.allocations) {
      if (data.concept != null && data.concept!.trim().isEmpty) {
        throw const BudgetFailure(
          'Concepto vacío.',
          code: BudgetFailureCode.invalidConcept,
        );
      }
    }
    return fresh;
  }

  /// El árbol y los reales completos afectan al cálculo/revisión. El destino
  /// solo afecta si pertenece a una raíz/mes seleccionado, nunca a otro ámbito.
  static BudgetProposalBasis _scopedBasis(
    BudgetProposalBasis basis,
    BudgetProposalDraft draft,
  ) {
    final categories = {for (final c in basis.categories) c.node.id: c.node};
    final scopes = {
      for (final s in draft.includedScopes) (s.rootId, s.month.value),
    };
    return BudgetProposalBasis(
      sourceYear: basis.sourceYear,
      datasetState: basis.datasetState,
      categories: basis.categories,
      sourceReals: basis.sourceReals,
      targetBudgets: basis.targetBudgets.where((b) {
        var node = categories[b.data.categoryId]!;
        while (node.parentId != null) {
          node = categories[node.parentId]!;
        }
        return scopes.contains((node.id, b.data.month.value));
      }),
    );
  }

  static (String, String) _key(BudgetInput data) =>
      (data.categoryId, data.month.value);

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on BudgetProposalSaveFailure {
      rethrow;
    } on BudgetProposalEditFailure {
      rethrow;
    } on BudgetFailure {
      rethrow;
    } on BudgetProposalFailure {
      rethrow;
    } catch (_) {
      throw const BudgetProposalSaveFailure(
        'No se pudo guardar la propuesta. No se ha aplicado ningún cambio. '
        'La revisión se conserva para reintentar.',
        code: BudgetProposalSaveFailureCode.persistence,
      );
    }
  }
}
