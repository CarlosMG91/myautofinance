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

enum MovementCategoryScope { direct, branch }

/// Una página y el subtotal firmado de todos los resultados filtrados.
/// Reutilizar el cursor únicamente con los mismos filtros y una base estable.
final class MovementPage {
  MovementPage({
    required List<MovementRecord> records,
    required this.subtotalCents,
    required this.nextCursor,
  }) : records = List.unmodifiable(records);

  final List<MovementRecord> records;
  final int subtotalCents;
  final MovementCursor? nextCursor;
}

abstract interface class MovementRepository {
  /// Lecturas completas, sin límite de paginación. categoryId selecciona
  /// el nodo y toda su rama; null incluye también los no clasificados.
  /// Cada movimiento aparece una sola vez, conservando su nodo directo.
  Future<List<MovementRecord>> readMonth(
    int year,
    int month, {
    String? categoryId,
  });
  Future<List<MovementRecord>> readYear(int year, {String? categoryId});

  Future<MovementRecord> create(MovementInput data);
  Future<MovementRecord?> get(String id);

  /// Cambia datos financieros; conserva discrecionalidad y procedencia.
  Future<MovementRecord> edit(String id, MovementInput data);

  /// Permite cambiar o retirar expresamente la discrecionalidad.
  Future<void> setDiscretion(String id, String? discretion);
  Future<void> delete(String id);

  /// [from, until), fecha descendente y UUID ascendente. until null para 9999.
  /// Concepto como subcadena literal sin mayúsculas ni marcas Unicode.
  /// Categoría concreta y unclassifiedOnly son mutuamente excluyentes.
  Future<List<MovementRecord>> list({
    required ValueDate from,
    required ValueDate? until,
    String? accountId,
    String? categoryId,
    MovementCategoryScope categoryScope = MovementCategoryScope.direct,
    bool unclassifiedOnly = false,
    String? concept,
    MovementCursor? after,
    int limit = 100,
  });

  /// Página y subtotal en una misma transacción de lectura. El subtotal ignora
  /// cursor y límite, vale cero sin resultados y falla si desborda int64.
  /// nextCursor es null al terminar. No mantiene un snapshot entre llamadas:
  /// tras escrituras o cambios de filtros se debe reiniciar la lectura.
  Future<MovementPage> readPage({
    required ValueDate from,
    required ValueDate? until,
    String? accountId,
    String? categoryId,
    MovementCategoryScope categoryScope = MovementCategoryScope.direct,
    bool unclassifiedOnly = false,
    String? concept,
    MovementCursor? after,
    int limit = 100,
  });
}
