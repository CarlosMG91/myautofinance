import 'dart:async';

import '../support/drilldown_capture.dart';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/navigation/budget_links.dart';
import 'package:myautofinance/app/navigation/budget_list_route.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/budget/presentation/budget_list_screen.dart';
import 'package:myautofinance/features/budget/presentation/budget_source.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

void main() {
  setUpAll(loadDrilldownFonts);
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement categories;
  late String root, child;
  var fail = false;
  Future<BudgetSource> load() async {
    if (fail) throw StateError('Lectura sintética fallida');
    return createBudgetSource(db, invalidation);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> choose(WidgetTester tester, Type type, String label) async {
    final field = find.byType(type).last;
    await tap(tester, field);
    await tap(tester, find.text(label).last);
  }

  Future<void> boot(
    WidgetTester tester,
    Widget screen,
    Size size,
    double scale,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AfTheme.light(),
        locale: AppRegional.locale,
        supportedLocales: AppRegional.supportedLocales,
        localizationsDelegates: AppRegional.delegates,
        builder: (context, child) => RepaintBoundary(
          key: drilldownCaptureKey,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: screen,
      ),
    );
    await settle(tester);
  }

  setUp(() async {
    fail = false;
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    root = (await categories.create(
      name: 'Alimentación',
      isIncome: false,
    )).node.id;
    child = (await categories.create(name: 'Compra', parentId: root)).node.id;
    final repository = SqliteBudgetRepository(db);
    for (final (month, category, cents) in [
      (BudgetMonth(2025, 12), child, -10000),
      (BudgetMonth(2026, 1), root, -20000),
      (BudgetMonth(2026, 2), child, 20000),
      (BudgetMonth(2026, 3), root, 0),
    ]) {
      await repository.create(
        BudgetInput(month: month, categoryId: category, amountCents: cents),
      );
    }
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
  });

  test('Ruta entre años conserva límites, mes de captura y alcance', () {
    final query = BudgetListQuery.range(
      month: BudgetMonth(2026, 10),
      firstMonth: BudgetMonth(2025, 12),
      lastMonth: BudgetMonth(2026, 2),
      categoryId: root,
      scope: MovementCategoryScope.direct,
    );
    final restored = BudgetLinks.parse(BudgetLinks.list(query));
    expect(restored.firstMonth.value, '2025-12-01');
    expect(restored.lastMonth.value, '2026-02-01');
    expect(restored.month.value, '2026-10-01');
    expect(restored.scope, MovementCategoryScope.direct);
    expect(restored.categoryId, root);
    for (final range in [
      'desde=2025-12&hasta=02',
      'desde=2026-13&hasta=2027-01',
      'desde=0000-01&hasta=2026-01',
    ]) {
      expect(
        () => BudgetLinks.parse('/presupuesto/partidas?a=2026&m=10&$range'),
        throwsException,
      );
    }
  });

  for (final (platform, size, scale) in [
    (TargetPlatform.windows, const Size(1440, 1000), 1.0),
    (TargetPlatform.android, const Size(412, 1000), 1.0),
    (TargetPlatform.android, const Size(320, 1000), 2.0),
  ]) {
    testWidgets(
      'Filtros partidas, error, reset, cero y retorno $platform $scale',
      (tester) async {
        final initial = BudgetListQuery.annual(
          2026,
          focusedMonth: 10,
          categoryId: root,
        );
        BudgetListQuery? applied;
        await boot(
          tester,
          Theme(
            data: AfTheme.light().copyWith(platform: platform),
            child: BudgetListScreen(
              load: load,
              query: initial,
              onReturn: () {},
              onCreate: () async {},
              onOpen: (_) async {},
              onQueryChanged: (value) => applied = value,
            ),
          ),
          size,
          scale,
        );
        expect(find.text('Resultados del ámbito: 3 partidas'), findsOneWidget);
        expect(find.text('Total de partidas: 0,00 €'), findsOneWidget);
        expect(find.text('Abrir'), findsNWidgets(3));
        await captureDrilldown(
          tester,
          'partidas-${platform.name}-${size.width.toInt()}-$scale',
        );
        expect(find.text('Cuenta'), findsNothing);
        expect(find.text('Sin clasificar'), findsNothing);
        await choose(
          tester,
          DropdownButtonFormField<MovementCategoryScope>,
          'Solo directos',
        );
        await tap(tester, find.text('Aplicar filtros'));
        expect(applied!.scope, MovementCategoryScope.direct);
        expect(find.text('Resultados del ámbito: 2 partidas'), findsOneWidget);
        expect(find.text('Total de partidas: −200,00 €'), findsOneWidget);
        expect(find.textContaining('Nuevo ámbito local:'), findsOneWidget);
        fail = true;
        await tap(tester, find.text('Restablecer filtros del informe'));
        expect(find.text('No se pudo abrir este detalle'), findsOneWidget);
        expect(find.textContaining('Total de partidas:'), findsNothing);
        fail = false;
        await tap(tester, find.text('Reintentar'));
        expect(applied!.scope, MovementCategoryScope.branch);
        expect(find.text('Resultados del ámbito: 3 partidas'), findsOneWidget);
        final mode = find.byType(DropdownButtonFormField<String>).first;
        await tap(tester, mode);
        await tap(tester, find.text('Rango de meses').last);
        await tester.enterText(find.byType(TextField).first, '2025-12');
        await tester.enterText(find.byType(TextField).last, '2026-01');
        await tap(tester, find.text('Aplicar filtros'));
        expect(find.text('Resultados del ámbito: 2 partidas'), findsOneWidget);
        expect(find.text('Total de partidas: −300,00 €'), findsOneWidget);
        await tap(tester, find.text('Restablecer filtros del informe'));
        expect(find.text('Total de partidas: 0,00 €'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('Respuestas tardías de partidas no sustituyen el ámbito nuevo', (
    tester,
  ) async {
    final pending = Completer<BudgetSource>();
    var calls = 0;
    await boot(
      tester,
      BudgetListScreen(
        load: () => ++calls == 1 ? pending.future : load(),
        query: BudgetListQuery.annual(2026),
        onReturn: () {},
        onCreate: () async {},
        onOpen: (_) async {},
      ),
      const Size(1440, 1000),
      1,
    );
    await tap(tester, find.byType(DropdownButtonFormField<String>).first);
    await tap(tester, find.text('Mes').last);
    await tester.enterText(find.byType(TextField).first, '2025-12');
    await tap(tester, find.text('Aplicar filtros'));
    expect(find.text('Total de partidas: −100,00 €'), findsOneWidget);
    pending.complete(await load());
    await settle(tester);
    expect(find.text('Total de partidas: −100,00 €'), findsOneWidget);
    expect(find.text('Resultados del ámbito: 1 partidas'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    '205 partidas: contador y subtotal global; vacío conserva origen',
    (tester) async {
      final repository = SqliteBudgetRepository(db);
      for (var i = 0; i < 205; i++) {
        final category = await categories.create(
          name: 'Duplicada',
          isIncome: false,
        );
        await repository.create(
          BudgetInput(
            month: BudgetMonth(2027, 1),
            categoryId: category.node.id,
            amountCents: -100,
          ),
        );
      }
      await boot(
        tester,
        BudgetListScreen(
          load: load,
          query: BudgetListQuery.annual(2027),
          onReturn: () {},
          onCreate: () async {},
          onOpen: (_) async {},
        ),
        const Size(1440, 1000),
        1,
      );
      expect(find.text('Resultados del ámbito: 205 partidas'), findsOneWidget);
      expect(find.text('Total de partidas: −205,00 €'), findsOneWidget);
      expect(find.text('Abrir'), findsNWidgets(100));
      await tap(tester, find.text('Página siguiente'));
      expect(find.text('Abrir'), findsNWidgets(100));
      expect(find.text('Total de partidas: −205,00 €'), findsOneWidget);
      await tap(tester, find.text('Página siguiente'));
      expect(find.text('Página 3'), findsOneWidget);
      expect(find.text('Abrir'), findsNWidgets(5));
      expect(find.text('Resultados del ámbito: 205 partidas'), findsOneWidget);
      await tap(tester, find.byType(DropdownButtonFormField<String>).first);
      await tap(tester, find.text('Mes').last);
      await tester.enterText(find.byType(TextField).first, '2028-01');
      await tap(tester, find.text('Aplicar filtros'));
      expect(find.text('Resultados del ámbito: 0 partidas'), findsOneWidget);
      expect(find.text('Total de partidas: 0,00 €'), findsOneWidget);
      expect(find.text('Página 1'), findsOneWidget);
      expect(
        find.textContaining('Ámbito del informe: 2027-01'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Restauración retira partidas y bloquea restablecer una rama ausente',
    (tester) async {
      final replacement = LocalDatabase(
        NativeDatabase.memory(setup: configureConnection),
      );
      addTearDown(replacement.close);
      var restored = false;
      await boot(
        tester,
        BudgetListScreen(
          load: () async =>
              createBudgetSource(restored ? replacement : db, invalidation),
          query: BudgetListQuery.annual(2026, categoryId: root),
          onReturn: () {},
          onCreate: () async {},
          onOpen: (_) async => restored = true,
        ),
        const Size(412, 1000),
        1,
      );
      expect(find.text('Resultados del ámbito: 3 partidas'), findsOneWidget);
      await tap(tester, find.text('Abrir').first);
      expect(find.text('No se pudo abrir este detalle'), findsOneWidget);
      expect(find.textContaining('Total de partidas:'), findsNothing);
      expect(find.text('Abrir'), findsNothing);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(
                TextButton,
                'Restablecer filtros del informe',
              ),
            )
            .onPressed,
        isNull,
      );
      await choose(
        tester,
        DropdownButtonFormField<String>,
        'Todas las categorías',
      );
      await tap(tester, find.text('Aplicar filtros'));
      expect(find.text('Resultados del ámbito: 0 partidas'), findsOneWidget);
      expect(find.text('Total de partidas: 0,00 €'), findsOneWidget);
      expect(
        find.textContaining('Ámbito del informe: 2026-01'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Editor recibe filtros locales y mantiene origen en la ruta', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    RouteSettings? opened;
    final originContext = NavigationContext(
      destination: SessionDestination.budget,
      period: NavigationPeriod(2026, 10),
      filters: {'abiertas': root},
      scrollOffset: 120,
      focus: root,
    );
    final session = NavigationSession(initialContext: originContext);
    addTearDown(session.dispose);
    final initial = BudgetListQuery.annual(2026, categoryId: root);
    final route = BudgetLinks.list(initial, origin: '/presupuesto?a=2026&m=10');
    await tester.pumpWidget(
      MaterialApp(
        theme: AfTheme.light(),
        locale: AppRegional.locale,
        supportedLocales: AppRegional.supportedLocales,
        localizationsDelegates: AppRegional.delegates,
        builder: (context, child) =>
            RepaintBoundary(key: drilldownCaptureKey, child: child!),
        home: Builder(
          builder: (context) => BudgetListRoute(
            settings: RouteSettings(name: route),
            load: load,
            navigationSession: session,
          ),
        ),
        onGenerateRoute: (settings) {
          opened = settings;
          return MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar detalle'),
                ),
              ),
            ),
          );
        },
      ),
    );
    await settle(tester);
    expect(find.byKey(const Key('period-year')), findsNothing);
    expect(find.textContaining('Periodo del informe:'), findsOneWidget);
    await captureDrilldown(tester, 'partidas-shell-windows');
    await choose(
      tester,
      DropdownButtonFormField<MovementCategoryScope>,
      'Solo directos',
    );
    await tap(tester, find.text('Aplicar filtros'));
    tester.view.physicalSize = const Size(412, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    await settle(tester);
    await captureDrilldown(tester, 'partidas-shell-android-local');
    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first)
        .controller!;
    await tap(tester, find.text('Abrir').first);
    final offset = scroll.offset;
    final query = BudgetLinks.parse(
      Uri.parse(opened!.name!).replace(path: BudgetLinks.path).toString(),
    );
    expect(query.scope, MovementCategoryScope.direct);
    expect(identical(session.context, originContext), isTrue);
    expect(BudgetLinks.origin(opened!.name!)!.context.period.month, 10);
    await tap(tester, find.text('Cancelar detalle'));
    expect(find.text('Total de partidas: −200,00 €'), findsOneWidget);
    expect(scroll.offset, closeTo(offset, 1));
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Abrir').first,
    );
    expect(button.focusNode!.hasFocus, isTrue);
    expect(identical(session.context, originContext), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
