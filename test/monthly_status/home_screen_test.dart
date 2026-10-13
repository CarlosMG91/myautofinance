import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/app/pending_movement_factory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/monthly_status_query_factory.dart';
import 'package:myautofinance/app/movement_list_factory.dart';
import 'package:myautofinance/app/navigation/budget_links.dart';
import 'package:myautofinance/app/navigation/monthly_status_origin.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/session_location.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/monthly_status/monthly_status.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../support/recovery_reference.dart';
import '../ui/kit_test.dart' show loadAfFonts;

void main() {
  setUpAll(() async {
    await loadAfFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement categories;
  late NavigationSession session;
  late String account;
  late Map<String, String> ids;
  var fail = false;
  Completer<MonthlyStatusQuery>? delayed;
  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    invalidation = CategoryReadInvalidation();
    account = await seedRecoveryReference(db);
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    ids = {for (final c in await categories.list()) c.path: c.node.id};
    session = NavigationSession(
      initialContext: NavigationContext(
        destination: SessionDestination.home,
        period: NavigationPeriod(2026, 1),
      ),
    );
    fail = false;
    delayed = null;
  });
  tearDown(() async {
    session.dispose();
    await invalidation.close();
    await db.close();
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> boot(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('home-visual'),
        child: AutofinanceApp(
          navigationSession: session,
          monthlyStatus: () async {
            if (fail) throw StateError('Fallo sintético');
            if (delayed != null) return delayed!.future;
            return createMonthlyStatusQuery(
              database: db,
              invalidation: invalidation,
            );
          },
          wealth: () async => createWealthManagement(database: db),
          imports: () async =>
              createImportServices(db, onConfirmed: invalidation.invalidate),
          pendingMovements: () async =>
              createPendingMovementSource(db, invalidation),
          categories: () async => categories,
          budgets: () async => createBudgetSource(db, invalidation),
          movements: () async => createMovementListSource(db, invalidation),
        ),
      ),
    );
    await settle(tester);
  }

  Finder summary(String label) => find.byWidgetPredicate(
    (widget) => widget is AfSummaryCard && widget.label == label,
  );
  void amount(String label, int cents) => expect(
    (summary(label).evaluate().single.widget as AfSummaryCard).amount.cents,
    cents,
  );
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> real(String? id, int cents, {String? onAccount}) async {
    await SqliteMovementRepository(db).create(
      MovementInput(
        accountId: onAccount ?? account,
        valueDate: ValueDate(2026, 1, 9),
        concept: 'Prueba sintética',
        amountCents: cents,
        categoryId: id,
      ),
    );
  }

  testWidgets(
    'Inicio EP-001 enero/febrero: cifras firmadas, foto separada, lectura sin escrituras',
    (tester) async {
      final state = await db.readState();
      await boot(tester);
      amount('Resultado real del mes', 122975);
      amount('Resultado presupuestado', 110000);
      amount('Diferencia real − presupuesto', 12975);
      expect(find.byKey(const ValueKey('monthly-status-table')), findsNothing);
      expect(find.text('14.000,00'), findsOneWidget);
      expect(find.textContaining('01/01/2026'), findsOneWidget);
      expect(find.text('Activos líquidos'), findsOneWidget);
      final after = await db.readState();
      expect(after.datasetId, state.datasetId);
      expect(after.revision, state.revision);
      await session.selectPeriod(NavigationPeriod(2026, 2));
      await settle(tester);
      amount('Resultado real del mes', 109990);
      amount('Diferencia real − presupuesto', -10);
      expect(find.text('Sin dato: falta foto patrimonial.'), findsOneWidget);
      expect(find.text('14.000,00'), findsNothing);
      expect(find.textContaining('01/02/2026'), findsOneWidget);
      expect(find.textContaining('Fichas pendientes:'), findsOneWidget);
    },
  );
  testWidgets(
    'Tres niveles, transferencias y Sin clasificar sin doble conteo; cero distinto de ausencia',
    (tester) async {
      await real(ids['Alimentación'], -1200);
      await real(ids['Alimentación / Supermercado'], 200);
      await real(null, 700);
      await real(null, -300);
      final savings = (await SqliteAccountRepository(
        db,
      ).list()).singleWhere((a) => a.name == 'Cuenta de ahorro');
      await real(
        ids['Ahorro / Cuenta de ahorro'],
        50000,
        onAccount: savings.id,
      );
      await SqliteBudgetRepository(db).create(
        BudgetInput(
          month: BudgetMonth(2026, 1),
          categoryId: ids['Ocio']!,
          amountCents: 0,
        ),
      );
      await boot(tester);
      amount('Resultado real del mes', 172375);
      expect(
        find.text('2 movimientos sin categorizar · 2026-01'),
        findsOneWidget,
      );
      final root = ids['Alimentación']!;
      await tap(tester, find.byKey(ValueKey('$root:expandir')));
      final child = ids['Alimentación / Supermercado']!;
      expect(find.byKey(ValueKey('home-category:$child')), findsOneWidget);
      await tap(tester, find.byKey(ValueKey('$child:expandir')));
      expect(
        find.byKey(
          ValueKey(
            'home-category:${ids['Alimentación / Supermercado / Compra semanal']}',
          ),
        ),
        findsOneWidget,
      );
      final charts = find
          .byType(AfBarChart)
          .evaluate()
          .map((e) => e.widget as AfBarChart);
      expect(
        charts
            .singleWhere((c) => c.title == 'Alimentación')
            .data
            .first
            .value
            .amount,
        -36025,
      );
      expect(
        charts.singleWhere((c) => c.title == 'Ahorro').data.first.value.amount,
        0,
      );
      expect(
        charts.singleWhere((c) => c.title == 'Ocio').data.last.value.amount,
        0,
      );
      expect(
        charts
            .singleWhere((c) => c.title == 'Sin clasificar')
            .data
            .last
            .value
            .reason,
        'Sin presupuesto',
      );
    },
  );
  testWidgets(
    'Ver detalle conserva directo/agregado y volver restaura ramas y periodo',
    (tester) async {
      await boot(tester);
      final root = ids['Alimentación']!;
      await tap(tester, find.byKey(ValueKey('$root:expandir')));
      await tap(tester, find.byKey(const ValueKey('home-detail')));
      expect(
        find.byKey(const ValueKey('monthly-status-table')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('$root:directo')), findsOneWidget);
      expect(find.byKey(ValueKey('$root:real')), findsOneWidget);
      final context = tester.element(
        find.byKey(const ValueKey('monthly-status-table')),
      );
      Navigator.of(context).pop();
      await settle(tester);
      expect(session.context.destination, SessionDestination.home);
      expect(
        find.byKey(
          ValueKey('home-category:${ids['Alimentación / Supermercado']}'),
        ),
        findsOneWidget,
      );
      amount('Resultado real del mes', 122975);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  testWidgets(
    'Partidas/reales retornan a Inicio; invalidación relee y no conserva conexión sustituida',
    (tester) async {
      await boot(tester);
      final root = ids['Alimentación']!;
      await tap(tester, find.byKey(ValueKey('$root:expandir')));
      final chart = find.descendant(
        of: find.byKey(ValueKey('home-category:$root')),
        matching: find.byType(AfBarChart),
      );
      final realRow = find.descendant(
        of: chart,
        matching: find.text('Real · Alimentación'),
      );
      await tap(tester, realRow);
      expect(find.textContaining('Volver a Inicio'), findsWidgets);
      final context = tester.element(find.text('Movimientos').first);
      Navigator.of(context).pop();
      await settle(tester);
      final plannedRow = find.descendant(
        of: find.byKey(ValueKey('home-category:$root')),
        matching: find.text('Presupuesto · Alimentación'),
      );
      await tap(tester, plannedRow);
      expect(find.textContaining('Partidas'), findsWidgets);
      Navigator.of(tester.element(find.textContaining('Partidas').first)).pop();
      await settle(tester);
      await real(null, 100);
      invalidation.invalidate();
      await settle(tester);
      amount('Resultado real del mes', 123075);
      final previous = db;
      db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
      await seedRecoveryReference(db);
      categories = createCategoryManagement(
        database: db,
        invalidation: invalidation,
      );
      await previous.close();
      invalidation.invalidate();
      await settle(tester);
      amount('Resultado real del mes', 122975);
      expect(find.text('14.000,00'), findsOneWidget);
    },
  );
  testWidgets(
    'Foto incompleta oculta todos los subtotales; cero manual completa y no afecta flujos',
    (tester) async {
      await SqliteWealthRepository(db).deleteValue(Month(2026, 1), account);
      await boot(tester);
      expect(
        find.text('Sin dato: foto patrimonial incompleta.'),
        findsOneWidget,
      );
      expect(find.text('Fichas pendientes: Cuenta principal'), findsOneWidget);
      expect(find.text('Patrimonio neto'), findsNothing);
      expect(find.text('Activos líquidos'), findsNothing);
      amount('Resultado real del mes', 122975);
      await SqliteWealthRepository(db).setValue(Month(2026, 1), account, 0);
      await tap(tester, find.text('Actualizar'));
      expect(find.text('8.000,00'), findsOneWidget);
      expect(find.text('Activos líquidos'), findsOneWidget);
      amount('Resultado real del mes', 122975);
    },
  );
  testWidgets(
    'Carga/error/reintento y respuesta anterior no reemplaza otro mes',
    (tester) async {
      fail = true;
      await boot(tester);
      expect(find.text('Reintentar'), findsOneWidget);
      fail = false;
      delayed = Completer<MonthlyStatusQuery>();
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      expect(find.text('Consultando el estado del mes…'), findsOneWidget);
      final old = delayed!;
      delayed = null;
      await session.selectPeriod(NavigationPeriod(2026, 2));
      await settle(tester);
      amount('Resultado real del mes', 109990);
      old.complete(
        createMonthlyStatusQuery(database: db, invalidation: invalidation),
      );
      await settle(tester);
      amount('Resultado real del mes', 109990);
    },
  );
  test('Origen Inicio para partidas conserva UUID, expansión y rechaza filtros libres', () {
    final origin = NavigationContext(
      destination: SessionDestination.home,
      period: NavigationPeriod(2026, 1),
      branchId: ids['Alimentación'],
      filters: {'abiertas': ids['Alimentación']!},
      scrollOffset: 123,
      focus: 'home:detalle',
    );
    final route = MonthlyStatusOrigin(origin).route;
    final link = BudgetLinks.list(
      BudgetListQuery(month: BudgetMonth(2026, 1)),
      origin: route,
    );
    final parsed = BudgetLinks.origin(link)!.context;
    expect(parsed.destination, SessionDestination.home);
    expect(parsed.filters, origin.filters);
    expect(parsed.scrollOffset, 123);
    expect(
      () => MonthlyStatusOrigin.parse('$route&externo=1'),
      throwsA(isA<MovementFailure>()),
    );
    final before = session.context;
    expect(
      SessionLocation.resolve('$route&externo=1', session),
      isA<InvalidSessionLocation>(),
    );
    expect(session.context, same(before));
  });
  testWidgets(
    'Importar, Categorizar y Corregir foto usan flujos existentes y retornan con datos frescos',
    (tester) async {
      await boot(tester);
      await tap(tester, find.text('Importar CSV'));
      expect(find.text('Volver a Inicio'), findsWidgets);
      Navigator.of(tester.element(find.text('Volver a Inicio').first)).pop();
      await settle(tester);
      await tap(tester, find.text('Categorizar pendientes'));
      expect(find.byTooltip('Volver a Inicio'), findsOneWidget);
      await tap(tester, find.byTooltip('Volver a Inicio'));
      await settle(tester);
      await tap(tester, find.text('Corregir foto'));
      final field = find.byKey(ValueKey('photo-value-$account'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '6100,00');
      await tap(tester, find.text('Guardar foto'));
      expect(session.context.destination, SessionDestination.home);
      expect(find.text('14.100,00'), findsOneWidget);
      amount('Resultado real del mes', 122975);
    },
  );
  for (final scenario in <String, ({Size size, double scale})>{
    'windows': (size: const Size(1440, 900), scale: 1),
    'android': (size: const Size(412, 915), scale: 1),
    'android-360': (size: const Size(360, 800), scale: 1),
    'texto-200': (size: const Size(320, 1100), scale: 2),
  }.entries) {
    testWidgets(
      'Inicio visual ${scenario.key} y acciones sin recortes',
      (tester) async {
        await boot(
          tester,
          size: scenario.value.size,
          scale: scenario.value.scale,
        );
        await expectLater(
          find.byKey(const Key('home-visual')),
          matchesGoldenFile('home_goldens/${scenario.key}.png'),
        );
        final root = ids['Alimentación']!;
        await tap(tester, find.byKey(ValueKey('$root:expandir')));
        expect(
          find.byKey(
            ValueKey('home-category:${ids['Alimentación / Supermercado']}'),
          ),
          findsOneWidget,
        );
        if (scenario.key == 'windows' || scenario.key == 'texto-200') {
          await expectLater(
            find.byKey(const Key('home-visual')),
            matchesGoldenFile('home_goldens/${scenario.key}-categorias.png'),
          );
        }
      },
      variant: TargetPlatformVariant.only(
        scenario.key == 'windows'
            ? TargetPlatform.windows
            : TargetPlatform.android,
      ),
    );
  }
}
