import '../../../core/persistence/unit_of_work.dart';
import '../../movements/movements.dart';
import 'budget_repository.dart';

enum BudgetProposalFailureCode { invalidSourceYear, overflow, persistence }

final class BudgetProposalFailure implements Exception {
  const BudgetProposalFailure(this.message, {required this.code});
  final String message;
  final BudgetProposalFailureCode code;
  @override
  String toString() => message;
}

/// Ámbito de sustitución: una raíz y un mes destino, incluidos descendientes
/// históricos. Retirar una asignación del borrador no retira este ámbito.
final class BudgetProposalScope {
  const BudgetProposalScope({required this.rootId, required this.month});
  final String rootId;
  final BudgetMonth month;
}

/// Datos financieros que afectan al cálculo. Concepto, cuenta y procedencia
/// no afectan a la suma; cambiar fecha, categoría, importe o UUID sí la invalida.
final class BudgetProposalSourceReal {
  const BudgetProposalSourceReal({
    required this.id,
    required this.valueDate,
    required this.categoryId,
    required this.amountCents,
  });
  factory BudgetProposalSourceReal.fromRecord(MovementRecord record) =>
      BudgetProposalSourceReal(
        id: record.id,
        valueDate: record.data.valueDate.value,
        categoryId: record.data.categoryId,
        amountCents: record.data.amountCents,
      );
  final String id, valueDate;
  final String? categoryId;
  final int amountCents;
  Object get _key => (id, valueDate, categoryId, amountCents);
}

enum BudgetProposalExclusionReason { unclassified, archivedRoot }

/// Aviso no bloqueante por registro, sin asignar un UUID ficticio a Sin
/// clasificar ni mezclar una rama archivada con una raíz activa.
final class BudgetProposalExcludedReal {
  const BudgetProposalExcludedReal({
    required this.real,
    required this.reason,
    required this.categoryPath,
  });
  final BudgetProposalSourceReal real;
  final BudgetProposalExclusionReason reason;
  final String? categoryPath;
}

final class BudgetProposalRow {
  const BudgetProposalRow({
    required this.root,
    required this.sourceMonth,
    required this.targetMonth,
    required this.sourceAmountCents,
    required this.proposedAmountCents,
    required this.sourceMovementCount,
  });
  final CategoryDetails root;
  final BudgetMonth sourceMonth, targetMonth;
  final int sourceAmountCents, proposedAmountCents, sourceMovementCount;
  String get categoryId => root.node.id;
  String get categoryPath => root.path;
  bool get hasSourceReals => sourceMovementCount != 0;
  bool get requiresSignReview =>
      root.node.isIncome ? sourceAmountCents < 0 : sourceAmountCents > 0;
}

/// Instantánea comparable sin depender de una revisión global: una foto o
/// cambios en otros años no invalidan la propuesta. Releer dentro de la misma
/// transacción que el futuro guardado; una revisión igual no sustituye la lectura.
final class BudgetProposalBasis {
  BudgetProposalBasis({
    required this.sourceYear,
    required this.datasetState,
    required Iterable<CategoryDetails> categories,
    required Iterable<BudgetProposalSourceReal> sourceReals,
    required Iterable<BudgetRecord> targetBudgets,
  }) : categories = List.unmodifiable(
         categories.toList()..sort((a, b) => a.node.id.compareTo(b.node.id)),
       ),
       sourceReals = List.unmodifiable(
         sourceReals.toList()..sort((a, b) => a.id.compareTo(b.id)),
       ),
       targetBudgets = List.unmodifiable(
         targetBudgets.toList()..sort((a, b) => a.id.compareTo(b.id)),
       );

  final int sourceYear;
  final DatasetState datasetState;
  final List<CategoryDetails> categories;
  final List<BudgetProposalSourceReal> sourceReals;

  /// Solo partidas del año destino bajo las raíces incluidas, también archivadas.
  final List<BudgetRecord> targetBudgets;

  bool hasSameRelevantData(BudgetProposalBasis other) =>
      sourceYear == other.sourceYear &&
      datasetState.datasetId == other.datasetState.datasetId &&
      _same(categories.map(_categoryKey), other.categories.map(_categoryKey)) &&
      _same(
        sourceReals.map((r) => r._key),
        other.sourceReals.map((r) => r._key),
      ) &&
      _same(targetBudgets.map(_budgetKey), other.targetBudgets.map(_budgetKey));

  static Object _categoryKey(CategoryDetails c) => (
    c.node.id,
    c.node.parentId,
    c.node.name,
    c.node.isIncome,
    c.node.archived,
    c.node.depth,
    c.path,
  );
  static Object _budgetKey(BudgetRecord r) => (
    r.id,
    r.data.month.value,
    r.data.categoryId,
    r.data.amountCents,
    r.data.concept,
    r.data.discretion,
    r.importRowId,
    r.batchId,
    r.sourceOrdinal,
  );
  static bool _same(Iterable<Object> first, Iterable<Object> second) {
    final a = first.iterator;
    final b = second.iterator;
    while (a.moveNext()) {
      if (!b.moveNext() || a.current != b.current) return false;
    }
    return !b.moveNext();
  }
}

/// Borrador solo en memoria. El editor puede construir otra instancia manteniendo
/// filas fuente, ámbitos y basis, y sustituyendo allocations al editar/desglosar.
/// El constructor no autoriza guardar: T02/T03 validan signos, categorías activas
/// y solapamientos, y T03 exige confirmación y revalidación atómica.
final class BudgetProposalDraft {
  BudgetProposalDraft({
    required this.sourceYear,
    required this.targetYear,
    required Iterable<BudgetProposalRow> sourceRows,
    required Iterable<BudgetInput> allocations,
    required Iterable<BudgetProposalScope> includedScopes,
    required Iterable<BudgetProposalExcludedReal> excludedReals,
    required this.basis,
    this.signsReviewed = false,
  }) : sourceRows = List.unmodifiable(sourceRows),
       allocations = List.unmodifiable(allocations),
       includedScopes = List.unmodifiable(includedScopes),
       excludedReals = List.unmodifiable(excludedReals);
  final int sourceYear, targetYear;
  final List<BudgetProposalRow> sourceRows;
  final List<BudgetInput> allocations;
  final List<BudgetProposalScope> includedScopes;
  final List<BudgetProposalExcludedReal> excludedReals;
  final BudgetProposalBasis basis;
  final bool signsReviewed;
  bool get requiresSignReview => sourceRows.any((r) => r.requiresSignReview);
}

/// Contrato de comparación para T03; no ejecuta escrituras ni representa una
/// aprobación. before incluye partidas retiradas; after incluye ceros explícitos.
/// El plan se revalida junto con el borrador antes de aplicar su ámbito completo.
final class BudgetProposalSavePlan {
  BudgetProposalSavePlan({
    required this.draft,
    required Iterable<BudgetRecord> before,
    required Iterable<BudgetInput> after,
  }) : before = List.unmodifiable(before),
       after = List.unmodifiable(after);
  final BudgetProposalDraft draft;
  final List<BudgetRecord> before;
  final List<BudgetInput> after;
}
