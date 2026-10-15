import '../../wealth/wealth.dart' show Month, WealthReading;
import 'indicator_definition.dart';

/// Suma firmada ya normalizada, solo de ramas cuya raíz actual es ingreso.
/// La presencia procede de partidas explícitas (también cero), no del total
/// mensual ni del número de filas. El proveedor no inventa meses presentes.
final class AnnualIncomeBudget {
  AnnualIncomeBudget({
    required this.year,
    required this.totalCents,
    required Set<int> presentMonths,
  }) : presentMonths = Set.unmodifiable(presentMonths) {
    if (year < 1 ||
        year > 9999 ||
        presentMonths.any((month) => month < 1 || month > 12)) {
      throw ArgumentError('Año o meses de ingresos inválidos.');
    }
  }

  final int year;
  final BigInt totalCents;
  final Set<int> presentMonths;
  List<int> get pendingMonths => List.unmodifiable([
    for (var month = 1; month <= 12; month++)
      if (!presentMonths.contains(month)) month,
  ]);
  bool get isComplete => presentMonths.length == 12;
}

/// Foto manual EP-009/017 sin proyectar ni recalcular saldos. WealthReading
/// conserva estado, fichas pendientes y líquidos solo con foto completa.
/// null significa entrada no solicitada, nunca ausencia financiera de foto.
final class IndicatorInputs {
  const IndicatorInputs({required this.month, this.wealth, this.annualIncome});

  final Month month;
  final WealthReading? wealth;
  final AnnualIncomeBudget? annualIncome;
}

enum IndicatorReadFailureCode { read, invalidInputs }

/// Fallo técnico fuera de IndicatorResult: no es un motivo financiero.
final class IndicatorReadFailure implements Exception {
  const IndicatorReadFailure({
    required this.code,
    required this.message,
    this.cause,
  });

  final IndicatorReadFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract interface class IndicatorInputProvider {
  /// Una lectura coherente del mes elegido y del año de ese mismo mes.
  /// Los estados absent/incomplete son WealthReading reales; un fallo técnico
  /// lanza IndicatorReadFailure. No usar la matriz EP-021 para completar datos.
  Future<IndicatorInputs> read(Month month, Set<IndicatorInput> requiredInputs);
}
