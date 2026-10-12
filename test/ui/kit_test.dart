import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../../examples/ui_kit.dart';

Future<void> loadAfFonts() async {
  final loader = FontLoader(AfTokens.family);
  for (final weight in ['regular', 'medium', 'bold']) {
    loader.addFont(rootBundle.load('assets/fonts/roboto-$weight.ttf'));
  }
  await loader.load();
}

Widget host(Widget child, {double scale = 1, bool reducedMotion = false}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AfTheme.light(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reducedMotion,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(loadAfFonts);
  test('EUR exacto con signo, cero y ausencia diferenciados', () {
    expect(const AfAmount(122975).format(), '+1.229,75 €');
    expect(const AfAmount(-35025).format(), '−350,25 €');
    expect(const AfAmount(0).format(), '0,00 €');
    expect(const AfAmount(500000).format(signed: false), '5.000,00 €');
    expect(const AfAmount(-1).format(signed: false), '−0,01 €');
    expect(
      const AfAmount.missing('Foto incompleta').format(),
      'Sin dato: Foto incompleta',
    );
    expect(() => AfChartValue.months(double.nan), throwsArgumentError);
    expect(() => AfChartValue.months(double.infinity), throwsArgumentError);
    expect(AfChartValue.months(-0.0).formatted, '0,00 meses');
  });

  test('Escala firmada, constante, vacía y extremos finitos', () {
    final signed = AfChartScale([-35025, 40000]);
    expect(signed.position(-35025), 0);
    expect(signed.position(40000), 1);
    expect(signed.position(0), inExclusiveRange(0, 1));
    for (final values in <List<double?>>[
      [],
      [null],
      [0, 0],
      [8, 8],
      [-1e308, 1e308],
      [1e-300],
    ]) {
      final scale = AfChartScale(values);
      for (final value in [0.0, ...values.whereType<double>()]) {
        expect(scale.position(value).isFinite, isTrue);
        expect(scale.position(value), inInclusiveRange(0, 1));
      }
    }
  });

  test('Tokens y contraste preservan la identidad normativa', () {
    final tokens = jsonDecode(
      File('docs/ep-026/identidad/tokens-visuales.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final colors = <String, Color>{
      'canvas': AfTokens.canvas,
      'surface': AfTokens.surface,
      'surfaceSubtle': AfTokens.surfaceSubtle,
      'text': AfTokens.text,
      'muted': AfTokens.muted,
      'border': AfTokens.border,
      'controlBorder': AfTokens.controlBorder,
      'accent': AfTokens.accent,
      'accentHover': AfTokens.accentHover,
      'accentTint': AfTokens.accentTint,
      'onAccent': AfTokens.onAccent,
      'favorable': AfTokens.favorable,
      'favorableTint': AfTokens.favorableTint,
      'unfavorable': AfTokens.unfavorable,
      'unfavorableTint': AfTokens.unfavorableTint,
      'warning': AfTokens.warning,
      'warningTint': AfTokens.warningTint,
      'error': AfTokens.error,
      'errorTint': AfTokens.errorTint,
      'focus': AfTokens.focus,
      'seriesReal': AfTokens.seriesReal,
      'seriesBudget': AfTokens.seriesBudget,
      'seriesAsset': AfTokens.seriesAsset,
      'seriesDebt': AfTokens.seriesDebt,
    };
    expect(colors.keys, unorderedEquals((tokens['color'] as Map).keys));
    for (final entry in colors.entries) {
      expect(
        '#${(entry.value.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
        tokens['color'][entry.key],
      );
    }
    for (final pair in tokens['contrastPairs'] as List) {
      final a = colors[pair[0]]!.computeLuminance();
      final b = colors[pair[1]]!.computeLuminance();
      final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
      expect(ratio, greaterThanOrEqualTo(pair[2]), reason: '$pair');
    }
    expect(AfTokens.family, tokens['type']['family']);
    expect(AfTheme.light().brightness, Brightness.light);
    expect(
      AfTheme.light(highContrast: true).colorScheme.outline,
      AfTokens.text,
    );
    for (final file in [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
      'LICENSE-Roboto.txt',
    ]) {
      expect(
        File('assets/fonts/$file').readAsBytesSync(),
        File('docs/ep-026/identidad/assets/$file').readAsBytesSync(),
      );
    }
  });

  testWidgets(
    'Controles 48dp, teclado, foco, selección y reducción de movimiento',
    (tester) async {
      var count = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          Column(
            children: [
              AfAction(label: 'Abrir detalle', onPressed: () => count++),
              SizedBox(
                width: 108,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Confirmar celda',
                      onPressed: () {},
                      icon: const AfIcon(AfIcons.confirm),
                    ),
                    IconButton(
                      tooltip: 'Cancelar edición',
                      onPressed: () {},
                      icon: const AfIcon(AfIcons.close),
                    ),
                  ],
                ),
              ),
              const AfAction(
                label: 'Guardar',
                onPressed: null,
                unavailableReason: 'Sin base activa',
              ),
              const AfValueRow(
                label: 'Compra',
                selected: true,
                value: AfMoneyText(AfAmount(-35025)),
              ),
            ],
          ),
          reducedMotion: true,
        ),
      );
      expect(
        tester.getSize(find.byType(OutlinedButton).first).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.getSize(find.byType(IconButton).first), const Size(48, 48));
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = tester
          .widget<OutlinedButton>(find.byType(OutlinedButton).first)
          .style;
      expect(focused!.animationDuration, Duration.zero);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(count, 1);
      final buttonContext = tester.element(find.text('Abrir detalle'));
      expect(AfTokens.duration(buttonContext), Duration.zero);
      expect(
        Theme.of(buttonContext).outlinedButtonTheme.style!.side!
            .resolve({WidgetState.focused})!
            .width,
        3,
      );
      expect(find.text('Sin base activa'), findsOneWidget);
      final rowNode = tester.getSemantics(
        find
            .descendant(
              of: find.byType(AfValueRow),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(
        rowNode.getSemanticsData().flagsCollection.isSelected.toBoolOrNull(),
        isTrue,
      );
      semantics.dispose();
    },
  );

  testWidgets('Barras accesibles no ocultan signo, cero ni ausencia', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var opened = false;
    await tester.pumpWidget(
      host(
        AfBarChart(
          title: 'Comparativa',
          period: 'Enero',
          data: [
            AfBarDatum(
              label: 'Real',
              value: const AfChartValue.euros(-35025),
              role: AfSeriesRole.real,
              onPressed: () => opened = true,
            ),
            const AfBarDatum(
              label: 'Presupuesto',
              value: AfChartValue.missing(AfChartUnit.eur, 'Sin presupuesto'),
              role: AfSeriesRole.budget,
            ),
            const AfBarDatum(
              label: 'Cero',
              value: AfChartValue.euros(0),
              role: AfSeriesRole.real,
            ),
          ],
        ),
      ),
    );
    expect(find.text('−350,25 €'), findsOneWidget);
    expect(find.text('0,00 €'), findsOneWidget);
    expect(find.textContaining('Sin presupuesto'), findsOneWidget);
    await tester.tap(find.text('−350,25 €'));
    await tester.pump();
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets(
    'Distribución protege fotos incompletas, inválidas y total cero',
    (tester) async {
      Widget distribution(AfDistributionState state, int total) =>
          AfDistributionChart(
            title: 'Activos',
            period: 'Enero',
            state: state,
            assets: const [AfAssetDatum(id: 'cero', label: 'Cuenta', cents: 0)],
            totalAssets: AfAmount(total),
            debt: const AfAmount(500000),
            reason: 'Falta Cartera',
          );
      await tester.pumpWidget(
        host(distribution(AfDistributionState.missing, 0)),
      );
      expect(find.textContaining('Falta Cartera'), findsOneWidget);
      expect(find.text('Cuenta'), findsNothing);
      await tester.pumpWidget(
        host(distribution(AfDistributionState.complete, 0)),
      );
      expect(
        find.textContaining('Distribución no representable'),
        findsOneWidget,
      );
      expect(find.text('Deudas · magnitud separada'), findsOneWidget);
      await tester.pumpWidget(
        host(distribution(AfDistributionState.complete, 100)),
      );
      expect(find.textContaining('incoherentes'), findsOneWidget);
      expect(find.text('Cuenta'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Formulario conserva borrador y expone validación a 200%', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(
      host(
        Form(
          key: form,
          child: AfFormField(
            label: 'Importe EUR',
            controller: controller,
            required: true,
            help: 'Ayuda persistente',
            validator: (_) => 'Importe rechazado por el propietario',
          ),
        ),
        scale: 2,
      ),
    );
    await tester.enterText(find.byType(TextFormField), '-12,00');
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(controller.text, '-12,00');
    expect(find.text('Importe rechazado por el propietario'), findsOneWidget);
    expect(find.text('Importe EUR · obligatorio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Selector cambia con datos controlados por el consumidor', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      host(
        AfPeriodSelector(
          label: 'Mes',
          selectedId: 'enero',
          options: const [
            AfPeriodOption(id: 'enero', label: 'Enero 2026'),
            AfPeriodOption(id: 'abril', label: 'Abril 2026'),
          ],
          onChanged: (value) => selected = value,
        ),
      ),
    );
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abril 2026').last);
    await tester.pumpAndSettle();
    expect(selected, 'abril');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Shell delega guards, conserva selección rechazada y todos los slots',
    (tester) async {
      String? requested;
      await tester.pumpWidget(
        host(
          SizedBox(
            height: 550,
            child: AfShell(
              primaryItems: const [
                AfNavItem(id: 'inicio', label: 'Inicio', icon: AfIcons.home),
                AfNavItem(id: 'real', label: 'Real', icon: AfIcons.receipt),
              ],
              utilityItems: const [],
              selectedId: 'inicio',
              onSelect: (id) async {
                requested = id;
                return false;
              },
              periodControl: const Text('Periodo visible'),
              page: const AfPageSlots(
                title: 'Vista',
                body: Text('Contenido'),
                status: Text('Estado'),
                contextTrail: Text('Origen'),
                detailAction: Text('Detalle'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Real'));
      await tester.pump();
      expect(requested, 'real');
      expect(tester.widget<AfShell>(find.byType(AfShell)).selectedId, 'inicio');
      for (final label in [
        'Vista',
        'Contenido',
        'Estado',
        'Origen',
        'Detalle',
        'Periodo visible',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Matriz mantiene cabecera y concepto al desplazar; expansión separada',
    (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var expanded = false;
      await tester.pumpWidget(
        host(
          AfDetailTable(
            caption: 'Matriz 2026 EUR',
            columns: const ['Enero', 'Febrero', 'Total'],
            rows: [
              AfDetailRow(
                label: 'Alimentación / Supermercado',
                onExpand: () => expanded = true,
                values: const [
                  AfMoneyText(AfAmount(-35025)),
                  AfMoneyText(AfAmount(0)),
                  AfMoneyText(AfAmount(-35025)),
                ],
              ),
            ],
          ),
        ),
      );
      final before = tester.getTopLeft(
        find.text('Alimentación / Supermercado'),
      );
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(-200, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Alimentación / Supermercado')).dx,
        closeTo(before.dx, .1),
      );
      await tester.tap(find.byTooltip('Expandir Alimentación / Supermercado'));
      await tester.pump();
      expect(expanded, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 900),
    const Size(360, 900),
    const Size(840, 900),
    const Size(1440, 1000),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Galería sin overflow ${size.width} texto $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AfTheme.light(),
            locale: const Locale('es', 'ES'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('es', 'ES')],
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: const AfKitGallery(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -5000),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
