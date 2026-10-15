import '../../wealth/wealth.dart' show AccountRecord;
import 'indicator_definition.dart';

/// Razón exacta reducida, sin double ni redondeo intermedio.
/// El cálculo del colchón podrá construir líquidosCents * 12 / ingresosCents.
final class IndicatorValue {
  factory IndicatorValue(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) {
      throw ArgumentError('El denominador no puede ser cero.');
    }
    if (denominator.isNegative) {
      numerator = -numerator;
      denominator = -denominator;
    }
    final divisor = numerator.gcd(denominator);
    return IndicatorValue._(numerator ~/ divisor, denominator ~/ divisor);
  }

  const IndicatorValue._(this.numerator, this.denominator);
  final BigInt numerator, denominator;
}

sealed class IndicatorResult {
  const IndicatorResult();
}

final class CalculatedIndicator extends IndicatorResult {
  CalculatedIndicator({
    required this.value,
    required this.precision,
    required this.unit,
  }) {
    if (precision < 0 || unit.trim().isEmpty) {
      throw ArgumentError('Precisión o unidad de resultado inválida.');
    }
  }

  final IndicatorValue value;

  /// Decimales para presentación; no modifica el valor exacto. Colchón v1: 2.
  final int precision;
  final String unit;
}

/// Referencias de fichas (ID/nombre) y meses 1–12, sin parsear texto visible.
final class IndicatorMissingDetail {
  IndicatorMissingDetail({
    List<AccountRecord> pendingAccounts = const [],
    List<int> pendingMonths = const [],
  }) : pendingAccounts = List.unmodifiable(pendingAccounts),
       pendingMonths = List.unmodifiable(pendingMonths) {
    if (pendingMonths.any((month) => month < 1 || month > 12) ||
        pendingMonths.toSet().length != pendingMonths.length) {
      throw ArgumentError('Meses pendientes inválidos.');
    }
  }

  final List<AccountRecord> pendingAccounts;
  final List<int> pendingMonths;
}

final class UnavailableIndicator extends IndicatorResult {
  const UnavailableIndicator({required this.reason, required this.detail});

  final IndicatorReason reason;
  String get code => reason.code;
  String get text => reason.text;
  final IndicatorMissingDetail detail;
}
