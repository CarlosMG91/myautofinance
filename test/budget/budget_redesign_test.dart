import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/navigation_session_scope.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/budget/presentation/budget_source.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../support/recovery_reference.dart';

void main() {
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late BudgetSource source;
  late NavigationSession session;

  setUpAll(() async {
    final fonts = FontLoader(AfTokens.family);
    for (final name in ['regular', 'medium', 'bold']) {
      fonts.addFont(rootBundle.load('assets/fonts/roboto-$name.ttf'));
    }
    await fonts.load();
    if (Platform.environment['BUDGET_REDESIGN_CAPTURE'] == '1') {
      final flutterRoot =
          Platform.environment['FLUTTER_ROOT'] ?? '.tools/flutter';
      final material = await File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(material)))).load();
    }
  });

  setUp(() async {
    db = LocalDatabase(
      NativeDatabase.memory(
        setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    await seedRecoveryReference(db);
    invalidation = CategoryReadInvalidation();
    source = createBudgetSource(db, invalidation);
    session = NavigationSession(
      initialContext: NavigationContext(
        destination: SessionDestination.budget,
        period: NavigationPeriod(2026, 1),
      ),
    );
  });
  tearDown(() async {
    session.dispose();
    await invalidation.close();
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

  Future<void> tap(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(finder));
    await settle(tester);
  }

  Future<void> boot(
    WidgetTester tester, {
    double width = 1440,
    double scale = 1,
    TargetPlatform platform = TargetPlatform.windows,
    String route = '/presupuesto?a=2026&m=01',
    BudgetLoader? load,
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
          initialRoute: route,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(
              key: const Key('redesign-capture'),
              child: child!,
            ),
          ),
          onGenerateRoute: (settings) => AppRouter.generateRoute(
            settings,
            budgets: load ?? () async => source,
            categories: () async => createCategoryManagement(
              database: db,
              invalidation: invalidation,
            ),
            navigationSession: session,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String name, {Finder? at}) async {
    if (Platform.environment['BUDGET_REDESIGN_CAPTURE'] != '1') return;
    if (at != null) {
      await tester.ensureVisible(at);
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('redesign-capture')),
      );
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('.tools/ma-tsk-211-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'Entrada visual y detalle conservan +13200 y los 48 UUID; Back y Escape vuelven al resumen',
    (tester) async {
      final before = await SqliteBudgetRepository(db).readYear(2026);
      await boot(tester);
      expect(find.byKey(const Key('matrix-scroll-region')), findsNothing);
      expect(find.byKey(const Key('budget-summary-year')), findsOneWidget);
      expect(find.text('+13.200,00'), findsOneWidget);
      expect(find.text('+36.000,00 €'), findsOneWidget);
      expect(
        find.text('2026 · 48 partidas · Suma de doce meses'),
        findsOneWidget,
      );
      await capture(tester, 'windows-summary');
      await tap(tester, find.byKey(const Key('budget-show-detail')));
      expect(find.text('Diciembre'), findsOneWidget);
      expect(find.textContaining('+13.200,00 €\n48 partidas'), findsWidgets);
      await capture(tester, 'windows-detail');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const Key('budget-summary-year')), findsOneWidget);
      final detailButton = tester.widget<OutlinedButton>(
        find.byKey(const Key('budget-show-detail')),
      );
      expect(detailButton.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.text('Diciembre'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byKey(const Key('budget-summary-year')), findsOneWidget);
      final after = await SqliteBudgetRepository(db).readYear(2026);
      expect(after.map((r) => r.id).toSet(), before.map((r) => r.id).toSet());
      expect(
        after.map((r) => r.data.amountCents),
        before.map((r) => r.data.amountCents),
      );
    },
  );

  testWidgets('El refresco del resumen relee las partidas sin duplicar ramas', (
    tester,
  ) async {
    await boot(tester);
    final records = await SqliteBudgetRepository(db).readYear(2026);
    final record = records.firstWhere((r) => r.data.amountCents == -40000);
    await tester.runAsync(
      () => source.management.edit(record.id, amountCents: -41000),
    );
    await tap(tester, find.text('Actualizar año'));
    expect(find.text('+13.190,00'), findsOneWidget);
    expect(find.text('+36.000,00 €'), findsOneWidget);
    await tap(tester, find.byKey(const Key('budget-show-detail')));
    expect(find.textContaining('+13.190,00 €\n48 partidas'), findsWidgets);
  });

  for (final width in [320.0, 840.0]) {
    testWidgets(
      'Android $width / 200%: resumen, detalle y captura mensual sin scroll horizontal global',
      (tester) async {
        await boot(
          tester,
          width: width,
          scale: 2,
          platform: TargetPlatform.android,
        );
        expect(find.text('+13.200,00'), findsOneWidget);
        expect(find.byType(AfSummaryCard), findsWidgets);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          ),
          findsNothing,
        );
        await capture(
          tester,
          'android-${width.toInt()}-summary-200',
          at: find.byKey(const Key('budget-summary-year')),
        );
        await tap(tester, find.byKey(const Key('budget-show-detail')));
        expect(find.text('Los doce meses'), findsWidgets);
        expect(find.byKey(const Key('matrix-scroll-region')), findsNothing);
        await capture(
          tester,
          'android-${width.toInt()}-detail-200',
          at: find.text('Total anual 2026'),
        );
        await tap(tester, find.text('Captura mensual'));
        expect(find.text('Resultado presupuestado del mes'), findsOneWidget);
        expect(find.text('+1.100,00 €'), findsOneWidget);
        await capture(
          tester,
          'android-${width.toInt()}-monthly-200',
          at: find.text('Resultado presupuestado del mes'),
        );
      },
    );
  }

  testWidgets(
    'Propuesta Android 320 / 200%: mes sin reales, signo atípico y revisión explícita conservan el borrador',
    (tester) async {
      await boot(
        tester,
        width: 320,
        scale: 2,
        platform: TargetPlatform.android,
        route: '/presupuesto/propuesta?a=2026&m=01',
      );
      await tap(tester, find.text('Generar propuesta'));
      await capture(
        tester,
        'android-proposal-200',
        at: find.text('Borrador · 2027'),
      );
      await tap(tester, find.byKey(const Key('proposal-show-detail')));
      expect(find.text('Diciembre 2027'), findsOneWidget);
      await tap(tester, find.text('Marzo 2027'));
      expect(find.text('Sin reales · cero explícito'), findsNWidgets(5));
      final categories = (await tester.runAsync(source.categories))!;
      final food = categories
          .firstWhere((c) => c.path == 'Alimentación')
          .node
          .id;
      await tap(tester, find.byKey(ValueKey('edit-$food-2027-03-01')));
      await tester.enterText(
        find.widgetWithText(TextField, 'Importe propuesto'),
        '25',
      );
      await tap(tester, find.text('Aplicar importe'));
      expect(find.text('Alimentación: +25,00 €'), findsOneWidget);
      expect(find.text('Revisar signo de la partida'), findsOneWidget);
      await tap(tester, find.text('Revisar y guardar'));
      expect(find.text('Comparar propuesta 2027'), findsNothing);
      expect(
        await tester.runAsync(() => SqliteBudgetRepository(db).readYear(2027)),
        isEmpty,
      );
      await tap(
        tester,
        find.widgetWithText(
          CheckboxListTile,
          'He revisado los signos señalados',
        ),
      );
      await tap(tester, find.text('Revisar y guardar'));
      expect(find.text('Comparar propuesta 2027'), findsOneWidget);
      await capture(tester, 'android-proposal-review-200');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Alimentación: +25,00 €'), findsOneWidget);
      expect(
        await tester.runAsync(() => SqliteBudgetRepository(db).readYear(2027)),
        isEmpty,
      );
    },
  );

  testWidgets(
    'Propuesta: resumen, matriz y mes equivalente muestran el mismo borrador; cancelar no escribe',
    (tester) async {
      await boot(tester, route: '/presupuesto/propuesta?a=2026&m=01');
      await tap(tester, find.text('Generar propuesta'));
      expect(find.text('Borrador · 2027'), findsOneWidget);
      expect(
        find.text('60 partidas · Incluye tus ediciones · Pendiente de guardar'),
        findsOneWidget,
      );
      expect(find.text('Propuesto inicial: −360,00 €'), findsOneWidget);
      await capture(tester, 'windows-proposal');
      await tap(tester, find.byKey(const Key('proposal-show-detail')));
      final tree = await source.categories();
      final food = tree.firstWhere((c) => c.path == 'Alimentación').node.id;
      final february = find.byKey(ValueKey('proposal-cell-$food-2027-02-01'));
      tester.widget<TextButton>(february).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      expect(tester.getRect(february).left, greaterThanOrEqualTo(256));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.text('Real fuente: −420,10 €'), findsOneWidget);
      expect(find.text('Propuesto inicial: −430,00 €'), findsOneWidget);
      await tap(tester, find.byKey(ValueKey('edit-$food-2027-02-01')));
      await tester.enterText(
        find.widgetWithText(TextField, 'Importe propuesto'),
        '-440',
      );
      await tap(tester, find.text('Aplicar importe'));
      expect(find.text('Alimentación: −440,00 €'), findsOneWidget);
      final yearBefore = await SqliteBudgetRepository(db).readYear(2026);
      expect(await SqliteBudgetRepository(db).readYear(2027), isEmpty);
      await tap(tester, find.text('Revisar y guardar'));
      expect(find.text('Comparar propuesta 2027'), findsOneWidget);
      await capture(tester, 'windows-proposal-review');
      await tap(tester, find.text('Cancelar').last);
      expect(find.text('Alimentación: −440,00 €'), findsOneWidget);
      expect(await SqliteBudgetRepository(db).readYear(2027), isEmpty);
      final yearAfter = await SqliteBudgetRepository(db).readYear(2026);
      expect(
        yearAfter.map((r) => r.id).toSet(),
        yearBefore.map((r) => r.id).toSet(),
      );
    },
  );
}
