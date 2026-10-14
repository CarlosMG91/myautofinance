import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/movement_list_factory.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/movement_links.dart';
import 'package:myautofinance/app/navigation/annual_actual_navigation.dart';
import 'package:myautofinance/app/navigation/annual_actual_origin.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/navigation_session_scope.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/actual_spending/actual_spending.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement categories;
  late NavigationSession session;
  late NavigationContext original;
  late String root;
  late AnnualActualDetail detail;
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
      final navigation = AnnualActualNavigation(
        context: context,
        origin: () => AnnualActualOrigin(session.context, detail: true),
        session: session,
      );
      return Scaffold(
        body: Column(
          children: [
            const Text('Origen anual'),
            TextButton(
              onPressed: () => navigation.open(detail),
              child: const Text('Real'),
            ),
            TextButton(
              onPressed: navigation.addMovement,
              child: const Text('Añadir'),
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
        Uri.parse(settings.name!).path == '/real/detalle'
        ? MaterialPageRoute(settings: settings, builder: (_) => originPage())
        : AppRouter.generateRoute(
            settings,
            movements: () async {
              reads++;
              return createMovementListSource(db, invalidation);
            },
            categories: () async => categories,
            navigationSession: session,
          );
    await tester.pumpWidget(
      MaterialApp(
        locale: AppRegional.locale,
        supportedLocales: AppRegional.supportedLocales,
        localizationsDelegates: AppRegional.delegates,
        navigatorObservers: [NavigationSessionObserver(session)],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        onGenerateInitialRoutes: (_) => [
          route(
            RouteSettings(
              name: initial ?? AnnualActualOrigin(original, detail: true).route,
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
    detail = AnnualActualDetail(year: 2026, categoryId: root);
    original = NavigationContext(
      destination: SessionDestination.actual,
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
        '2027-02-01',
      );
      await tap(tester, find.text('Guardar movimiento'));
      expect(find.text('Ver mes'), findsOneWidget);
      expect(session.period, original.period);
      final saved = await tester.runAsync(
        () => SqliteMovementRepository(db).get(real.id),
      );
      expect(saved!.data.valueDate.value, '2027-02-01');
      await tap(tester, find.text('Ver mes'));
      expect(session.period, NavigationPeriod(2027, 2));
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester);
      await tap(tester, find.byTooltip('Volver a Real anual, 2026'));
      expect(identical(session.context, original), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Sin pila restaura contexto anual serializado', (tester) async {
    await boot(
      tester,
      initial: MovementLinks.list(
        detail.movements,
        origin: AnnualActualOrigin(original, detail: true).route,
      ),
    );
    await tap(tester, find.byTooltip('Volver a Real anual, 2026'));
    expect(find.text('Origen anual'), findsOneWidget);
    expect(session.context.scrollOffset, original.scrollOffset);
    expect(session.context.focus, original.focus);
    expect(session.context.filters, original.filters);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Añadir usa mes enfocado y cancelar no escribe', (tester) async {
    original = NavigationContext(
      destination: SessionDestination.actual,
      period: NavigationPeriod(2026, 7),
      filters: {'abiertas': root},
      scrollOffset: 123.5,
    );
    session.setContext(original);
    await boot(tester);
    final before = await db.readState();
    await tap(tester, find.text('Añadir'));
    expect(find.widgetWithText(TextFormField, '2026-07-01'), findsOneWidget);
    await tap(tester, find.text('Cancelar'));
    expect(find.text('Origen anual'), findsOneWidget);
    expect(identical(session.context, original), isTrue);
    expect((await db.readState()).revision, before.revision);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Origen inválido muestra error antes de cargar', (tester) async {
    final initial = Uri(
      path: '/movimientos',
      queryParameters: {
        'desde': '2026-01-01',
        'hasta': '2027-01-01',
        'origen': '/real?a=2026&m=01&posicion=NaN',
      },
    ).toString();
    await boot(tester, initial: initial);
    expect(
      find.text('Periodo o destino de navegación inválido.'),
      findsOneWidget,
    );
    expect(reads, 0);
    expect(identical(session.context, original), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Editor anual sin pila permite cambiar mes dentro del ano', (
    tester,
  ) async {
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
    await boot(
      tester,
      initial: MovementLinks.detail(
        real.id,
        detail.movements,
        origin: AnnualActualOrigin(original, detail: true).route,
      ),
    );
    await tap(tester, find.text('Editar'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Fecha de valor · AAAA-MM-DD'),
      '2026-02-01',
    );
    await tap(tester, find.text('Guardar movimiento'));
    expect(find.text('Ver mes'), findsNothing);
    expect(session.period, original.period);
    final saved = await tester.runAsync(
      () => SqliteMovementRepository(db).get(real.id),
    );
    expect(saved!.data.valueDate.value, '2026-02-01');
    await tap(tester, find.byTooltip('Volver a Real anual, 2026'));
    expect(session.context.period, original.period);
    expect(session.context.scrollOffset, original.scrollOffset);
    expect(session.context.filters, original.filters);
    await tester.pumpWidget(const SizedBox());
  });
}
