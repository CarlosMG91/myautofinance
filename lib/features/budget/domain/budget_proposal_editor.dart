import '../../movements/movements.dart';
import 'budget_proposal.dart';
import 'budget_repository.dart';

enum BudgetProposalEditFailureCode {
  sessionClosed,
  invalidDraft,
  allocationNotFound,
  categoryNotFound,
  categoryArchived,
  invalidSplit,
  totalChangeRequiresEdit,
  totalMismatch,
  overflow,
  duplicateCategoryMonth,
  ancestorDescendantConflict,
  signsNotReviewed,
}

final class BudgetProposalEditFailure implements Exception {
  const BudgetProposalEditFailure(this.message, {required this.code});
  final String message;
  final BudgetProposalEditFailureCode code;
  @override
  String toString() => message;
}

/// El mes se hereda del padre; el nombre no se usa como identidad.
final class BudgetProposalSplitAllocation {
  const BudgetProposalSplitAllocation({
    required this.categoryId,
    required this.amountCents,
  });
  final String categoryId;
  final int amountCents;
}

/// Validación pura reutilizable antes del guardado. No certifica concurrencia
/// ni sustituye la relectura y transacción de T03.
final class BudgetProposalDraftValidator {
  const BudgetProposalDraftValidator();

  void validate(BudgetProposalDraft draft, {bool requireSignReview = true}) {
    if (draft.sourceYear < 1 ||
        draft.sourceYear >= 9999 ||
        draft.targetYear != draft.sourceYear + 1 ||
        draft.basis.sourceYear != draft.sourceYear) {
      _fail('El año del borrador no es válido.');
    }
    final tree = _ProposalTree(draft.basis.categories);
    final scopes = <(String, String)>{};
    for (final scope in draft.includedScopes) {
      final root = tree.activeLineage(scope.rootId).last;
      if (root.node.id != scope.rootId ||
          !_inYear(scope.month, draft.targetYear) ||
          !scopes.add((scope.rootId, scope.month.value))) {
        _fail('El ámbito del borrador no es válido.');
      }
    }
    final byMonth = <String, Set<String>>{};
    for (final allocation in draft.allocations) {
      final lineage = tree.activeLineage(allocation.categoryId);
      if (!_inYear(allocation.month, draft.targetYear) ||
          !scopes.contains((lineage.last.node.id, allocation.month.value))) {
        _fail('La partida queda fuera de los ámbitos de la propuesta.');
      }
      final ids = byMonth.putIfAbsent(allocation.month.value, () => <String>{});
      if (!ids.add(allocation.categoryId)) {
        _fail(
          'La categoría ${lineage.first.path} ya tiene partida en '
          '${allocation.month.value}.',
          BudgetProposalEditFailureCode.duplicateCategoryMonth,
        );
      }
    }
    for (final entry in byMonth.entries) {
      for (final id in entry.value) {
        for (final ancestor in tree.activeLineage(id).skip(1)) {
          if (entry.value.contains(ancestor.node.id)) {
            _fail(
              'No pueden coexistir ${tree.category(id).path} y '
              '${ancestor.path} en ${entry.key}.',
              BudgetProposalEditFailureCode.ancestorDescendantConflict,
            );
          }
        }
      }
    }
    if (requireSignReview && draft.requiresSignReview && !draft.signsReviewed) {
      _fail(
        'Marca «He revisado los signos señalados» antes de continuar.',
        BudgetProposalEditFailureCode.signsNotReviewed,
      );
    }
  }

  static bool _inYear(BudgetMonth month, int year) =>
      int.parse(month.value.substring(0, 4)) == year;
}

/// Una instancia por sesión, sin repositorios, callbacks de guardado o disco.
/// Las operaciones rechazadas conservan exactamente el borrador anterior.
final class BudgetProposalEditor {
  BudgetProposalEditor(BudgetProposalDraft draft) {
    _validator.validate(draft, requireSignReview: false);
    _draft = draft;
  }

  static const _validator = BudgetProposalDraftValidator();
  BudgetProposalDraft? _draft;
  bool get isClosed => _draft == null;
  BudgetProposalDraft get draft =>
      _draft ??
      (throw const BudgetProposalEditFailure(
        'La sesión de propuesta está cerrada.',
        code: BudgetProposalEditFailureCode.sessionClosed,
      ));

  /// No redondea ni transforma esta cifra en un real; cero es una partida.
  void editAmount({
    required BudgetMonth month,
    required String categoryId,
    required int amountCents,
  }) {
    final old = draft;
    final index = _index(old, month, categoryId);
    final allocation = old.allocations[index];
    if (allocation.amountCents == amountCents) return;
    final next = old.allocations.toList();
    next[index] = BudgetInput(
      month: allocation.month,
      categoryId: allocation.categoryId,
      amountCents: amountCents,
      concept: allocation.concept,
      discretion: allocation.discretion,
    );
    _replace(old, next, signsReviewed: false);
  }

  List<CategoryDetails> splitOptions({
    required BudgetMonth month,
    required String parentCategoryId,
  }) {
    final old = draft;
    _index(old, month, parentCategoryId);
    final tree = _ProposalTree(old.basis.categories);
    final options =
        tree.categories.values.where((category) {
          if (category.node.archived) return false;
          final lineage = tree.lineage(category.node.id);
          return lineage.every((c) => !c.node.archived) &&
              lineage.skip(1).any((c) => c.node.id == parentCategoryId);
        }).toList()..sort((a, b) {
          final path = a.path.compareTo(b.path);
          return path == 0 ? a.node.id.compareTo(b.node.id) : path;
        });
    return List.unmodifiable(options);
  }

  /// Confirmar el desglose es una operación de memoria. Si cambia la suma,
  /// el consumidor debe aportar el nuevo total editado expresamente; no basta
  /// con aprobar una diferencia calculada ni ajustar un hijo automáticamente.
  void split({
    required BudgetMonth month,
    required String parentCategoryId,
    required Iterable<BudgetProposalSplitAllocation> allocations,
    int? explicitlyEditedTotalCents,
  }) {
    final old = draft;
    final index = _index(old, month, parentCategoryId);
    final parent = old.allocations[index];
    final children = allocations.toList();
    if (children.isEmpty) {
      _fail(
        'Elige al menos un descendiente para desglosar.',
        BudgetProposalEditFailureCode.invalidSplit,
      );
    }
    final tree = _ProposalTree(old.basis.categories);
    var total = BigInt.zero;
    for (final child in children) {
      final lineage = tree.activeLineage(child.categoryId);
      if (!lineage.skip(1).any((c) => c.node.id == parentCategoryId)) {
        _fail(
          '${lineage.first.path} no es descendiente de '
          '${tree.category(parentCategoryId).path}.',
          BudgetProposalEditFailureCode.invalidSplit,
        );
      }
      total += BigInt.from(child.amountCents);
    }
    if (total < BigInt.parse('-9223372036854775808') ||
        total > BigInt.parse('9223372036854775807')) {
      _fail(
        'El total del desglose excede el rango de céntimos permitido.',
        BudgetProposalEditFailureCode.overflow,
      );
    }
    if (explicitlyEditedTotalCents == null &&
        total != BigInt.from(parent.amountCents)) {
      _fail(
        'Conserva el total anterior o edita explícitamente el nuevo total.',
        BudgetProposalEditFailureCode.totalChangeRequiresEdit,
      );
    }
    if (explicitlyEditedTotalCents != null &&
        total != BigInt.from(explicitlyEditedTotalCents)) {
      _fail(
        'La suma del desglose no coincide con el nuevo total editado.',
        BudgetProposalEditFailureCode.totalMismatch,
      );
    }
    final next = old.allocations.toList()..removeAt(index);
    next.insertAll(
      index,
      children.map(
        (child) => BudgetInput(
          month: parent.month,
          categoryId: child.categoryId,
          amountCents: child.amountCents,
        ),
      ),
    );
    _replace(old, next, signsReviewed: false);
  }

  /// Corresponde a la casilla «He revisado los signos señalados». Nunca se
  /// marca automáticamente después de editar o desglosar.
  void setSignsReviewed(bool reviewed) {
    final old = draft;
    _replace(old, old.allocations, signsReviewed: reviewed);
  }

  /// Solo valida y entrega la instantánea; T03 confirma y revalida al guardar.
  BudgetProposalDraft validatedDraft() {
    final current = draft;
    _validator.validate(current);
    return current;
  }

  void cancel() => _draft = null;

  int _index(BudgetProposalDraft old, BudgetMonth month, String id) {
    final index = old.allocations.indexWhere(
      (a) => a.categoryId == id && a.month.value == month.value,
    );
    if (index == -1) {
      _fail(
        'La partida solicitada no existe en el borrador de ese mes.',
        BudgetProposalEditFailureCode.allocationNotFound,
      );
    }
    return index;
  }

  void _replace(
    BudgetProposalDraft old,
    Iterable<BudgetInput> allocations, {
    required bool signsReviewed,
  }) {
    final next = BudgetProposalDraft(
      sourceYear: old.sourceYear,
      targetYear: old.targetYear,
      sourceRows: old.sourceRows,
      allocations: allocations,
      includedScopes: old.includedScopes,
      excludedReals: old.excludedReals,
      basis: old.basis,
      signsReviewed: signsReviewed,
    );
    _validator.validate(next, requireSignReview: false);
    _draft = next;
  }
}

final class _ProposalTree {
  _ProposalTree(Iterable<CategoryDetails> values) {
    for (final value in values) {
      if (categories.containsKey(value.node.id)) {
        _fail('El árbol contiene UUID duplicados.');
      }
      categories[value.node.id] = value;
    }
  }
  final categories = <String, CategoryDetails>{};
  CategoryDetails category(String id) =>
      categories[id] ??
      (throw const BudgetProposalEditFailure(
        'La categoría no existe.',
        code: BudgetProposalEditFailureCode.categoryNotFound,
      ));

  List<CategoryDetails> lineage(String id) {
    final result = <CategoryDetails>[];
    final seen = <String>{};
    String? current = id;
    while (current != null) {
      if (!seen.add(current) || result.length == 3) {
        _fail('El árbol debe ser acíclico y tener como máximo tres niveles.');
      }
      final item = category(current);
      result.add(item);
      current = item.node.parentId;
    }
    for (var index = 0; index < result.length; index++) {
      if (result[index].node.depth != result.length - index) {
        _fail('La profundidad de la categoría no es válida.');
      }
    }
    return result;
  }

  List<CategoryDetails> activeLineage(String id) {
    final result = lineage(id);
    if (result.any((c) => c.node.archived)) {
      _fail(
        'No se puede asignar a la categoría archivada ${result.first.path}.',
        BudgetProposalEditFailureCode.categoryArchived,
      );
    }
    return result;
  }
}

Never _fail(
  String message, [
  BudgetProposalEditFailureCode code =
      BudgetProposalEditFailureCode.invalidDraft,
]) => throw BudgetProposalEditFailure(message, code: code);
