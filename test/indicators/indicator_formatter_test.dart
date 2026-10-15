import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/indicators/indicators.dart';

void main() {
  // Casos a ambos lados del empate y empates que half-even redondearía abajo.
  for (final fixture in [
    ('100499999999999999999', '100000000000000000000', '1,00 meses'),
    ('1005', '1000', '1,01 meses'),
    ('100500000000000000001', '100000000000000000000', '1,01 meses'),
    ('2675', '1000', '2,68 meses'),
    ('2685', '1000', '2,69 meses'),
    ('9994999', '10000', '999,50 meses'),
    ('999995', '1000', '1.000,00 meses'),
    ('4999', '1000000', '0,00 meses'),
    ('5', '1000', '0,01 meses'),
    ('-1005', '1000', '−1,01 meses'),
    ('-1', '1000', '0,00 meses'),
    ('1', '3', '0,33 meses'),
    ('2', '3', '0,67 meses'),
    ('0', '7', '0,00 meses'),
    ('110680464442257309684', '1', '110.680.464.442.257.309.684,00 meses'),
  ]) {
    test('half-up es-ES ${fixture.$1}/${fixture.$2}', () {
      final result = CalculatedIndicator(
        value: IndicatorValue(
          BigInt.parse(fixture.$1),
          BigInt.parse(fixture.$2),
        ),
        precision: 2,
        unit: 'meses',
      );
      expect(formatCalculatedIndicator(result), fixture.$3);
      // Formatear nunca sustituye la razón por el decimal redondeado.
      expect(
        result.value.numerator * BigInt.parse(fixture.$2),
        BigInt.parse(fixture.$1) * result.value.denominator,
      );
    });
  }

  test('respeta precisión y unidad de un resultado tipado', () {
    for (final fixture in [(0, '1 unidades'), (3, '1,005 unidades')]) {
      expect(
        formatCalculatedIndicator(
          CalculatedIndicator(
            value: IndicatorValue(BigInt.from(1005), BigInt.from(1000)),
            precision: fixture.$1,
            unit: 'unidades',
          ),
        ),
        fixture.$2,
      );
    }
  });
}
