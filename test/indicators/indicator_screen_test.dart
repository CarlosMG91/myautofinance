import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/navigation/indicator_origin.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/features/indicators/indicators.dart';
import 'package:myautofinance/features/indicators/presentation/indicator_screen.dart';
import 'package:myautofinance/features/indicators/presentation/indicator_source.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

final class _Provider implements IndicatorInputProvider {
  _Provider(this.readInputs);
  final Future<IndicatorInputs> Function(Month) readInputs;
  @override
  Future<IndicatorInputs> read(
    Month month,
    Set<IndicatorInput> requiredInputs,
  ) => readInputs(month);
}

IndicatorInputs _inputs(
  Month month, {
  WealthSnapshotStatus status = WealthSnapshotStatus.complete,
  int liquid = 900000,
  int income = 3600000,
  Set<int>? present,
}) {
  final account = AccountRecord(
    id: 'synthetic-account',
    name: 'Cuenta sintética',
    kind: AccountKind.account,
    activeFrom: Month(2026, 1),
    activeThrough: null,
    liquidity: Liquidity.liquid,
  );
  return IndicatorInputs(
    month: month,
    wealth: WealthReading.fromSnapshot(
      WealthSnapshot(
        month: month,
        snapshotId: 'synthetic-photo',
        status: status,
        values: status == WealthSnapshotStatus.complete
            ? [
                WealthValue(
                  id: 'synthetic-value',
                  account: account,
                  amountCents: liquid,
                ),
              ]
            : [],
        pending: status == WealthSnapshotStatus.complete ? [] : [account],
      ),
    ),
    annualIncome: AnnualIncomeBudget(
      year: int.parse(month.value.substring(0, 4)),
      totalCents: BigInt.from(income),
      presentMonths: present ?? {for (var m = 1; m <= 12; m++) m},
    ),
  );
}

final class _SyntheticCalculation implements IndicatorCalculation {
  @override
  IndicatorResult calculate(IndicatorInputs inputs) => CalculatedIndicator(
    value: IndicatorValue(BigInt.from(7), BigInt.from(2)),
    precision: 2,
    unit: 'unidades',
  );
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    Future<IndicatorInputs> Function(Month) read, {
    NavigationSession? session,
    double width = 1440,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final navigation =
        session ??
        NavigationSession(
          initialContext: NavigationContext(
            destination: SessionDestination.indicators,
            period: NavigationPeriod(2026, 1),
          ),
        );
    if (session == null) addTearDown(navigation.dispose);
    final source = IndicatorSource(
      engine: IndicatorEngine(
        catalog: IndicatorCatalog.v1(),
        inputs: _Provider(read),
        calculations: {
          'colchon_emergencia': const EmergencyCushionCalculation(),
        },
      ),
      changes: const Stream<int>.empty(),
    );
    await tester.pumpWidget(
      AutofinanceApp(
        navigationSession: navigation,
        indicators: () async => source,
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 412.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('catálogo real, entradas y detalle a $width / $scale', (
        tester,
      ) async {
        await mount(
          tester,
          (month) async => _inputs(month),
          width: width,
          scale: scale,
        );
        expect(find.text('Colchón de emergencia'), findsOneWidget);
        expect(find.text('3,00 meses'), findsOneWidget);
        expect(find.text('9.000,00 €'), findsOneWidget);
        expect(find.text('+36.000,00 €'), findsOneWidget);
        expect(find.text('+3.000,00 €'), findsOneWidget);
        expect(find.byType(AfCard), findsWidgets);
        await tester.ensureVisible(
          find.byKey(const ValueKey('indicator-detail')),
        );
        await tester.tap(find.byKey(const ValueKey('indicator-detail')));
        await tester.pumpAndSettle();
        expect(find.text('Precedencia de motivos'), findsOneWidget);
        expect(find.text('foto_ausente'), findsOneWidget);
        await tester.ensureVisible(find.text('Volver al resumen'));
        await tester.tap(find.text('Volver al resumen'));
        await tester.pumpAndSettle();
        expect(find.text('3,00 meses'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final scenario in [
    ('foto_ausente', WealthSnapshotStatus.absent, 3600000, false),
    ('foto_incompleta', WealthSnapshotStatus.incomplete, 3600000, false),
    ('ingresos_incompletos', WealthSnapshotStatus.complete, 3600000, true),
    ('ingresos_nulos', WealthSnapshotStatus.complete, 0, false),
    ('ingresos_negativos', WealthSnapshotStatus.complete, -120000, false),
  ]) {
    testWidgets('motivo tipado ${scenario.$1} a 320px / 200%', (tester) async {
      await mount(
        tester,
        (month) async => _inputs(
          month,
          status: scenario.$2,
          income: scenario.$3,
          present: scenario.$4 ? {1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12} : null,
        ),
        width: 320,
        scale: 2,
      );
      expect(find.text('Código: ${scenario.$1}'), findsOneWidget);
      expect(find.text('3,00 meses'), findsNothing);
      if (scenario.$1.startsWith('foto')) {
        expect(find.text('• Cuenta sintética'), findsOneWidget);
      }
      if (scenario.$4) {
        expect(find.text('Completar marzo 2026'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cero calculable y promedio sin redondeo intermedio', (
    tester,
  ) async {
    await mount(tester, (month) async => _inputs(month, liquid: 0));
    expect(find.text('0,00 meses'), findsOneWidget);
    expect(find.textContaining('Cero calculable:'), findsOneWidget);
    expect(find.text('Sin dato'), findsNothing);
  });

  testWidgets('precisión al presentar denominador de menos de un céntimo', (
    tester,
  ) async {
    await mount(tester, (month) async => _inputs(month, liquid: 1, income: 7));
    expect(find.text('1,71 meses'), findsOneWidget);
    expect(find.text('+0,01 €'), findsOneWidget);
  });

  testWidgets('cambio mes/año descarta valor y errores tardíos', (
    tester,
  ) async {
    final session = NavigationSession(
      initialContext: NavigationContext(
        destination: SessionDestination.indicators,
        period: NavigationPeriod(2026, 1),
      ),
    );
    addTearDown(session.dispose);
    final pending = <String, Completer<IndicatorInputs>>{};
    await mount(
      tester,
      (month) => (pending[month.value] = Completer<IndicatorInputs>()).future,
      session: session,
    );
    expect(find.text('Cargando'), findsOneWidget);
    pending['2026-01-01']!.complete(_inputs(Month(2026, 1)));
    await tester.pumpAndSettle();
    expect(find.text('3,00 meses'), findsOneWidget);
    await session.selectPeriod(NavigationPeriod(2026, 2));
    await tester.pumpAndSettle();
    expect(find.text('3,00 meses'), findsNothing);
    await session.selectPeriod(NavigationPeriod(2027, 2));
    await tester.pumpAndSettle();
    await session.selectPeriod(NavigationPeriod(2027, 3));
    await tester.pumpAndSettle();
    pending['2027-03-01']!.complete(_inputs(Month(2027, 3), liquid: 630000));
    await tester.pumpAndSettle();
    expect(find.text('2,10 meses'), findsOneWidget);
    pending['2027-02-01']!.complete(_inputs(Month(2027, 2)));
    await tester.pumpAndSettle();
    expect(find.text('2,10 meses'), findsOneWidget);
    expect(find.text('3,00 meses'), findsNothing);
    pending['2026-02-01']!.completeError(StateError('fallo tardío sintético'));
    await tester.pumpAndSettle();
    expect(find.text('2,10 meses'), findsOneWidget);
    expect(find.textContaining('fallo tardío'), findsNothing);
    expect(find.textContaining('presupuesto de 2027'), findsOneWidget);
  });

  testWidgets('fallo técnico conserva causa y reintenta sin falso sin dato', (
    tester,
  ) async {
    var fail = true;
    await mount(tester, (month) async {
      if (fail) {
        throw IndicatorReadFailure(
          code: IndicatorReadFailureCode.read,
          message: 'No se pudo leer SQLite.',
          cause: StateError('disco sintético'),
        );
      }
      return _inputs(month);
    });
    expect(
      find.textContaining('Causa: Bad state: disco sintético'),
      findsOneWidget,
    );
    expect(find.text('Sin dato'), findsNothing);
    fail = false;
    await tester.ensureVisible(find.text('Reintentar'));
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('3,00 meses'), findsOneWidget);
  });

  testWidgets('Tab/Enter abre detalle y Alt+Izquierda restaura foco', (
    tester,
  ) async {
    await mount(tester, (month) async => _inputs(month));
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('indicator-detail')),
    );
    button.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Precedencia de motivos'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.text('Colchón de emergencia'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('indicator-detail')),
          )
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ruta inválida no lee y detalle directo vuelve sin pila', (
    tester,
  ) async {
    var reads = 0;
    final session = NavigationSession(
      initialContext: NavigationContext(
        destination: SessionDestination.indicators,
        period: NavigationPeriod(2026, 1),
      ),
    );
    addTearDown(session.dispose);
    await mount(tester, (month) async {
      reads++;
      return _inputs(month);
    }, session: session);
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.pushNamed('/indicadores?a=2026&m=13');
    await tester.pumpAndSettle();
    expect(reads, 1);
    navigator.pushNamedAndRemoveUntil(
      '/indicadores/detalle?a=2026&m=02&rama=00000000-0000-4000-8000-000000000001&concepto=Salario',
      (_) => false,
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Colchón de emergencia'), findsOneWidget);
    expect(session.context.period, NavigationPeriod(2026, 2));
    expect(session.context.branchId, '00000000-0000-4000-8000-000000000001');
    expect(session.context.filters, {'concepto': 'Salario'});
    await tester.ensureVisible(find.byKey(const ValueKey('indicator-detail')));
    await tester.tap(find.byKey(const ValueKey('indicator-detail')));
    await tester.pumpAndSettle();
    expect(session.context.branchId, '00000000-0000-4000-8000-000000000001');
    expect(session.context.filters, {'concepto': 'Salario', 'detalle': '1'});
  });

  testWidgets('otra definición solo test se renderiza sin cambiar la vista', (
    tester,
  ) async {
    final synthetic = IndicatorDefinition(
      id: 'test_only',
      name: 'Indicador sintético solo test',
      version: 2,
      requiredInputs: {},
      period: IndicatorPeriod.month,
      unit: 'unidades',
      reasons: [],
    );
    final source = IndicatorSource(
      engine: IndicatorEngine(
        catalog: IndicatorCatalog([
          ...IndicatorCatalog.v1().definitions,
          synthetic,
        ]),
        inputs: _Provider((month) async => _inputs(month)),
        calculations: {
          'colchon_emergencia': const EmergencyCushionCalculation(),
          synthetic.id: _SyntheticCalculation(),
        },
      ),
      changes: const Stream<int>.empty(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AfTheme.light(),
        home: IndicatorScreen(
          load: () async => source,
          month: Month(2026, 1),
          onPosition: (_, _) {},
          shell: (body, scroll, detailAction) => Scaffold(
            body: SingleChildScrollView(controller: scroll, child: body),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(synthetic.name), findsOneWidget);
    expect(find.text('3,50 unidades'), findsOneWidget);
    expect(find.text('3,00 meses'), findsOneWidget);
    expect(IndicatorCatalog.v1().definitions.map((d) => d.id), [
      'colchon_emergencia',
    ]);
  });

  test(
    'origen conserva periodo, detalle, posición y foco y rechaza externos',
    () {
      final origin = IndicatorOrigin(
        NavigationContext(
          destination: SessionDestination.indicators,
          period: NavigationPeriod(2026, 2),
          filters: const {'detalle': '1'},
          scrollOffset: 123.5,
          focus: 'detail-photo',
        ),
      );
      final parsed = IndicatorOrigin.parse(origin.route);
      expect(parsed.context.period, origin.context.period);
      expect(parsed.context.scrollOffset, 123.5);
      expect(parsed.context.focus, 'detail-photo');
      expect(parsed.detail, isTrue);
      for (final route in [
        'https://invalid.test/indicadores?a=2026&m=02',
        '/indicadores?a=2026&m=02&posicion=NaN',
        '/indicadores?a=2026&m=02&extra=1',
      ]) {
        expect(() => IndicatorOrigin.parse(route), throwsFormatException);
      }
    },
  );
}
