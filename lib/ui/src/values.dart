/// Cantidad ya calculada en céntimos EUR. null conserva ausencia y su motivo.
class AfAmount {
  const AfAmount(this.cents) : reason = null;
  const AfAmount.missing(this.reason) : cents = null;
  final int? cents;
  final String? reason;

  String format({bool signed = true}) {
    final value = cents;
    if (value == null) return 'Sin dato${reason == null ? '' : ': $reason'}';
    final magnitude = BigInt.from(value).abs();
    final digits = (magnitude ~/ BigInt.from(100)).toString();
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    final sign = value < 0
        ? '−'
        : signed && value > 0
        ? '+'
        : '';
    return '$sign$grouped,${(magnitude % BigInt.from(100)).toString().padLeft(2, '0')} €';
  }
}

enum AfChartUnit { eur, months }

/// Unidades tipadas, sin dobles ambiguos para dinero ni valores NaN/infinito.
class AfChartValue {
  const AfChartValue.euros(int cents)
    : amount = cents,
      months = null,
      reason = null,
      unit = AfChartUnit.eur;
  const AfChartValue.unbudgeted()
    : amount = null,
      months = null,
      reason = 'Sin presupuesto',
      unit = AfChartUnit.eur;
  AfChartValue.months(double value)
    : amount = null,
      months = value,
      reason = null,
      unit = AfChartUnit.months {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'Debe ser finito');
    }
  }
  const AfChartValue.missing(this.unit, this.reason)
    : amount = null,
      months = null;
  final AfChartUnit unit;
  final int? amount;
  final double? months;
  final String? reason;
  double? get plotValue => amount?.toDouble() ?? months;
  String get formatted => reason == 'Sin presupuesto'
      ? 'Sin presupuesto'
      : plotValue == null
      ? 'Sin dato${reason == null ? '' : ': $reason'}'
      : unit == AfChartUnit.eur
      ? AfAmount(amount!).format()
      : '${months == 0 ? '0,00' : months!.toStringAsFixed(2).replaceAll('.', ',').replaceAll('-', '−')} meses';
}

/// Estado entregado por el propietario; el kit no deduce bondad desde el signo.
enum AfComparisonState { favorable, unfavorable, equal, unbudgeted }

class AfPeriodOption {
  const AfPeriodOption({required this.id, required this.label});
  final String id;
  final String label;
}
