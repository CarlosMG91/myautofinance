import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/indicators/indicators.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  final month = Month(2026, 1);
  final catalog = IndicatorCatalog.v1();
  final definition = catalog.definitions.single;

  test('v1 publica solo el colchón y el contrato EP-001 en orden', () {
    expect(definition.id, 'colchon_emergencia');
    expect(definition.name, 'Colchón de emergencia');
    expect(definition.version, 1);
    expect(definition.period, IndicatorPeriod.month);
    expect(definition.unit, 'meses');
    expect(definition.requiredInputs, IndicatorInput.values.toSet());
    expect(definition.reasons.map((reason) => reason.code), [
      'foto_ausente',
      'foto_incompleta',
      'ingresos_incompletos',
      'ingresos_nulos',
      'ingresos_negativos',
    ]);
    expect(definition.reasons.map((reason) => reason.text), [
      'sin dato: falta foto patrimonial',
      'sin dato: foto patrimonial incompleta',
      'sin dato: presupuesto anual de ingresos incompleto',
      'sin dato: ingresos presupuestados nulos',
      'sin dato: ingresos presupuestados no positivos',
    ]);
  });

  test('ID duplicado se rechaza incluso con versión distinta', () {
    expect(
      () => IndicatorCatalog([definition, _definition(version: 2)]),
      throwsArgumentError,
    );
    expect(() => catalog.definition('inexistente'), throwsArgumentError);
  });

  test(
    'definición y catálogo copian sus colecciones y no permiten mutarlas',
    () {
      final inputs = {IndicatorInput.monthlyWealth};
      final reasons = [IndicatorReason(code: 'ausente', text: 'Sin foto')];
      final custom = _definition(requiredInputs: inputs, reasons: reasons);
      final definitions = [custom];
      final registry = IndicatorCatalog(definitions);
      inputs.clear();
      reasons.clear();
      definitions.clear();
      expect(custom.requiredInputs, {IndicatorInput.monthlyWealth});
      expect(custom.reasons.single.code, 'ausente');
      expect(registry.definitions.single, same(custom));
      expect(() => custom.requiredInputs.clear(), throwsUnsupportedError);
      expect(() => custom.reasons.clear(), throwsUnsupportedError);
      expect(() => registry.definitions.clear(), throwsUnsupportedError);
    },
  );

  test('rechaza metadatos vacíos, versiones y motivos ambiguos', () {
    expect(() => _definition(id: ''), throwsArgumentError);
    expect(() => _definition(version: 0), throwsArgumentError);
    expect(
      () => IndicatorReason(code: '', text: 'Ausente'),
      throwsArgumentError,
    );
    expect(
      () =>
          _definition(reasons: [definition.reasons[0], definition.reasons[0]]),
      throwsArgumentError,
    );
  });

  test('ingresos firmados y presencia son independientes, incluido cero', () {
    for (final total in [
      BigInt.zero,
      BigInt.from(-120000),
      BigInt.from(2880000),
    ]) {
      final income = _income(total: total);
      expect(income.totalCents, total);
      expect(income.isComplete, isTrue);
      expect(income.pendingMonths, isEmpty);
    }
    final present = {12, 2};
    final income = AnnualIncomeBudget(
      year: 2026,
      totalCents: BigInt.zero,
      presentMonths: present,
    );
    present.add(1);
    expect(income.isComplete, isFalse);
    expect(income.pendingMonths, [1, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
    expect(() => income.presentMonths.clear(), throwsUnsupportedError);
    expect(
      () => AnnualIncomeBudget(
        year: 2026,
        totalCents: BigInt.zero,
        presentMonths: {13},
      ),
      throwsArgumentError,
    );
  });

  test(
    'razón conserva precisión más allá de int64 y permite numerador cero',
    () {
      final numerator = BigInt.parse('9223372036854775807') * BigInt.from(12);
      final denominator = BigInt.from(3600001);
      final value = IndicatorValue(numerator, denominator);
      expect(value.numerator * denominator, numerator * value.denominator);
      expect(value.denominator, greaterThan(BigInt.one));
      final zero = IndicatorValue(BigInt.zero, denominator);
      expect(zero.numerator, BigInt.zero);
      expect(zero.denominator, BigInt.one);
      final signed = IndicatorValue(BigInt.from(12), BigInt.from(-8));
      expect(signed.numerator, BigInt.from(-3));
      expect(signed.denominator, BigInt.two);
      expect(
        () => IndicatorValue(BigInt.one, BigInt.zero),
        throwsArgumentError,
      );
    },
  );

  test(
    'motor inyecta entradas y cálculo y entrega valor/precisión/unidad',
    () async {
      final inputs = _inputs(month);
      final provider = _Provider((requestedMonth, requestedInputs) async {
        expect(requestedMonth.value, month.value);
        expect(requestedInputs, definition.requiredInputs);
        expect(() => requestedInputs.clear(), throwsUnsupportedError);
        return inputs;
      });
      final expected = _value();
      final calculations = <String, IndicatorCalculation>{
        definition.id: _Calculation((actual) {
          expect(actual, same(inputs));
          return expected;
        }),
      };
      final engine = IndicatorEngine(
        catalog: catalog,
        inputs: provider,
        calculations: calculations,
      );
      calculations.clear();
      final evaluation = await engine.evaluate(definition.id, month);
      expect(evaluation.definition, same(definition));
      expect(evaluation.month.value, month.value);
      final result = evaluation.result as CalculatedIndicator;
      expect(result, same(expected));
      expect(result.precision, 2);
      expect(result.unit, 'meses');
      expect(result.value.numerator, BigInt.from(3));
      expect(result.value.denominator, BigInt.one);
    },
  );

  test(
    'sin dato conserva código/texto y fichas o meses estructurados',
    () async {
      final pending = [_account(month, 'pendiente')];
      final months = [3, 8];
      final detail = IndicatorMissingDetail(
        pendingAccounts: pending,
        pendingMonths: months,
      );
      pending.clear();
      months.clear();
      final expected = UnavailableIndicator(
        reason: definition.reasons[1],
        detail: detail,
      );
      final evaluation = await _engine(
        catalog,
        _inputs(month),
        (_) => expected,
      ).evaluate(definition.id, month);
      final result = evaluation.result as UnavailableIndicator;
      expect(result.code, 'foto_incompleta');
      expect(result.text, 'sin dato: foto patrimonial incompleta');
      expect(result.detail.pendingAccounts.single.id, 'pendiente');
      expect(result.detail.pendingMonths, [3, 8]);
      expect(() => detail.pendingAccounts.clear(), throwsUnsupportedError);
      expect(() => detail.pendingMonths.clear(), throwsUnsupportedError);
    },
  );

  test('lectura fallida nunca se transforma en foto_ausente', () async {
    const failure = IndicatorReadFailure(
      code: IndicatorReadFailureCode.read,
      message: 'No se pudo abrir la base.',
    );
    for (final error in [failure, StateError('SQLite no disponible')]) {
      var calculated = false;
      final engine = IndicatorEngine(
        catalog: catalog,
        inputs: _Provider((_, _) async => throw error),
        calculations: {
          definition.id: _Calculation((_) {
            calculated = true;
            return UnavailableIndicator(
              reason: definition.reasons[0],
              detail: IndicatorMissingDetail(),
            );
          }),
        },
      );
      await expectLater(
        engine.evaluate(definition.id, month),
        throwsA(
          error == failure
              ? same(failure)
              : isA<IndicatorReadFailure>()
                    .having(
                      (failure) => failure.code,
                      'código',
                      IndicatorReadFailureCode.read,
                    )
                    .having((failure) => failure.cause, 'causa', same(error)),
        ),
      );
      expect(calculated, isFalse);
    }
  });

  test('entrada no leída y periodos distintos son fallos técnicos', () async {
    for (final inputs in [
      IndicatorInputs(month: month),
      IndicatorInputs(month: month, wealth: _wealth(month)),
      _inputs(Month(2026, 2)),
      IndicatorInputs(
        month: month,
        wealth: _wealth(Month(2026, 2)),
        annualIncome: _income(),
      ),
      IndicatorInputs(
        month: month,
        wealth: _wealth(month),
        annualIncome: _income(year: 2025),
      ),
    ]) {
      final engine = _engine(
        catalog,
        inputs,
        (_) => throw StateError('No debe calcular'),
      );
      await expectLater(
        engine.evaluate(definition.id, month),
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

  test('foto ausente e incompleta son entradas financieras válidas', () async {
    for (final status in [
      WealthSnapshotStatus.absent,
      WealthSnapshotStatus.incomplete,
    ]) {
      final reading = WealthReading.fromSnapshot(
        WealthSnapshot(
          month: month,
          snapshotId: null,
          status: status,
          values: [],
          pending: [_account(month, 'sin_valor')],
        ),
      );
      final inputs = IndicatorInputs(
        month: month,
        wealth: reading,
        annualIncome: _income(),
      );
      final engine = _engine(catalog, inputs, (actual) {
        expect(actual.wealth!.status, status);
        expect(actual.wealth!.liquidAssetsCents, isNull);
        expect(actual.wealth!.pending.single.id, 'sin_valor');
        return UnavailableIndicator(
          reason:
              definition.reasons[status == WealthSnapshotStatus.absent ? 0 : 1],
          detail: IndicatorMissingDetail(
            pendingAccounts: actual.wealth!.pending,
          ),
        );
      });
      expect(
        (await engine.evaluate(definition.id, month)).result,
        isA<UnavailableIndicator>(),
      );
    }
  });

  test('catálogo sin cálculo o con cálculos ajenos se rechaza al componer', () {
    for (final calculations in <Map<String, IndicatorCalculation>>[
      {},
      {'otro': _Calculation((_) => _value())},
      {
        definition.id: _Calculation((_) => _value()),
        'otro': _Calculation((_) => _value()),
      },
    ]) {
      expect(
        () => IndicatorEngine(
          catalog: catalog,
          inputs: _Provider((_, _) async => _inputs(month)),
          calculations: calculations,
        ),
        throwsArgumentError,
      );
    }
  });

  test(
    'no oculta errores de cálculo ni acepta unidad o motivo ajenos',
    () async {
      final failure = StateError('Error de cálculo');
      final engine = _engine(catalog, _inputs(month), (_) => throw failure);
      await expectLater(
        engine.evaluate(definition.id, month),
        throwsA(same(failure)),
      );
      for (final result in <IndicatorResult>[
        _value(unit: 'EUR'),
        UnavailableIndicator(
          reason: IndicatorReason(
            code: 'foto_ausente',
            text: 'Texto no registrado',
          ),
          detail: IndicatorMissingDetail(),
        ),
        UnavailableIndicator(
          reason: IndicatorReason(code: 'otro', text: 'Otro motivo'),
          detail: IndicatorMissingDetail(),
        ),
      ]) {
        await expectLater(
          _engine(
            catalog,
            _inputs(month),
            (_) => result,
          ).evaluate(definition.id, month),
          throwsStateError,
        );
      }
    },
  );

  test('indicador sintético se añade solo en test sin cambiar entidades base', () async {
    // Otra unidad y otros motivos, sobre la misma foto EP-009/017. No necesita
    // ingresos ni schema, movimientos, partidas o valores nuevos persistidos.
    final synthetic = IndicatorDefinition(
      id: 'liquidos_solo_test',
      name: 'Líquidos de prueba',
      version: 1,
      requiredInputs: {IndicatorInput.monthlyWealth},
      period: IndicatorPeriod.month,
      unit: 'EUR',
      reasons: [],
    );
    final extended = IndicatorCatalog([...catalog.definitions, synthetic]);
    final engine = IndicatorEngine(
      catalog: extended,
      inputs: _Provider((requestedMonth, requiredInputs) async {
        expect(requiredInputs, {IndicatorInput.monthlyWealth});
        return IndicatorInputs(
          month: requestedMonth,
          wealth: _wealth(requestedMonth),
        );
      }),
      calculations: {
        definition.id: _Calculation((_) => _value()),
        synthetic.id: _LiquidEurosOnlyInTest(),
      },
    );
    final result =
        (await engine.evaluate(synthetic.id, month)).result
            as CalculatedIndicator;
    // Foto con activo líquido de 9.000 EUR y deuda de 1.000: no se resta deuda.
    expect(result.value.numerator, BigInt.from(9000));
    expect(result.value.denominator, BigInt.one);
    expect(result.unit, 'EUR');
    expect(IndicatorCatalog.v1().definitions.map((d) => d.id), [
      'colchon_emergencia',
    ]);
  });
}

IndicatorDefinition _definition({
  String id = 'colchon_emergencia',
  int version = 1,
  Set<IndicatorInput> requiredInputs = const {},
  List<IndicatorReason> reasons = const [],
}) => IndicatorDefinition(
  id: id,
  name: 'Prueba',
  version: version,
  requiredInputs: requiredInputs,
  period: IndicatorPeriod.month,
  unit: 'meses',
  reasons: reasons,
);

AnnualIncomeBudget _income({int year = 2026, BigInt? total}) =>
    AnnualIncomeBudget(
      year: year,
      totalCents: total ?? BigInt.from(3600000),
      presentMonths: {for (var month = 1; month <= 12; month++) month},
    );

AccountRecord _account(
  Month month,
  String id, {
  AccountKind kind = AccountKind.account,
}) => AccountRecord(
  id: id,
  name: id,
  kind: kind,
  activeFrom: month,
  activeThrough: null,
  liquidity: kind == AccountKind.debt ? null : Liquidity.liquid,
);

WealthReading _wealth(Month month) => WealthReading.fromSnapshot(
  WealthSnapshot(
    month: month,
    snapshotId: 'foto',
    status: WealthSnapshotStatus.complete,
    values: [
      WealthValue(
        id: 'valor_activo',
        account: _account(month, 'activo'),
        amountCents: 900000,
      ),
      WealthValue(
        id: 'valor_deuda',
        account: _account(month, 'deuda', kind: AccountKind.debt),
        amountCents: 100000,
      ),
    ],
    pending: [],
  ),
);

IndicatorInputs _inputs(Month month) => IndicatorInputs(
  month: month,
  wealth: _wealth(month),
  annualIncome: _income(),
);

CalculatedIndicator _value({String unit = 'meses'}) => CalculatedIndicator(
  value: IndicatorValue(BigInt.from(3), BigInt.one),
  precision: 2,
  unit: unit,
);

IndicatorEngine _engine(
  IndicatorCatalog catalog,
  IndicatorInputs inputs,
  IndicatorResult Function(IndicatorInputs) calculate,
) => IndicatorEngine(
  catalog: catalog,
  inputs: _Provider((_, _) async => inputs),
  calculations: {catalog.definitions.single.id: _Calculation(calculate)},
);

final class _Provider implements IndicatorInputProvider {
  _Provider(this._read);
  final Future<IndicatorInputs> Function(Month, Set<IndicatorInput>) _read;
  @override
  Future<IndicatorInputs> read(
    Month month,
    Set<IndicatorInput> requiredInputs,
  ) => _read(month, requiredInputs);
}

final class _Calculation implements IndicatorCalculation {
  _Calculation(this._calculate);
  final IndicatorResult Function(IndicatorInputs) _calculate;
  @override
  IndicatorResult calculate(IndicatorInputs inputs) => _calculate(inputs);
}

final class _LiquidEurosOnlyInTest implements IndicatorCalculation {
  @override
  IndicatorResult calculate(IndicatorInputs inputs) => CalculatedIndicator(
    value: IndicatorValue(
      BigInt.from(inputs.wealth!.liquidAssetsCents!),
      BigInt.from(100),
    ),
    precision: 2,
    unit: 'EUR',
  );
}
