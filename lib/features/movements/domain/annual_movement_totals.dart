/// Subtotal directo por mes de fecha de valor y UUID (null: Sin clasificar).
/// Un neto cero mantiene el contador de sus movimientos origen.
final class AnnualMovementTotal {
  const AnnualMovementTotal({
    required this.month,
    required this.categoryId,
    required this.amountCents,
    required this.movementCount,
  });

  final int month;
  final String? categoryId;
  final int amountCents, movementCount;
}

/// Una consulta agregada de todas las cuentas, sin cargar registros ni hacer
/// doce lecturas mensuales. Compartir transacción con árbol e identidad/base.
/// Una suma directa fuera de int64 produce MovementTotalsOverflow.
abstract interface class AnnualMovementTotalsReader {
  Future<List<AnnualMovementTotal>> readYearTotals(int year);
}
