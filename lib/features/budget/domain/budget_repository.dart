/// Mes civil independiente de cuentas y zonas horarias.
final class BudgetMonth {
  BudgetMonth(int year, int month) {
    if (year < 1 || year > 9999 || month < 1 || month > 12) {
      throw const BudgetFailure('Mes inválido.');
    }
    value =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-01';
  }
  factory BudgetMonth.parse(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-01$').hasMatch(value)) {
      throw const BudgetFailure('Mes inválido.');
    }
    return BudgetMonth(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(5, 7)),
    );
  }
  late final String value;
}

final class BudgetFailure implements Exception {
  const BudgetFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

final class BudgetInput {
  const BudgetInput({
    required this.month,
    required this.categoryId,
    required this.amountCents,
    this.concept,
    this.discretion,
  });

  /// El CSV usa el signo opuesto. Rechaza int64 mínimo antes de negarlo.
  factory BudgetInput.fromHistoricalCsv({
    required BudgetMonth month,
    required String categoryId,
    required int csvAmountCents,
    String? concept,
    String? discretion,
  }) {
    if (csvAmountCents == -9223372036854775808) {
      throw const BudgetFailure(
        'El importe CSV no se puede normalizar en int64.',
      );
    }
    return BudgetInput(
      month: month,
      categoryId: categoryId,
      amountCents: -csvAmountCents,
      concept: concept,
      discretion: discretion,
    );
  }
  final BudgetMonth month;
  final String categoryId;
  final int amountCents;
  final String? concept, discretion;
}

final class BudgetRecord {
  const BudgetRecord({
    required this.id,
    required this.data,
    this.importRowId,
    this.batchId,
    this.sourceOrdinal,
  });
  final String id;
  final BudgetInput data;
  final String? importRowId, batchId;
  final int? sourceOrdinal;
}

abstract interface class BudgetRepository {
  Future<BudgetRecord> create(BudgetInput data);
  Future<BudgetRecord> edit(String id, BudgetInput data);
  Future<void> delete(String id);
  Future<BudgetRecord?> get(String id);

  /// Devuelve partidas explícitas, incluido cero; no materializa ausencias.
  Future<List<BudgetRecord>> list(BudgetMonth month);
}
