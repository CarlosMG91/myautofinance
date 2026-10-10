import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/movement_list_factory.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/budget_links.dart';
import 'package:myautofinance/app/navigation/monthly_status_detail_navigation.dart';
import 'package:myautofinance/app/navigation/monthly_status_origin.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/navigation_session_scope.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/monthly_status/monthly_status.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement categories;
  late NavigationSession session;
  late NavigationContext original;
  late String root;
  late MonthlyFigureDetail detail;
  late BudgetRecord budget;
  var reads = 0;
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

  Widget originPage() => Builder(
    builder: (context) {
      final callbacks = createMonthlyStatusDetailCallbacks(
        context: context,
        origin: () => session.context,
        session: session,
      );
      return Scaffold(
        body: Column(
          children: [
            const Text('Origen sintético de Estado'),
            TextButton(
              onPressed: () => callbacks.onDifference(detail),
              child: const Text('Diferencia'),
            ),
            TextButton(
              onPressed: () => callbacks.onBudgets(detail),
              child: const Text('Previsto'),
            ),
            TextButton(
              onPressed: () => callbacks.onMovements(detail),
              child: const Text('Real'),
            ),
          ],
        ),
      );
    },
  );
  Future<void> boot(
    WidgetTester tester, {
    String? initial,
    double width = 1440,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Route<Object?> route(RouteSettings settings) =>
        Uri.parse(settings.name!).path == '/estado'
        ? MaterialPageRoute(settings: settings, builder: (_) => originPage())
        : AppRouter.generateRoute(
            settings,
            budgets: () async {
              reads++;
              return createBudgetSource(db, invalidation);
            },
            movements: () async => createMovementListSource(db, invalidation),
            categories: () async => categories,
            navigationSession: session,
          );
    await tester.pumpWidget(
      MaterialApp(
        locale: AppRegional.locale,
        supportedLocales: AppRegional.supportedLocales,
        localizationsDelegates: AppRegional.delegates,
        navigatorObservers: [
          NavigationSessionObserver(session, monthlyBudget: true),
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        onGenerateInitialRoutes: (_) => [
          route(
            RouteSettings(
              name: initial ?? MonthlyStatusOrigin(original).route,
              arguments: initial == null ? original : null,
            ),
          ),
        ],
        onGenerateRoute: route,
      ),
    );
    await settle(tester);
  }

  setUp(() async {
    reads = 0;
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    root = (await categories.create(
      name: 'Raíz sintética',
      isIncome: false,
    )).node.id;
    budget = await SqliteBudgetRepository(db).create(
      BudgetInput(
        month: BudgetMonth(2026, 1),
        categoryId: root,
        amountCents: -40000,
      ),
    );
    detail = MonthlyFigureDetail(month: BudgetMonth(2026, 1), categoryId: root);
    original = NavigationContext(
      destination: SessionDestination.status,
      period: NavigationPeriod(2026, 1),
      branchId: root,
      filters: {'abiertas': root},
      scrollOffset: 123.5,
      focus: '$root:previsto',
    );
    session = NavigationSession(initialContext: original);
  });
  tearDown(() async {
    session.dispose();
    await invalidation.close();
    await db.close();
  });
  testWidgets(
    'Diferencia ofrece ambas fuentes y cancelar no consulta ni escribe',
    (tester) async {
      await boot(tester);
      final before = await db.readState();
      await tap(tester, find.text('Diferencia'));
      expect(find.text('Ver movimientos reales'), findsOneWidget);
      expect(find.text('Ver partidas previstas'), findsOneWidget);
      await tap(tester, find.text('Cancelar'));
      expect(reads, 0);
      expect(identical(session.context, original), isTrue);
      expect((await db.readState()).revision, before.revision);
      await tap(tester, find.text('Diferencia'));
      await tap(tester, find.text('Ver movimientos reales'));
      expect(
        find.byTooltip('Volver a Estado del mes, 01/2026'),
        findsOneWidget,
      );
      await tap(tester, find.byTooltip('Volver a Estado del mes, 01/2026'));
      expect(session.context.scrollOffset, 123.5);
      expect(session.context.focus, original.focus);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Guardar partida fuera de origen vuelve a lista vacía y ofrece Ver mes',
    (tester) async {
      await boot(tester);
      await tap(tester, find.text('Diferencia'));
      await tap(tester, find.text('Ver partidas previstas'));
      expect(find.text('−400,00 €'), findsOneWidget);
      await tap(tester, find.text('Abrir'));
      await tap(tester, find.text('Editar'));
      await tester.enterText(find.byKey(const Key('budget-period')), '2026-02');
      await tap(tester, find.text('Guardar partida'));
      expect(
        find.textContaining('Sin presupuesto · No hay partidas'),
        findsOneWidget,
      );
      expect(find.text('Ver mes'), findsOneWidget);
      expect(session.period, original.period);
      final saved = await tester.runAsync(
        () => SqliteBudgetRepository(db).get(budget.id),
      );
      expect(saved!.data.month.value, '2026-02-01');
      await tap(tester, find.text('Ver mes'));
      expect(session.period, NavigationPeriod(2026, 2));
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester);
      await tap(tester, find.text('Volver al origen'));
      expect(identical(session.context, original), isTrue);
      expect(session.context.filters, {'abiertas': root});
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Ausencia abre lista vacía y captura explícita reutilizada sin crear al cancelar',
    (tester) async {
      detail = MonthlyFigureDetail(
        month: BudgetMonth(2026, 2),
        categoryId: root,
      );
      await boot(tester, width: 320, scale: 2);
      final before = await db.readState();
      await tap(tester, find.text('Previsto'));
      expect(
        find.textContaining('Sin presupuesto · No hay partidas'),
        findsOneWidget,
      );
      await tap(tester, find.text('Crear partida'));
      expect(find.byKey(const Key('budget-form-amount')), findsOneWidget);
      await tap(tester, find.text('Cancelar'));
      expect(find.text('Partidas del mes'), findsOneWidget);
      expect((await db.readState()).revision, before.revision);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Lista sin pila restaura el contexto serializado completo', (
    tester,
  ) async {
    await boot(
      tester,
      initial: BudgetLinks.list(
        detail.budgets,
        origin: MonthlyStatusOrigin(original).route,
      ),
      width: 320,
      scale: 2,
    );
    expect(find.text('−400,00 €'), findsOneWidget);
    await tap(tester, find.text('Volver al origen'));
    expect(find.text('Origen sintético de Estado'), findsOneWidget);
    expect(session.context.scrollOffset, 123.5);
    expect(session.context.focus, original.focus);
    expect(session.context.filters, original.filters);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Editar real fuera del mes conserva origen, lista y acción Ver mes',
    (tester) async {
      final account = await SqliteAccountRepository(db).create(
        name: 'Cuenta sintética',
        kind: AccountKind.account,
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      );
      final real = await SqliteMovementRepository(db).create(
        MovementInput(
          accountId: account.id,
          valueDate: ValueDate(2026, 1, 15),
          concept: 'Movimiento sintético',
          amountCents: -1200,
          categoryId: root,
        ),
      );
      await boot(tester);
      await tap(tester, find.text('Real'));
      await tap(tester, find.text('Abrir Movimiento sintético'));
      await tap(tester, find.text('Editar'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Fecha de valor · AAAA-MM-DD'),
        '2026-02-01',
      );
      await tap(tester, find.text('Guardar movimiento'));
      expect(find.text('Ver mes'), findsOneWidget);
      expect(session.period, original.period);
      final saved = await tester.runAsync(
        () => SqliteMovementRepository(db).get(real.id),
      );
      expect(saved!.data.valueDate.value, '2026-02-01');
      await tap(tester, find.byTooltip('Volver a Estado del mes, 01/2026'));
      expect(identical(session.context, original), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('IDs y rutas inválidos muestran error sin cargar fuentes', (
    tester,
  ) async {
    await boot(tester, initial: '/presupuesto/partidas/ambiguo?a=2026&m=01');
    expect(find.text('No se pudo abrir este detalle'), findsOneWidget);
    expect(reads, 0);
    await tester.pumpWidget(const SizedBox());
    await boot(
      tester,
      initial: '/presupuesto/partidas?a=2026&m=01&rama=$root&rama=$root',
    );
    expect(find.text('No se pudo abrir este detalle'), findsOneWidget);
    expect(reads, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
