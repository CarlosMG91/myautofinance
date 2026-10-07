import '../../budget/budget.dart';
import '../../movements/movements.dart';

/// Versión de las entradas comunes; independiente de la versión del lector.
const importContractVersion = '1';

enum ImportIssueCode {
  invalidFile,
  unsupportedVersion,
  emptyBatch,
  invalidOrdinal,
  invalidField,
  unresolvedReference,
  invalidResolution,
  budgetConflict,
  staleReview,
  persistence,
}

/// ordinal null identifica un problema del archivo/lote; field null, de fila.
final class ImportIssue {
  const ImportIssue({
    required this.code,
    required this.reason,
    this.sourceOrdinal,
    this.field,
  });

  final ImportIssueCode code;
  final int? sourceOrdinal;
  final String? field;
  final String reason;
}

/// Conserva valor, nombre y orden, incluso columnas con nombres repetidos.
final class ImportOriginalField {
  const ImportOriginalField(this.name, this.value);
  final String name, value;
}

enum ImportAmountConvention { economic, historicalBudget }

/// La normalización ocurre una sola vez aquí, nunca al resolver referencias.
final class ImportAmount {
  const ImportAmount.economic(int cents)
    : originalCents = cents,
      internalCents = cents,
      convention = ImportAmountConvention.economic;

  factory ImportAmount.historicalBudget(int cents) {
    if (cents == -9223372036854775808) {
      throw const BudgetFailure(
        'El importe CSV no se puede normalizar en int64.',
        code: BudgetFailureCode.invalidAmount,
      );
    }
    return ImportAmount._(cents, -cents);
  }

  const ImportAmount._(this.originalCents, this.internalCents)
    : convention = ImportAmountConvention.historicalBudget;

  final int originalCents, internalCents;
  final ImportAmountConvention convention;
}

/// Una cuenta puede venir nombrada o requerir elección para todo el archivo
/// bancario. La segunda opción es una referencia pendiente, nunca cuenta nula.
final class ImportAccountReference {
  factory ImportAccountReference.named(String name) {
    if (name.trim().isEmpty) throw ArgumentError('Cuenta vacía.');
    return ImportAccountReference._(name.trim());
  }
  const ImportAccountReference.selectedAccount() : name = null;
  const ImportAccountReference._(this.name);
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is ImportAccountReference &&
      name?.toLowerCase() == other.name?.toLowerCase();
  @override
  int get hashCode => name?.toLowerCase().hashCode ?? 0;
}

/// Ruta sin UUID: se resuelve nivel por nivel, sin asumir nombres únicos.
final class ImportCategoryReference {
  ImportCategoryReference(List<String> path)
    : path = List.unmodifiable(path.map((name) => name.trim())) {
    if (this.path.isEmpty ||
        this.path.length > 3 ||
        this.path.any((name) => name.isEmpty)) {
      throw ArgumentError('Ruta de categoría inválida.');
    }
  }

  final List<String> path;

  @override
  bool operator ==(Object other) =>
      other is ImportCategoryReference &&
      path.length == other.path.length &&
      Iterable<int>.generate(path.length)
          .every((i) => path[i].toLowerCase() == other.path[i].toLowerCase());
  @override
  int get hashCode => Object.hashAll(path.map((name) => name.toLowerCase()));
}

sealed class InterpretedImportRow {
  InterpretedImportRow({
    required this.sourceOrdinal,
    required List<ImportOriginalField> originalFields,
    required this.concept,
    required this.amount,
    this.discretion,
  }) : originalFields = List.unmodifiable(originalFields) {
    if (concept.trim().isEmpty) throw ArgumentError('Concepto vacío.');
  }

  /// >= 2; único entre los dos tipos en una misma sesión.
  final int sourceOrdinal;
  final List<ImportOriginalField> originalFields;
  final String concept;
  final ImportAmount amount;
  final String? discretion;
}

final class InterpretedMovement extends InterpretedImportRow {
  InterpretedMovement({
    required super.sourceOrdinal,
    required super.originalFields,
    required super.concept,
    required super.amount,
    required this.valueDate,
    required this.account,
    this.category,
    super.discretion,
  }) {
    if (amount.internalCents == 0 ||
        amount.convention != ImportAmountConvention.economic) {
      throw ArgumentError('REAL exige importe económico distinto de cero.');
    }
  }

  final ValueDate valueDate;
  final ImportAccountReference account;
  final ImportCategoryReference? category;

  /// Solo tras resolver; UUID/elegibilidad se revalidan contra la base vigente.
  MovementInput toMovementInput({
    required String accountId,
    String? categoryId,
  }) {
    if (accountId.trim().isEmpty ||
        (category != null &&
            (categoryId == null || categoryId.trim().isEmpty)) ||
        (categoryId != null && categoryId.trim().isEmpty)) {
      throw ArgumentError('Referencias REAL sin resolver.');
    }
    return MovementInput(
      accountId: accountId,
      valueDate: valueDate,
      concept: concept,
      amountCents: amount.internalCents,
      categoryId: categoryId,
      discretion: discretion,
    );
  }
}

final class InterpretedBudget extends InterpretedImportRow {
  InterpretedBudget({
    required super.sourceOrdinal,
    required super.originalFields,
    required super.concept,
    required super.amount,
    required this.month,
    required this.category,
    super.discretion,
  });

  final BudgetMonth month;
  final ImportCategoryReference category;

  /// Ya normalizado: no llamar de nuevo a BudgetInput.fromHistoricalCsv.
  BudgetInput toBudgetInput({required String categoryId}) {
    if (categoryId.trim().isEmpty) {
      throw ArgumentError('Categoría presupuestaria sin resolver.');
    }
    return BudgetInput(
      month: month,
      categoryId: categoryId,
      amountCents: amount.internalCents,
      concept: concept,
      discretion: discretion,
    );
  }
}
