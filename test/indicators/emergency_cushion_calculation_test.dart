import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/indicators/indicators.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  const calculation = EmergencyCushionCalculation();
  final texts = {
    'foto_ausente': 'sin dato: falta foto patrimonial',
    'foto_incompleta': 'sin dato: foto patrimonial incompleta',
    'ingresos_incompletos':
        'sin dato: presupuesto anual de ingresos incompleto',
    'ingresos_nulos': 'sin dato: ingresos presupuestados nulos',
    'ingresos_negativos': 'sin dato: ingresos presupuestados no positivos',
  };

  for (final status in WealthSnapshotStatus.values) {
    for (final completeIncome in [false, true]) {
      for (final total in [-120000, 0, 3600000]) {
        test(
          'precedencia: $status, completo=$completeIncome, total=$total',
          () {
            final inputs = _inputs(
              status: status,
              income: _income(
                total: BigInt.from(total),
                present: completeIncome ? null : {12, 2, 1},
              ),
            );
            final result = calculation.calculate(inputs);
            final String? code;
            if (status == WealthSnapshotStatus.absent) {
              code = 'foto_ausente';
            } else if (status == WealthSnapshotStatus.incomplete) {
              code = 'foto_incompleta';
            } else if (!completeIncome) {
              code = 'ingresos_incompletos';
            } else if (total == 0) {
              code = 'ingresos_nulos';
            } else if (total < 0) {
              code = 'ingresos_negativos';
            } else {
              code = null;
            }
            if (code == null) {
              expect(result, isA<CalculatedIndicator>());
              return;
            }
            final missing = result as UnavailableIndicator;
            expect(missing.code, code);
            expect(missing.text, texts[code]);
            expect(
              missing.detail.pendingAccounts,
              status == WealthSnapshotStatus.complete
                  ? isEmpty
                  : orderedEquals(inputs.wealth!.pending),
            );
            expect(
              missing.detail.pendingMonths,
              code == 'ingresos_incompletos'
                  ? [3, 4, 5, 6, 7, 8, 9, 10, 11]
                  : isEmpty,
            );
          },
        );
      }
    }
  }

  test('foto parcial con todos los líquidos aún exige la deuda pendiente', () {
    final result = calculation.calculate(
      _inputs(status: WealthSnapshotStatus.incomplete),
    ) as UnavailableIndicator;
    expect(result.detail.pendingAccounts.single.id, 'deuda');
    expect(result.detail.pendingAccounts.single.name, 'Deuda familiar');
  });

  test('doce ceros explícitos completan ingresos y dan ingresos_nulos', () {
    final income = _income(total: BigInt.zero);
    expect(income.isComplete, isTrue);
    expect(income.pendingMonths, isEmpty);
    final result =
        calculation.calculate(_inputs(income: income)) as UnavailableIndicator;
    expect(result.code, 'ingresos_nulos');
  });

  test('sin presupuesto no inventa meses a partir del total cero', () {
    final result = calculation.calculate(
      _inputs(
        income: _income(total: BigInt.zero, present: {}),
      ),
    ) as UnavailableIndicator;
    expect(result.code, 'ingresos_incompletos');
    expect(result.detail.pendingMonths, List.generate(12, (i) => i + 1));
  });

  test('caso G: líquidos 9000 / 3000, sin restar deudas ni sumar cartera', () {
    final inputs = _inputs();
    final result = calculation.calculate(inputs) as CalculatedIndicator;
    expect(inputs.wealth!.totals!.netWorthCents, 1400000);
    expect(result.value.numerator, BigInt.from(3));
    expect(result.value.denominator, BigInt.one);
    expect(result.precision, 2);
    expect(result.unit, 'meses');
    expect(formatCalculatedIndicator(result), '3,00 meses');
  });

  for (final fixture in [
    (620000, 3600000, '2,07 meses'), // Caso D: 31/15 meses.
    (1670000, 3600000, '5,57 meses'), // Variante de liquidez histórica.
    (1, 7, '1,71 meses'), // 12/7, promedio de 7/12 céntimos.
    (1, 288, '0,04 meses'), // 1/24 periódico.
    (1, 97, '0,12 meses'), // Promedio redondeado a 8 daría 0,13.
    (201, 2400, '1,01 meses'), // 1,005: empate decimal half-up.
  ]) {
    test('razón exacta ${fixture.$1} * 12 / ${fixture.$2}', () {
      final result = calculation.calculate(
        _inputs(
          liquidCents: fixture.$1,
          income: _income(total: BigInt.from(fixture.$2)),
        ),
      ) as CalculatedIndicator;
      expect(
        result.value.numerator * BigInt.from(fixture.$2),
        BigInt.from(fixture.$1) * BigInt.from(12) * result.value.denominator,
      );
      expect(result.value.denominator, greaterThan(BigInt.one));
      expect(formatCalculatedIndicator(result), fixture.$3);
    });
  }

  test('numerador cero con denominador positivo es valor 0 meses', () {
    final result =
        calculation.calculate(_inputs(liquidCents: 0)) as CalculatedIndicator;
    expect(result.value.numerator, BigInt.zero);
    expect(result.value.denominator, BigInt.one);
    expect(formatCalculatedIndicator(result), '0,00 meses');
  });

  test('activos no líquidos positivos tampoco integran el numerador', () {
    final result = calculation.calculate(
      _inputs(illiquidCents: 200000),
    ) as CalculatedIndicator;
    expect(formatCalculatedIndicator(result), '3,00 meses');
  });

  test('producto por doce y presupuesto superiores a int64 son exactos', () {
    const liquid = 9223372036854775807;
    for (final total in [BigInt.one, BigInt.parse('110680464442257309685')]) {
      final result = calculation.calculate(
        _inputs(
          liquidCents: liquid,
          income: _income(total: total),
        ),
      ) as CalculatedIndicator;
      expect(
        result.value.numerator * total,
        BigInt.from(liquid) * BigInt.from(12) * result.value.denominator,
      );
    }
  });

  test('entradas omitidas o de otro periodo son errores técnicos', () {
    final valid = _inputs();
    for (final inputs in [
      IndicatorInputs(month: valid.month),
      IndicatorInputs(month: valid.month, wealth: valid.wealth),
      IndicatorInputs(month: valid.month, annualIncome: valid.annualIncome),
      IndicatorInputs(
        month: Month(2026, 2),
        wealth: valid.wealth,
        annualIncome: valid.annualIncome,
      ),
      _inputs(income: _income(year: 2025)),
    ]) {
      expect(
        () => calculation.calculate(inputs),
        throwsA(
          isA<IndicatorReadFailure>().having(
            (failure) => failure.code,
            'código',
            IndicatorReadFailureCode.invalidInputs,
          ),
        ),
      );
    }
  });

  test(
    'cálculo real se conecta al motor sin IO ni mutar las entradas',
    () async {
      final inputs = _inputs();
      final engine = IndicatorEngine(
        catalog: IndicatorCatalog.v1(),
        inputs: _Provider(inputs),
        calculations: {'colchon_emergencia': calculation},
      );
      final evaluation = await engine.evaluate(
        'colchon_emergencia',
        inputs.month,
      );
      expect(evaluation.definition.version, 1);
      expect(
        formatCalculatedIndicator(evaluation.result as CalculatedIndicator),
        '3,00 meses',
      );
      final repeated = calculation.calculate(inputs) as CalculatedIndicator;
      expect(repeated.value.numerator, BigInt.from(3));
      expect(inputs.wealth!.values.length, 4);
      expect(inputs.annualIncome!.totalCents, BigInt.from(3600000));
      expect(inputs.annualIncome!.presentMonths.length, 12);
    },
  );
}

AnnualIncomeBudget _income({
  BigInt? total,
  Set<int>? present,
  int year = 2026,
}) => AnnualIncomeBudget(
  year: year,
  totalCents: total ?? BigInt.from(3600000),
  presentMonths: present ?? {for (var i = 1; i <= 12; i++) i},
);

IndicatorInputs _inputs({
  WealthSnapshotStatus status = WealthSnapshotStatus.complete,
  int liquidCents = 900000,
  int illiquidCents = 0,
  AnnualIncomeBudget? income,
}) {
  final month = Month(2026, 1);
  AccountRecord account(
    String id,
    String name,
    AccountKind kind,
    Liquidity? l,
  ) => AccountRecord(
    id: id,
    name: name,
    kind: kind,
    activeFrom: month,
    activeThrough: null,
    liquidity: l,
  );
  final liquid = account(
    'liquido',
    'Cuenta',
    AccountKind.account,
    Liquidity.liquid,
  );
  final medium = account(
    'media',
    'Cartera',
    AccountKind.portfolio,
    Liquidity.medium,
  );
  final illiquid = account(
    'no_liquido',
    'Activo',
    AccountKind.portfolio,
    Liquidity.illiquid,
  );
  final debt = account('deuda', 'Deuda familiar', AccountKind.debt, null);
  return IndicatorInputs(
    month: month,
    annualIncome: income ?? _income(),
    wealth: WealthReading.fromSnapshot(
      WealthSnapshot(
        month: month,
        snapshotId: status == WealthSnapshotStatus.absent ? null : 'foto',
        status: status,
        values: status == WealthSnapshotStatus.absent
            ? []
            : [
                WealthValue(
                  id: 'v1',
                  account: liquid,
                  amountCents: liquidCents,
                ),
                WealthValue(id: 'v2', account: medium, amountCents: 1000000),
                WealthValue(
                  id: 'v3',
                  account: illiquid,
                  amountCents: illiquidCents,
                ),
                if (status == WealthSnapshotStatus.complete)
                  WealthValue(id: 'v4', account: debt, amountCents: 500000),
              ],
        pending: switch (status) {
          WealthSnapshotStatus.absent => [liquid, medium, illiquid, debt],
          WealthSnapshotStatus.incomplete => [debt],
          WealthSnapshotStatus.complete => [],
        },
      ),
    ),
  );
}

final class _Provider implements IndicatorInputProvider {
  const _Provider(this.inputs);
  final IndicatorInputs inputs;
  @override
  Future<IndicatorInputs> read(
    Month month,
    Set<IndicatorInput> requiredInputs,
  ) async => inputs;
}
