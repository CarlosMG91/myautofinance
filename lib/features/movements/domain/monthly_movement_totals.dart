/// Suma directa y número de registros por categoría UUID (null: Sin clasificar).
/// El contador conserva el origen incluso cuando los importes se compensan.
final class MonthlyMovementTotal {
  const MonthlyMovementTotal({
    required this.categoryId,
    required this.amountCents,
    required this.movementCount,
  });

  final String? categoryId;
  final int amountCents, movementCount;
}

/// Lectura agregada por fecha de valor, todas las cuentas, sin cargar registros.
/// Invocar sobre la conexión de la transacción que lee árbol y presupuesto.
/// Una suma directa fuera de int64 produce MovementTotalsOverflow.
abstract interface class MonthlyMovementTotalsReader {
  Future<List<MonthlyMovementTotal>> readMonthTotals(int year, int month);
}

final class MovementTotalsOverflow implements Exception {
  const MovementTotalsOverflow();
  @override
  String toString() => 'El subtotal de movimientos excede el rango int64.';
}
