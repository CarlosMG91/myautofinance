import '../domain/indicator_result.dart';

/// Presentación es-ES de una razón exacta. Half-up decimal: los empates se
/// alejan de cero. Solo redondea aquí, sin convertir el valor a double.
String formatCalculatedIndicator(
  CalculatedIndicator result, {
  bool includeUnit = true,
}) {
  final value = result.value;
  final scale = BigInt.from(10).pow(result.precision);
  final scaled = value.numerator.abs() * scale;
  var rounded = scaled ~/ value.denominator;
  if ((scaled % value.denominator) * BigInt.two >= value.denominator) {
    rounded += BigInt.one;
  }
  final integer = (rounded ~/ scale).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final fraction = result.precision == 0
      ? ''
      : ',${(rounded % scale).toString().padLeft(result.precision, '0')}';
  final sign = value.numerator.isNegative && rounded != BigInt.zero ? '−' : '';
  return '$sign$integer$fraction${includeUnit ? ' ${result.unit}' : ''}';
}
