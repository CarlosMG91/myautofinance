/// Fecha civil, sin conversión de zona horaria.
final class ValueDate implements Comparable<ValueDate> {
  ValueDate(int year, int month, int day) {
    final date = DateTime.utc(year, month, day);
    if (year < 1 ||
        year > 9999 ||
        date.year != year ||
        date.month != month ||
        date.day != day) {
      throw const MovementFailure('Fecha de valor inválida.');
    }
    value =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }
  factory ValueDate.parse(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const MovementFailure('Fecha de valor inválida.');
    }
    return ValueDate(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(5, 7)),
      int.parse(value.substring(8)),
    );
  }
  late final String value;
  @override
  int compareTo(ValueDate other) => value.compareTo(other.value);
}

final class MovementFailure implements Exception {
  const MovementFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

final class MovementInput {
  const MovementInput({
    required this.accountId,
    required this.valueDate,
    required this.concept,
    required this.amountCents,
    this.categoryId,
    this.discretion,
  });
  final String accountId, concept;
  final ValueDate valueDate;
  final int amountCents;
  final String? categoryId, discretion;
}

final class MovementRecord {
  const MovementRecord({
    required this.id,
    required this.data,
    this.importRowId,
    this.batchId,
    this.sourceOrdinal,
  });
  final String id;
  final MovementInput data;
  final String? importRowId, batchId;
  final int? sourceOrdinal;
}

final class MovementCursor {
  const MovementCursor(this.valueDate, this.id);
  final ValueDate valueDate;
  final String id;
}

abstract interface class MovementRepository {
  Future<MovementRecord> create(MovementInput data);
  Future<MovementRecord?> get(String id);

  /// Cambia datos financieros; conserva discrecionalidad y procedencia.
  Future<MovementRecord> edit(String id, MovementInput data);

  /// Permite cambiar o retirar expresamente la discrecionalidad.
  Future<void> setDiscretion(String id, String? discretion);
  Future<void> delete(String id);

  /// [from, until), orden estable por fecha e identidad. until null para 9999.
  Future<List<MovementRecord>> list({
    required ValueDate from,
    required ValueDate? until,
    String? accountId,
    String? categoryId,
    bool unclassifiedOnly = false,
    MovementCursor? after,
    int limit = 100,
  });
}
