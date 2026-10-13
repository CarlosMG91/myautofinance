import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/navigation_session_scope.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../support/recovery_reference.dart';
import '../support/wealth_summary.dart';

void main() {
  late LocalDatabase db;
  late WealthManagement management;
  late NavigationSession session;
  late Map<String, String> ids;
  final january = Month(2026, 1), february = Month(2026, 2);

  setUpAll(() async {
    final fonts = FontLoader(AfTokens.family);
    for (final name in ['regular', 'medium', 'bold']) {
      fonts.addFont(rootBundle.load('assets/fonts/roboto-$name.ttf'));
    }
    await fonts.load();
    if (Platform.environment['WEALTH_REDESIGN_CAPTURE'] == '1') {
      final root = Platform.environment['FLUTTER_ROOT'] ?? '.tools/flutter';
      final material = await File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(material)))).load();
    }
  });
  setUp(() async {
    db = LocalDatabase(
      NativeDatabase.memory(setup: (s) => s.execute('PRAGMA foreign_keys=ON')),
    );
    await seedRecoveryReference(db);
    management = createWealthManagement(database: db);
    ids = {for (final a in await management.catalog()) a.name: a.id};
    session = NavigationSession(
      initialContext: NavigationContext(
        destination: SessionDestination.wealth,
        period: NavigationPeriod(2026, 1),
      ),
    );
  });
  tearDown(() async {
    session.dispose();
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await settle(tester);
  }

  Future<void> boot(
    WidgetTester tester, {
    double width = 1440,
    double scale = 1,
    int month = 1,
    TargetPlatform platform = TargetPlatform.windows,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1100);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      NavigationSessionScope(
        session: session,
        child: MaterialApp(
          theme: AfTheme.light().copyWith(platform: platform),
          locale: AppRegional.locale,
          supportedLocales: AppRegional.supportedLocales,
          localizationsDelegates: AppRegional.delegates,
          navigatorObservers: [NavigationSessionObserver(session)],
          initialRoute:
              '/patrimonio?a=2026&m=${month.toString().padLeft(2, '0')}',
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(
              key: const Key('wealth-redesign-capture'),
              child: child!,
            ),
          ),
          onGenerateRoute: (settings) => AppRouter.generateRoute(
            settings,
            wealth: () async => management,
            navigationSession: session,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String name, {Finder? at}) async {
    if (Platform.environment['WEALTH_REDESIGN_CAPTURE'] != '1') return;
    // Esperar las etiquetas flotantes y los cambios de foco antes del PNG.
    await tester.pumpAndSettle();
    if (at != null) {
      await tester.ensureVisible(at);
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('wealth-redesign-capture')),
      );
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('.tools/ma-tsk-212-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Finder field(String name) => find.byKey(ValueKey('photo-value-${ids[name]}'));
  Future<void> input(WidgetTester tester, String name, String value) async {
    await tester.ensureVisible(field(name));
    await tester.enterText(field(name), value);
    await tester.pump();
  }

  testWidgets(
    'Caso D: resumen, distribución completa y ausencia/parcial sin subtotales ni escrituras',
    (tester) async {
      final before = await management.photos.read(january);
      final revision = (await db.readState()).revision;
      await boot(tester);
      expect(wealthSummary('Patrimonio neto', '14.000,00 €'), findsOneWidget);
      expect(wealthSummary('Activos totales', '19.000,00 €'), findsOneWidget);
      final distribution = tester.widget<AfDistributionChart>(
        find.byType(AfDistributionChart),
      );
      expect(distribution.assets.map((a) => a.cents), [900000, 1000000, 0]);
      expect(distribution.totalAssets.cents, 1900000);
      expect(distribution.debt.cents, 500000);
      expect(
        distribution.assets.fold<int>(0, (sum, a) => sum + a.cents),
        distribution.totalAssets.cents,
      );
      await capture(tester, 'windows-summary');
      await capture(
        tester,
        'windows-distribution',
        at: find.text('Distribución de activos por liquidez'),
      );
      await tap(tester, find.text('Mes siguiente'));
      expect(find.textContaining('01/02/2026'), findsOneWidget);
      expect(wealthSummary('Patrimonio neto', 'Sin dato'), findsOneWidget);
      expect(
        tester
            .widget<AfDistributionChart>(find.byType(AfDistributionChart))
            .assets,
        isEmpty,
      );
      await capture(tester, 'windows-absent');
      expect((await db.readState()).revision, revision);
      await tester.runAsync(
        () => management.savePhoto(february, {
          ids['Cuenta principal']!: 620000,
          ids['Deuda familiar']!: 480000,
          ids['Cuenta de ahorro']!: null,
          ids['Cartera']!: null,
        }),
      );
      await tap(tester, find.text('Registrar / editar foto'));
      await tap(tester, find.text('Volver al origen'));
      for (final label in [
        'Patrimonio neto',
        'Activos totales',
        'Activos líquidos',
        'Deudas',
      ]) {
        expect(wealthSummary(label, 'Sin dato'), findsOneWidget);
      }
      expect(find.textContaining('Pendientes:'), findsOneWidget);
      final partial = tester.widget<AfDistributionChart>(
        find.byType(AfDistributionChart),
      );
      expect(partial.state, AfDistributionState.missing);
      expect(partial.assets, isEmpty);
      expect(partial.totalAssets.cents, isNull);
      expect(partial.debt.cents, isNull);
      await capture(tester, 'windows-partial');
      final after = await management.photos.read(january);
      expect(
        after.values.map((v) => (v.id, v.amountCents)),
        before.values.map((v) => (v.id, v.amountCents)),
      );
    },
  );

  testWidgets(
    'Caso D en rutas: cero, guardar y corregir 6200 a 6300 conserva UUID y enero',
    (tester) async {
      final beforeJanuary = await management.photos.read(january);
      await boot(tester, month: 2);
      await tap(tester, find.text('Registrar / editar foto'));
      expect(find.text('Referencia fija: 2026-02-01'), findsOneWidget);
      await input(tester, 'Cuenta principal', '6200');
      await input(tester, 'Deuda familiar', '4800');
      await input(tester, 'Cuenta de ahorro', '0');
      expect(
        find.text('Cero registrado · 0,00 € es un dato válido'),
        findsOneWidget,
      );
      expect(
        find.text('Dato pendiente · Deja vacío si aún no lo conoces'),
        findsOneWidget,
      );
      await input(tester, 'Cartera', '10500');
      await capture(tester, 'windows-photo');
      await tap(tester, find.text('Guardar foto'));
      expect(wealthSummary('Patrimonio neto', '11.900,00 €'), findsOneWidget);
      final saved = await management.photos.read(february);
      expect(
        saved.values
            .singleWhere((v) => v.account.id == ids['Cuenta de ahorro'])
            .amountCents,
        0,
      );
      await tap(tester, find.text('Registrar / editar foto'));
      await input(tester, 'Cuenta principal', '6300');
      await tap(tester, find.text('Guardar foto'));
      expect(wealthSummary('Patrimonio neto', '12.000,00 €'), findsOneWidget);
      final corrected = await management.photos.read(february);
      expect(corrected.snapshotId, saved.snapshotId);
      expect(corrected.values.map((v) => v.id), saved.values.map((v) => v.id));
      expect(
        {for (final v in corrected.values) v.account.name: v.amountCents},
        {
          'Cuenta principal': 630000,
          'Cuenta de ahorro': 0,
          'Cartera': 1050000,
          'Deuda familiar': 480000,
        },
      );
      final afterJanuary = await management.photos.read(january);
      expect(
        afterJanuary.values.map((v) => (v.id, v.amountCents)),
        beforeJanuary.values.map((v) => (v.id, v.amountCents)),
      );
    },
  );

  testWidgets(
    'Historial con huecos, matriz íntegra y liquidez histórica/vigencia desde consulta existente',
    (tester) async {
      await management.savePhoto(Month(2026, 3), {
        for (final id in ids.values) id: 0,
      });
      await management.accounts.changeLiquidity(
        ids['Cartera']!,
        Month(2026, 3),
        Liquidity.liquid,
      );
      final extra = await management.accounts.create(
        name: 'Ficha marzo y abril',
        kind: AccountKind.account,
        activeFrom: Month(2026, 3),
        liquidity: Liquidity.medium,
      );
      await management.photos.setValue(Month(2026, 3), extra.id, 0);
      await management.accounts.close(extra.id, Month(2026, 4));
      await boot(tester);
      await tap(tester, find.text('Ver detalle'));
      expect(find.text('Cuenta principal'), findsOneWidget);
      await capture(
        tester,
        'windows-detail',
        at: find.text('Cuenta principal'),
      );
      await tap(tester, find.text('Las doce fotos de 2026 · sin suma anual'));
      final series = tester
          .widget<AfTimeChart>(find.byType(AfTimeChart))
          .series
          .first;
      expect(series.points, hasLength(12));
      expect(series.points[0].value.amount, 1900000);
      expect(series.points[1].value.amount, isNull);
      expect(series.points[2].value.amount, 0);
      expect(series.points[3].value.amount, isNull);
      expect(
        series.points.map((p) => p.periodIndex),
        List.generate(12, (i) => 2026 * 12 + i),
      );
      await capture(
        tester,
        'windows-history',
        at: find.text('Histórico de activos y deudas'),
      );
      await tap(tester, find.text('Matriz de las doce fotos'));
      final table = tester.widget<AfDetailTable>(find.byType(AfDetailTable));
      expect(table.columns, hasLength(12));
      expect(table.rows.every((r) => r.values.length == 12), isTrue);
      final row = table.rows.singleWhere((r) => r.label == 'Cartera');
      expect((row.values[0] as Semantics).properties.label, contains('Media'));
      expect(
        (row.values[2] as Semantics).properties.label,
        contains('Líquida'),
      );
      final newRow = table.rows.singleWhere(
        (r) => r.label == 'Ficha marzo y abril',
      );
      expect((newRow.values[0] as Text).data, 'Fuera de vigencia');
      expect(
        (newRow.values[3] as Semantics).properties.label,
        contains('Pendiente'),
      );
      expect((newRow.values[4] as Text).data, 'Fuera de vigencia');
      await capture(tester, 'windows-matrix', at: find.byType(AfDetailTable));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('Ver detalle'), findsOneWidget);
      await tap(tester, find.text('Ver detalle'));
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Ver detalle'), findsOneWidget);
    },
  );

  testWidgets(
    'Activos cero: dato completo, deuda separada y distribución sin división',
    (tester) async {
      await management.savePhoto(january, {for (final id in ids.values) id: 0});
      await boot(tester);
      expect(wealthSummary('Patrimonio neto', '0,00 €'), findsOneWidget);
      expect(
        find.text('Distribución no representable: activos totales cero.'),
        findsOneWidget,
      );
      final chart = tester.widget<AfDistributionChart>(
        find.byType(AfDistributionChart),
      );
      expect(chart.state, AfDistributionState.complete);
      expect(chart.assets.every((a) => a.cents == 0), isTrue);
    },
  );

  for (final width in [320.0, 840.0, 1440.0]) {
    testWidgets(
      'Tema real Android $width texto 200 %: resumen, detalle, formulario y Back protegido',
      (tester) async {
        await boot(
          tester,
          width: width,
          scale: 2,
          platform: TargetPlatform.android,
        );
        expect(wealthSummary('Patrimonio neto', '14.000,00 €'), findsOneWidget);
        await capture(
          tester,
          'android-${width.toInt()}-summary-200',
          at: find.byType(AfSummaryCard).first,
        );
        await tap(tester, find.text('Ver detalle'));
        await capture(
          tester,
          'android-${width.toInt()}-detail-200',
          at: find.text('Cuenta principal'),
        );
        await tap(tester, find.text('Registrar / editar foto'));
        await input(tester, 'Cuenta de ahorro', '0');
        await capture(
          tester,
          'android-${width.toInt()}-photo-200',
          at: field('Cuenta de ahorro'),
        );
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(find.text('Hay cambios sin guardar'), findsOneWidget);
        await tap(tester, find.text('Seguir editando'));
        expect(
          tester.widget<TextField>(field('Cuenta de ahorro')).controller!.text,
          '0',
        );
        await tap(tester, find.text('Guardar foto'));
        expect(wealthSummary('Patrimonio neto', '11.000,00 €'), findsOneWidget);
        expect(find.text('Volver al resumen'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(find.text('Ver detalle'), findsOneWidget);
      },
    );
  }
}
