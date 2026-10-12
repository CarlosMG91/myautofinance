import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/navigation/annual_budget_navigation.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/budget_links.dart';
import 'package:myautofinance/app/navigation/budget_origin.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/navigation_session_scope.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/budget/presentation/budget_source.dart';
import 'package:myautofinance/features/budget/presentation/budget_form_screen.dart';
import 'package:myautofinance/features/budget/presentation/monthly_budget_screen.dart';
import 'package:myautofinance/features/movements/movements.dart';

void main() {
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement categories;
  late NavigationSession session;
  late NavigationContext original;
  late String root, leaf, sibling;
  late BudgetRecord zero;
  late FocusNode annualFocus;
  var loads = 0;

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
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<BudgetSource> load() async {
    loads++;
    return createBudgetSource(db, invalidation);
  }

  Widget annual(BuildContext context, AnnualBudgetNavigation navigation) =>
      Scaffold(
        appBar: AppBar(
          title: Text(
            'Consumidor anual ${navigation.year}/${navigation.focusedMonth}',
          ),
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              TextButton(
                focusNode: annualFocus,
                onPressed: () => navigation.openYear(categoryId: root),
                child: const Text('Total rama anual'),
              ),
              TextButton(
                onPressed: () => navigation.openMonth(2),
                child: const Text('Total febrero'),
              ),
              TextButton(
                onPressed: () => navigation.openCell(
                  month: 3,
                  categoryId: sibling,
                  budgetId: zero.id,
                ),
                child: const Text('Cero registrado'),
              ),
              TextButton(
                onPressed: () =>
                    navigation.openCell(month: 4, categoryId: sibling),
                child: const Text('Alta explícita'),
              ),
              TextButton(
                onPressed: navigation.openMonthlyCapture,
                child: const Text('Captura secundaria'),
              ),
            ],
          ),
        ),
      );
  Future<void> boot(
    WidgetTester tester, {
    String? route,
    bool placeholder = false,
    BudgetLoader? loader,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Route<Object?> generate(RouteSettings settings) => AppRouter.generateRoute(
      settings,
      budgets: loader ?? load,
      categories: () async => categories,
      navigationSession: session,
      annualBudgetBuilder: placeholder ? null : annual,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: AppRegional.locale,
        supportedLocales: AppRegional.supportedLocales,
        localizationsDelegates: AppRegional.delegates,
        navigatorObservers: [NavigationSessionObserver(session)],
        onGenerateInitialRoutes: (_) => [
          generate(
            RouteSettings(
              name: route ?? BudgetOrigin(original).route,
              arguments: route == null ? original : null,
            ),
          ),
        ],
        onGenerateRoute: generate,
      ),
    );
    await settle(tester);
  }

  setUp(() async {
    loads = 0;
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    root = (await categories.create(name: 'Hogar', isIncome: false)).node.id;
    final child = (await categories.create(
      name: 'Alquiler',
      parentId: root,
    )).node.id;
    leaf = (await categories.create(name: 'Antigua', parentId: child)).node.id;
    sibling = (await categories.create(name: 'Hogar', isIncome: false)).node.id;
    final budgets = SqliteBudgetRepository(db);
    for (final (category, month, amount) in [
      (root, 1, -100),
      (leaf, 2, -200),
      (sibling, 2, 200),
    ]) {
      await budgets.create(
        BudgetInput(
          month: BudgetMonth(2026, month),
          categoryId: category,
          amountCents: amount,
        ),
      );
    }
    zero = await budgets.create(
      BudgetInput(
        month: BudgetMonth(2026, 3),
        categoryId: sibling,
        amountCents: 0,
      ),
    );
    await categories.archive(leaf);
    original = NavigationContext(
      destination: SessionDestination.budget,
      period: NavigationPeriod(2026, 10),
      branchId: root,
      filters: {'abiertas': '$root,$child'},
      scrollOffset: 123.5,
      focus: '$root:anual',
    );
    session = NavigationSession(
      initialContext: original,
      clock: () => DateTime.utc(2026, 1, 15),
    );
    annualFocus = FocusNode();
  });
  tearDown(() async {
    annualFocus.dispose();
    session.dispose();
    await invalidation.close();
    await db.close();
  });

  testWidgets(
    'Callbacks sin matriz: anual/rama, mes neto cero, retorno completo y foco',
    (tester) async {
      await boot(tester);
      expect(loads, 0);
      annualFocus.requestFocus();
      await tester.pump();
      await tap(tester, find.text('Total rama anual'));
      expect(find.text('Partidas del año'), findsOneWidget);
      expect(find.text('Total de partidas: −3,00 €'), findsOneWidget);
      expect(find.textContaining('Archivada'), findsOneWidget);
      expect(find.text('2026-01'), findsOneWidget);
      expect(find.text('2026-02'), findsOneWidget);
      await tap(tester, find.text('Volver al origen'));
      expect(identical(session.context, original), isTrue);
      expect(annualFocus.hasFocus, isTrue);
      await tap(tester, find.text('Total febrero'));
      expect(find.text('Total de partidas: 0,00 €'), findsOneWidget);
      expect(find.text('Abrir'), findsNWidgets(2));
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(identical(session.context, original), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Cero abre su UUID; edición fuera del año conserva origen hasta Ver mes',
    (tester) async {
      await boot(tester);
      await tap(tester, find.text('Cero registrado'));
      expect(
        tester.widget<BudgetFormScreen>(find.byType(BudgetFormScreen)).id,
        zero.id,
      );
      await tap(tester, find.text('Editar'));
      await tester.enterText(find.byKey(const Key('budget-period')), '2027-02');
      await tap(tester, find.text('Guardar partida'));
      expect(session.period, original.period);
      expect(session.context.branchId, root);
      expect(session.context.scrollOffset, 123.5);
      expect(session.context.focus, original.focus);
      expect(find.text('Ver mes'), findsOneWidget);
      expect(
        (await tester.runAsync(() => SqliteBudgetRepository(db).get(zero.id)))!
            .data
            .month
            .value,
        '2027-02-01',
      );
      await tap(tester, find.text('Ver mes'));
      expect(find.text('Presupuesto mensual'), findsOneWidget);
      expect(session.period, NavigationPeriod(2027, 2));
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(identical(session.context, original), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Ausencia no crea; alta explícita, guardado, borrado confirmado y retorno',
    (tester) async {
      final before = await db.readState();
      await boot(tester);
      await tap(tester, find.text('Alta explícita'));
      await tap(tester, find.text('Cancelar'));
      expect((await db.readState()).revision, before.revision);
      await tap(tester, find.text('Alta explícita'));
      await tester.enterText(find.byKey(const Key('budget-form-amount')), '0');
      await tap(tester, find.text('Guardar partida'));
      expect(identical(session.context, original), isTrue);
      await tap(tester, find.text('Total febrero'));
      await tap(tester, find.text('Volver al origen'));
      await tap(tester, find.text('Cero registrado'));
      await tap(tester, find.text('Eliminar partida'));
      await tap(tester, find.text('Cancelar').last);
      expect(
        (await tester.runAsync(() => SqliteBudgetRepository(db).get(zero.id))),
        isNotNull,
      );
      await tap(tester, find.text('Eliminar partida'));
      await tap(tester, find.widgetWithText(FilledButton, 'Eliminar partida'));
      expect(
        (await tester.runAsync(() => SqliteBudgetRepository(db).get(zero.id))),
        isNull,
      );
      expect(identical(session.context, original), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Captura mensual cambia su periodo local y vuelve sin alterar matriz',
    (tester) async {
      await boot(tester);
      await tap(tester, find.text('Captura secundaria'));
      expect(find.text('Periodo de consulta: 2026-10'), findsOneWidget);
      await tap(tester, find.text('Mes siguiente'));
      expect(find.text('Periodo de consulta: 2026-11'), findsOneWidget);
      expect(identical(session.context, original), isTrue);
      await tap(tester, find.text('Mes actual'));
      expect(find.text('Periodo de consulta: 2026-01'), findsOneWidget);
      expect(identical(session.context, original), isTrue);
      await tap(tester, find.text('Volver a Presupuesto anual'));
      expect(identical(session.context, original), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Lista anual sin historial devuelve ramas/posición/foco; formularios conservan rango',
    (tester) async {
      final route = BudgetLinks.list(
        BudgetListQuery.annual(2026, focusedMonth: 10, categoryId: sibling),
        origin: BudgetOrigin(original).route,
      );
      await boot(tester, route: route);
      expect(find.text('Abrir'), findsNWidgets(2));
      await tap(tester, find.text('Abrir').last);
      await tap(tester, find.textContaining('Volver a Presupuesto,'));
      expect(find.text('Partidas del año'), findsOneWidget);
      expect(find.text('Abrir'), findsNWidgets(2));
      await tap(tester, find.text('Volver al origen'));
      expect(session.context.branchId, root);
      expect(session.context.filters, original.filters);
      expect(session.context.scrollOffset, original.scrollOffset);
      expect(session.context.focus, original.focus);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Errores de rutas no cargan repositorios ni modifican sesión', (
    tester,
  ) async {
    for (final route in [
      '/presupuesto?a=2026&m=10&rama=nombre',
      '/presupuesto?a=0000&m=10',
      '/presupuesto?a=2026&m=10&cuenta=$root',
      '/presupuesto/partidas?a=2026&m=10&desde=12&hasta=01',
      '/presupuesto/mensual?a=2026&m=10&origen=https%3A%2F%2Fexample.com',
      '/presupuesto/partidas/ambiguo?a=2026&m=10',
    ]) {
      await boot(tester, route: route);
      expect(loads, 0, reason: route);
      expect(identical(session.context, original), isTrue, reason: route);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'Captura sin historial reconstruye posición y foco del contexto local',
    (tester) async {
      for (var i = 0; i < 20; i++) {
        await categories.create(name: 'Rama sintética $i', isIncome: false);
      }
      final capture = BudgetOrigin(
        NavigationContext(
          destination: SessionDestination.budget,
          period: original.period,
          view: PeriodView.monthly,
          branchId: sibling,
          scrollOffset: 123.5,
          focus: sibling,
        ),
      );
      await boot(tester, route: capture.route);
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.descendant(
              of: find.byType(MonthlyBudgetScreen),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is SingleChildScrollView &&
                    widget.controller != null,
              ),
            ),
          )
          .controller!;
      expect(scroll.offset, closeTo(123.5, 1));
      final action = tester.widget<TextButton>(
        find.descendant(
          of: find.byKey(ValueKey(sibling)),
          matching: find.widgetWithText(TextButton, 'Abrir alta'),
        ),
      );
      expect(action.focusNode!.hasFocus, isTrue);
      expect(identical(session.context, original), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Entrada EP-018 se habilita solo con entrega; principal anual desde sesión',
    (tester) async {
      final real = createBudgetSource(db, invalidation);
      final unavailable = BudgetSource(
        query: real.query,
        management: real.management,
        categories: real.categories,
        identity: db,
        entries: real.entries,
      );
      await boot(tester, placeholder: true, loader: () async => unavailable);
      expect(
        find.text('Año de consulta: 2026 · Mes enfocado: 2026-10'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Preparar año siguiente'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await boot(tester, placeholder: true);
      await tap(tester, find.text('Preparar año siguiente'));
      expect(find.text('Propuesta'), findsOneWidget);
      expect(session.period, original.period);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(session.context.period, original.period);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        AutofinanceApp(
          navigationSession: session,
          budgets: load,
          annualBudgetBuilder: annual,
        ),
      );
      await settle(tester);
      expect(find.text('Consumidor anual 2026/10'), findsOneWidget);
      expect(session.context.view, PeriodView.annual);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
