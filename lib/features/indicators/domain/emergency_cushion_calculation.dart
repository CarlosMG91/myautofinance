import '../../wealth/wealth.dart' show WealthSnapshotStatus;
import 'indicator_catalog.dart';
import 'indicator_engine.dart';
import 'indicator_inputs.dart';
import 'indicator_result.dart';

/// Colchón de emergencia v1. No consulta repositorios ni modifica entradas.
final class EmergencyCushionCalculation implements IndicatorCalculation {
  const EmergencyCushionCalculation();

  static final _definition = IndicatorCatalog.v1().definition(
    'colchon_emergencia',
  );

  @override
  IndicatorResult calculate(IndicatorInputs inputs) {
    final wealth = inputs.wealth;
    final income = inputs.annualIncome;
    // También protege el uso directo de esta función fuera del motor.
    if (wealth == null ||
        income == null ||
        wealth.month.value != inputs.month.value ||
        income.year != int.parse(inputs.month.value.substring(0, 4))) {
      throw const IndicatorReadFailure(
        code: IndicatorReadFailureCode.invalidInputs,
        message: 'Las entradas no corresponden al periodo o faltan lecturas.',
      );
    }

    switch (wealth.status) {
      case WealthSnapshotStatus.absent:
        return _unavailable(
          'foto_ausente',
          IndicatorMissingDetail(pendingAccounts: wealth.pending),
        );
      case WealthSnapshotStatus.incomplete:
        return _unavailable(
          'foto_incompleta',
          IndicatorMissingDetail(pendingAccounts: wealth.pending),
        );
      case WealthSnapshotStatus.complete:
        break;
    }
    if (!income.isComplete) {
      return _unavailable(
        'ingresos_incompletos',
        IndicatorMissingDetail(pendingMonths: income.pendingMonths),
      );
    }
    if (income.totalCents == BigInt.zero) {
      return _unavailable('ingresos_nulos', IndicatorMissingDetail());
    }
    if (income.totalCents.isNegative) {
      return _unavailable('ingresos_negativos', IndicatorMissingDetail());
    }

    // Multiplicar como BigInt antes de dividir evita desbordar int64 y
    // redondear el promedio mensual. No usa neto patrimonial ni reales.
    return CalculatedIndicator(
      value: IndicatorValue(
        BigInt.from(wealth.liquidAssetsCents!) * BigInt.from(12),
        income.totalCents,
      ),
      precision: 2,
      unit: _definition.unit,
    );
  }

  UnavailableIndicator _unavailable(
    String code,
    IndicatorMissingDetail detail,
  ) => UnavailableIndicator(
    reason: _definition.reasons.firstWhere((reason) => reason.code == code),
    detail: detail,
  );
}
