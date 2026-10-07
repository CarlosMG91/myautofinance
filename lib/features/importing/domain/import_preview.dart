import '../../budget/budget.dart';
import '../../movements/movements.dart';
import '../../wealth/wealth.dart';
import 'import_creation.dart';
import 'import_session.dart';
import 'interpreted_import.dart';

/// Catálogos completos y registros de todos los meses presentes en la sesión.
/// El proveedor entrega una instantánea coherente sin transacción de escritura.
final class ImportPreviewSnapshot {
  ImportPreviewSnapshot({
    required List<AccountRecord> accounts,
    required List<CategoryNode> categories,
    required List<MovementRecord> movements,
    required List<BudgetRecord> budgets,
    this.sameFileBatchId,
  }) : accounts = List.unmodifiable(accounts),
       categories = List.unmodifiable(categories),
       movements = List.unmodifiable(movements),
       budgets = List.unmodifiable(budgets);
  final List<AccountRecord> accounts;
  final List<CategoryNode> categories;
  final List<MovementRecord> movements;
  final List<BudgetRecord> budgets;
  final String? sameFileBatchId;
}

abstract interface class ImportPreviewSource {
  Future<ImportPreviewSnapshot> read(ImportSession session);
}

/// Resolución y validación de todo el lote. No dispone de métodos de escritura.
final class ValidatingImportPreviewer implements ImportPreviewer {
  const ValidatingImportPreviewer(this.source);
  final ImportPreviewSource source;

  @override
  Future<ImportReview> preview(
    ImportSession session, {
    ImportReferenceBindings? bindings,
  }) async {
    try {
      return _Preview(
        session,
        bindings ?? ImportReferenceBindings(),
        await source.read(session),
      ).run();
    } catch (_) {
      return ImportReview(
        session: session,
        bindings: bindings,
        issues: [
          ...session.issues,
          const ImportIssue(
            code: ImportIssueCode.persistence,
            reason: 'No se pudo leer la base para revisar el lote. Inténtalo de nuevo.',
          ),
        ],
      );
    }
  }
}

String _key(String value) => value.trim().toLowerCase();

final class _Preview {
  _Preview(this.session, this.input, this.snapshot);
  final ImportSession session;
  final ImportReferenceBindings input;
  final ImportPreviewSnapshot snapshot;
  final issues = <ImportIssue>[];
  final pending = <ImportPendingReference>[];
  final overlaps = <ImportOverlap>[];
  final accounts = <ImportAccountReference, String>{};
  final categories = <ImportCategoryReference, String>{};
  final accountRows = <ImportAccountReference, List<int>>{};
  final categoryRows = <ImportCategoryReference, List<int>>{};
  late final nodes = {for (final n in snapshot.categories) n.id: n};
  late final accountNodes = {for (final n in snapshot.accounts) n.id: n};
  final validPlans = <ImportCategoryReference, bool>{};
  final visiting = <ImportCategoryReference>{};

  void error(
    ImportIssueCode code,
    String field,
    String reason, [
    int? ordinal,
  ]) {
    issues.add(
      ImportIssue(
        code: code,
        field: field,
        reason: reason,
        sourceOrdinal: ordinal,
      ),
    );
  }

  ImportReview run() {
    issues.addAll(session.issues);
    for (final row in session.interpretation.rows) {
      if (row is InterpretedMovement) {
        (accountRows[row.account] ??= []).add(row.sourceOrdinal);
      }
      final ref = switch (row) {
        InterpretedMovement() => row.category,
        InterpretedBudget() => row.category,
      };
      if (ref != null) (categoryRows[ref] ??= []).add(row.sourceOrdinal);
    }
    for (final entry in accountRows.entries) {
      final ref = entry.key;
      final explicit = input.accounts[ref];
      final creation = input.newAccounts[ref];
      if (explicit != null && creation != null) {
        _referenceError(
          entry.value,
          'cuenta',
          'Elige vincular o crear la cuenta, una sola opción.',
        );
      } else if (creation != null) {
        if (creation.name.trim().isEmpty ||
            (creation.activeThrough != null &&
                creation.activeThrough!.compareTo(creation.activeFrom) < 0)) {
          _referenceError(
            entry.value,
            'cuenta',
            'Nombre o vigencia de la cuenta nueva inválidos.',
          );
        }
      } else if (explicit != null) {
        final candidate = accountNodes[explicit];
        if (candidate == null || candidate.kind != AccountKind.account) {
          _referenceError(
            entry.value,
            'cuenta',
            'La cuenta elegida no existe o no es una cuenta corriente.',
          );
        } else {
          accounts[ref] = explicit;
        }
      } else {
        final candidates = snapshot.accounts
            .where(
              (a) =>
                  a.kind == AccountKind.account &&
                  ref.name != null &&
                  _key(a.name) == _key(ref.name!),
            )
            .toList();
        if (candidates.length == 1) {
          accounts[ref] = candidates.single.id;
        } else {
          pending.add(
            ImportPendingReference(
              reference: PendingImportAccount(ref),
              sourceOrdinals: entry.value,
              candidateIds: candidates.map((a) => a.id).toList(),
              reason: candidates.isEmpty
                  ? 'Selecciona o prepara una cuenta.'
                  : 'Cuenta ambigua: selecciona un UUID expresamente.',
            ),
          );
        }
      }
    }
    for (final entry in categoryRows.entries) {
      final ref = entry.key;
      if (input.categories.containsKey(ref) &&
          input.newCategories.containsKey(ref)) {
        _referenceError(
          entry.value,
          'categoría',
          'Elige vincular o crear la categoría, una sola opción.',
        );
      } else if (input.newCategories.containsKey(ref)) {
        _validatePlan(ref);
      } else if (input.categories.containsKey(ref)) {
        final node = nodes[input.categories[ref]];
        if (node == null || node.archived) {
          _referenceError(
            entry.value,
            'categoría',
            'La categoría elegida no existe o está archivada.',
          );
        } else {
          categories[ref] = node.id;
        }
      } else {
        var candidates = <CategoryNode>[];
        Set<String?> parents = {null};
        for (final name in ref.path) {
          candidates = snapshot.categories
              .where(
                (n) =>
                    parents.contains(n.parentId) && _key(n.name) == _key(name),
              )
              .toList();
          parents = candidates.map((n) => n.id).toSet();
        }
        // No descartar archivadas para escoger silenciosamente otra identidad.
        if (candidates.length == 1 && !candidates.single.archived) {
          categories[ref] = candidates.single.id;
        } else {
          pending.add(
            ImportPendingReference(
              reference: PendingImportCategory(ref),
              sourceOrdinals: entry.value,
              candidateIds: candidates.map((n) => n.id).toList(),
              reason: candidates.isEmpty ? 'Vincula o prepara la categoría.' : 'Selecciona una categoría activa expresamente; la referencia es ambigua o está archivada.',
            ),
          );
        }
      }
    }
    // También se validan los antecesores propuestos, aunque no tengan filas.
    for (final ref in input.newCategories.keys) {
      _validatePlan(ref);
      if (input.categories.containsKey(ref)) {
        _referenceError(
          categoryRows[ref] ?? [],
          'categoría',
          'Un plan no puede estar vinculado también a un UUID.',
        );
      }
    }
    for (final ref in input.newAccounts.keys) {
      if (!accountRows.containsKey(ref)) {
        error(
          ImportIssueCode.invalidResolution,
          'cuenta',
          'El plan de cuenta no está usado por ninguna fila.',
        );
      }
    }
    final usedCategoryPlans = <ImportCategoryReference>{};
    for (final ref in categoryRows.keys) {
      if (input.newCategories.containsKey(ref)) {
        usedCategoryPlans.addAll(
          _ancestors(ImportCategoryTarget.proposed(ref))
              .map((t) => t.proposedReference)
              .whereType<ImportCategoryReference>(),
        );
      }
    }
    for (final ref in input.newCategories.keys) {
      if (!usedCategoryPlans.contains(ref)) {
        error(
          ImportIssueCode.invalidResolution,
          'categoría',
          'El plan de categoría no está usado por filas ni por sus antecesores.',
        );
      }
    }
    final resolved = ImportReferenceBindings(
      accounts: accounts,
      categories: categories,
      newAccounts: input.newAccounts,
      newCategories: input.newCategories,
    );
    _validateRows(resolved);
    _validateBudgets(resolved);
    return ImportReview(
      session: session,
      bindings: resolved,
      issues: issues,
      pendingReferences: pending,
      overlaps: overlaps,
    );
  }

  void _referenceError(List<int> ordinals, String field, String reason) {
    if (ordinals.isEmpty) {
      error(ImportIssueCode.invalidResolution, field, reason);
    }
    for (final ordinal in ordinals) {
      error(ImportIssueCode.invalidResolution, field, reason, ordinal);
    }
  }

  bool _validatePlan(ImportCategoryReference ref) {
    if (validPlans.containsKey(ref)) return validPlans[ref]!;
    if (!visiting.add(ref)) {
      _referenceError(
        categoryRows[ref] ?? [],
        'categoría',
        'El plan de categorías contiene un ciclo.',
      );
      return false;
    }
    final plan = input.newCategories[ref];
    var valid = plan != null;
    if (plan != null) {
      if (plan.name.trim().isEmpty ||
          (plan.parent == null && plan.isIncome == null) ||
          (plan.parent != null && plan.isIncome != null)) {
        valid = false;
        _referenceError(
          categoryRows[ref] ?? [],
          'categoría',
          'El nombre es obligatorio; elige Ingreso/Salida solo en la raíz nueva.',
        );
      }
      final parent = plan.parent;
      if (parent?.existingId != null) {
        final node = nodes[parent!.existingId];
        if (node == null || node.archived) {
          valid = false;
          _referenceError(
            categoryRows[ref] ?? [],
            'categoría',
            'El padre no existe o está archivado.',
          );
        }
      } else if (parent?.proposedReference != null) {
        if (!_validatePlan(parent!.proposedReference!)) {
          valid = false;
          _referenceError(
            categoryRows[ref] ?? [],
            'categoría',
            'El padre propuesto no es válido; resuelve su plan antes de confirmar.',
          );
        }
      }
      if (valid && _ancestors(ImportCategoryTarget.proposed(ref)).length > 3) {
        valid = false;
        _referenceError(
          categoryRows[ref] ?? [],
          'categoría',
          'Solo se permiten tres niveles de categorías.',
        );
      }
    } else {
      _referenceError(
        categoryRows[ref] ?? [],
        'categoría',
        'Falta el plan del padre propuesto.',
      );
    }
    visiting.remove(ref);
    return validPlans[ref] = valid;
  }

  Set<ImportCategoryTarget> _ancestors(ImportCategoryTarget target) {
    final result = <ImportCategoryTarget>{};
    ImportCategoryTarget? current = target;
    while (current != null && result.add(current)) {
      if (current.existingId != null) {
        final parentId = nodes[current.existingId]?.parentId;
        current = parentId == null
            ? null
            : ImportCategoryTarget.existing(parentId);
      } else {
        current = input.newCategories[current.proposedReference]?.parent;
      }
    }
    return result;
  }

  void _validateRows(ImportReferenceBindings resolved) {
    for (final row
        in session.interpretation.rows.whereType<InterpretedMovement>()) {
      final account = accountNodes[resolved.accounts[row.account]];
      final plan = resolved.newAccounts[row.account];
      final from = account?.activeFrom ?? plan?.activeFrom;
      final through = account?.activeThrough ?? plan?.activeThrough;
      final month = '${row.valueDate.value.substring(0, 7)}-01';
      if (from != null &&
          (month.compareTo(from.value) < 0 ||
              (through != null && month.compareTo(through.value) > 0))) {
        error(
          ImportIssueCode.invalidResolution,
          'cuenta',
          'La cuenta no está vigente en el mes de la fecha de valor.',
          row.sourceOrdinal,
        );
      }
      if (account == null) continue;
      for (final existing in snapshot.movements) {
        if (existing.batchId == null ||
            existing.batchId == snapshot.sameFileBatchId) {
          continue;
        }
        final data = existing.data;
        if (data.accountId == account.id &&
            data.valueDate.value == row.valueDate.value &&
            data.amountCents == row.amount.internalCents &&
            _key(data.concept) == _key(row.concept)) {
          overlaps.add(
            ImportOverlap(
              sourceOrdinal: row.sourceOrdinal,
              existingMovementId: existing.id,
            ),
          );
        }
      }
    }
  }

  void _validateBudgets(ImportReferenceBindings resolved) {
    final rows = session.interpretation.rows
        .whereType<InterpretedBudget>()
        .toList();
    bool conflict(ImportCategoryTarget a, ImportCategoryTarget b) =>
        _ancestors(a).contains(b) || _ancestors(b).contains(a);
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final target = resolved.categoryTarget(row.category);
      if (target == null) continue;
      for (var j = i + 1; j < rows.length; j++) {
        final other = rows[j];
        final otherTarget = resolved.categoryTarget(other.category);
        if (row.month.value == other.month.value &&
            otherTarget != null &&
            conflict(target, otherTarget)) {
          for (final pair in [(row, other), (other, row)]) {
            error(
              ImportIssueCode.budgetConflict,
              'categoría',
              'Conflicto en ${row.month.value}: mismo nodo o padre/descendiente con ordinal ${pair.$2.sourceOrdinal}.',
              pair.$1.sourceOrdinal,
            );
          }
        }
      }
      for (final existing in snapshot.budgets) {
        if (existing.batchId != null &&
            existing.batchId == snapshot.sameFileBatchId) {
          continue;
        }
        if (existing.data.month.value == row.month.value &&
            conflict(
              target,
              ImportCategoryTarget.existing(existing.data.categoryId),
            )) {
          error(
            ImportIssueCode.budgetConflict,
            'categoría',
            'Conflicto en ${row.month.value} con partida ${existing.id}: mismo nodo o padre/descendiente.',
            row.sourceOrdinal,
          );
        }
      }
    }
  }
}
