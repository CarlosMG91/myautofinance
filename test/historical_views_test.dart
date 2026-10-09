import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/movement_list_factory.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/budget/presentation/budget_source.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_controller.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_screen.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement categories;
  late WealthManagement wealth;
  late BudgetSource budget;
  late MovementListSource movements;
  late NavigationSession session;
  late String accountId, categoryId;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    wealth = createWealthManagement(database: db);
    budget = createBudgetSource(db, invalidation);
    final account = await wealth.accounts.create(
      name: 'Cuenta cerrada sintética',
      kind: AccountKind.account,
      activeFrom: Month(2025, 1),
      activeThrough: Month(2026, 2),
      liquidity: Liquidity.liquid,
    );
    accountId = account.id;
    final debt = await wealth.accounts.create(
      name: 'Deuda sintética',
      kind: AccountKind.debt,
      activeFrom: Month(2026, 1),
    );
    await wealth.photos.setValue(Month(2026, 1), account.id, 90000);
    await wealth.photos.setValue(Month(2026, 1), debt.id, 10000);
    await wealth.photos.setValue(Month(2026, 2), account.id, 70000);
    final archived = await categories.create(
      name: 'Histórico sintético',
      isIncome: false,
    );
    categoryId = archived.node.id;
    final active = await categories.create(
      name: 'Actual sintético',
      isIncome: false,
    );
    await budget.management.create(
      month: BudgetMonth(2026, 1),
      categoryId: categoryId,
      amountCents: 0,
    );
    await budget.management.create(
      month: BudgetMonth(2026, 2),
      categoryId: active.node.id,
      amountCents: -12300,
    );
    final repository = SqliteMovementRepository(db);
    for (final (day, amount) in [(10, -200), (11, 500), (12, -100)]) {
      await repository.create(
        MovementInput(
          accountId: accountId,
          valueDate: ValueDate(2026, 1, day),
          concept: 'Registro $day',
          amountCents: amount,
          categoryId: categoryId,
        ),
      );
    }
    await repository.create(
      MovementInput(
        accountId: accountId,
        valueDate: ValueDate(2026, 2, 1),
        concept: 'Fuera de enero',
        amountCents: -400,
      ),
    );
    await categories.archive(categoryId);
    movements = createMovementListSource(db, invalidation);
    session = NavigationSession(clock: () => DateTime.utc(2026, 1, 15));
  });

  tearDown(() async {
    session.dispose();
    await invalidation.close();
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> boot(
    WidgetTester tester, {
    BudgetLoader? budgets,
    WealthManagementLoader? photos,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AutofinanceApp(
        navigationSession: session,
        categories: () async => categories,
        budgets: budgets ?? () async => budget,
        wealth: photos ?? () async => wealth,
        movements: () async => movements,
      ),
    );
    await settle(tester);
  }

  NavigatorState nav(WidgetTester tester) =>
      tester.state(find.byType(Navigator));
  MovementListController list(WidgetTester tester) => tester
      .widget<MovementListScreen>(find.byType(MovementListScreen))
      .controller;

  testWidgets(
    'Histórico cerrado/archivado y futuro: fotos exactas, ausencia y cero, sin escrituras',
    (tester) async {
      await boot(tester);
      final revision = (await tester.runAsync(db.readState))!.revision;
      await tap(tester, find.byKey(const ValueKey('destination-wealth')));
      expect(find.text('Patrimonio neto: 800,00\u00a0€'), findsOneWidget);
      await tap(tester, find.text('Mes siguiente'));
      expect(
        find.text('Sin dato: foto patrimonial incompleta'),
        findsOneWidget,
      );
      expect(find.text('Patrimonio neto: Sin dato'), findsOneWidget);
      expect(find.text('Pendientes: Deuda sintética'), findsOneWidget);
      await tap(tester, find.text('Mes siguiente'));
      expect(find.text('Sin dato: falta foto patrimonial'), findsOneWidget);
      expect(find.text('Cuenta cerrada sintética'), findsNothing);
      await tap(tester, find.widgetWithText(TextButton, 'Presupuesto'));
      expect(find.text('Total mensual: Sin presupuesto'), findsOneWidget);
      await tap(tester, find.text('Mes anterior'));
      expect(find.text('Total mensual: −123,00 €'), findsOneWidget);
      await tap(tester, find.text('Mes anterior'));
      expect(
        find.text('Histórico archivado · incluido en el total'),
        findsOneWidget,
      );
      expect(find.text('0,00 € (registrado)'), findsOneWidget);
      expect(find.text('Total mensual: 0,00 €'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('period-year')), '2035');
      await tap(tester, find.text('Ir al periodo'));
      expect(find.text('Total mensual: Sin presupuesto'), findsOneWidget);
      expect((await tester.runAsync(db.readState))!.revision, revision);
    },
  );

  testWidgets(
    'Gestión desde presupuesto usa el mes elegido; filtros custom no cambian sesión ni pestañas',
    (tester) async {
      await boot(tester);
      await tap(tester, find.byKey(const ValueKey('destination-budget')));
      await tap(tester, find.byTooltip('Gestión'));
      await tap(tester, find.text('Movimientos'));
      expect(list(tester).from.value, '2026-01-01');
      expect(list(tester).page!.subtotalCents, 200);
      expect(list(tester).paths[categoryId], 'Histórico sintético');
      expect(list(tester).accounts[accountId], 'Cuenta cerrada sintética');
      await tester.enterText(
        find.widgetWithText(TextField, 'Desde · AAAA-MM-DD'),
        '2026-02-01',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Hasta exclusivo · AAAA-MM-DD'),
        '2026-03-01',
      );
      await tap(tester, find.text('Aplicar filtros'));
      expect(list(tester).page!.subtotalCents, -400);
      expect(session.period, NavigationPeriod(2026, 1));
      await tap(tester, find.widgetWithText(TextButton, 'Patrimonio'));
      expect(session.period, NavigationPeriod(2026, 1));
      expect(find.text('Patrimonio neto: 800,00\u00a0€'), findsOneWidget);
    },
  );

  testWidgets(
    'Default implícito sigue sesión; periodo explícito y rango tienen prioridad local',
    (tester) async {
      await boot(tester);
      nav(tester).pushNamed('/movimientos');
      await settle(tester);
      list(tester).selectPage();
      await session.selectPeriod(NavigationPeriod(2026, 2));
      await settle(tester);
      expect(list(tester).from.value, '2026-02-01');
      expect(list(tester).selected, isEmpty);
      expect(list(tester).pageIndex, 0);
      expect(list(tester).page!.subtotalCents, -400);
      nav(tester).pop();
      await settle(tester);
      nav(
        tester,
      ).pushNamed('/movimientos?a=2026&m=01&desde=2026-01-11&hasta=2026-01-13');
      await settle(tester);
      expect(list(tester).page!.subtotalCents, 400);
      await session.selectPeriod(NavigationPeriod(2035, 4));
      await settle(tester);
      expect(list(tester).from.value, '2026-01-11');
      expect(list(tester).page!.subtotalCents, 400);
    },
  );

  test('Cambio de periodo durante lectura invalida página, selección y respuesta antigua; fallo sin cifras previas', () async {
    final gate = Completer<MovementListSource>();
    var delayed = false, fail = false;
    final c = MovementListController(
      load: () async {
        if (fail) throw StateError('Fallo de lectura sintético');
        if (delayed) {
          delayed = false;
          return gate.future;
        }
        return movements;
      },
      from: ValueDate(2026, 1, 1),
      until: ValueDate(2026, 2, 1),
      pageSize: 1,
    );
    addTearDown(c.dispose);
    await c.refresh();
    await c.next();
    c.selectPage();
    delayed = true;
    final old = c.refresh();
    await c.changePeriod(ValueDate(2026, 2, 1), ValueDate(2026, 3, 1));
    expect(c.selected, isEmpty);
    expect(c.pageIndex, 0);
    expect(c.page!.subtotalCents, -400);
    gate.complete(movements);
    await old;
    expect(c.page!.subtotalCents, -400);
    fail = true;
    await c.changePeriod(ValueDate(2035, 1, 1), ValueDate(2035, 2, 1));
    expect(c.page, isNull);
    expect(c.error, isNotNull);
    fail = false;
    await c.refresh();
    expect(c.page!.subtotalCents, 0);
    expect(c.page!.records, isEmpty);
  });

  testWidgets(
    'Presupuesto: lectura tardía y fallo no sustituyen el periodo nuevo',
    (tester) async {
      final gate = Completer<BudgetSource>();
      var calls = 0, fail = false;
      await boot(
        tester,
        budgets: () async {
          if (calls++ == 0) return gate.future;
          if (fail) throw StateError('Fallo sintético');
          return budget;
        },
      );
      nav(tester).pushNamed('/presupuesto');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Consultando presupuesto…'), findsOneWidget);
      await tap(tester, find.text('Mes siguiente').last);
      expect(find.text('Total mensual: −123,00 €'), findsOneWidget);
      gate.complete(budget);
      await settle(tester);
      expect(session.period, NavigationPeriod(2026, 2));
      expect(find.text('Total mensual: 0,00 €'), findsNothing);
      fail = true;
      await tap(tester, find.text('Mes siguiente'));
      expect(session.period, NavigationPeriod(2026, 3));
      expect(find.textContaining('Total mensual:'), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
    },
  );

  testWidgets(
    'Patrimonio: año tardío y error no muestran la foto del año anterior',
    (tester) async {
      final gate = Completer<WealthManagement>();
      var calls = 0, fail = false;
      await boot(
        tester,
        photos: () async {
          if (calls++ == 0) return gate.future;
          if (fail) throw StateError('Fallo sintético');
          return wealth;
        },
      );
      nav(tester).pushNamed('/patrimonio');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Cargando patrimonio…'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('period-year')).last, '2035');
      await tap(tester, find.text('Ir al periodo').last);
      expect(find.text('Sin dato: falta foto patrimonial'), findsOneWidget);
      gate.complete(wealth);
      await settle(tester);
      expect(find.text('Patrimonio neto: 800,00\u00a0€'), findsNothing);
      fail = true;
      await tester.enterText(find.byKey(const Key('period-year')), '2036');
      await tap(tester, find.text('Ir al periodo'));
      expect(
        find.textContaining('No se pudo cargar el patrimonio.'),
        findsOneWidget,
      );
      expect(find.textContaining('Patrimonio neto:'), findsNothing);
    },
  );

  for (final savedDate in ['2026-01-20', '2026-02-20']) {
    testWidgets(
      'Movimiento guardado en $savedDate fuera del rango ofrece Ver mes y vuelve al origen',
      (tester) async {
        await boot(tester);
        nav(tester).pushNamed(
          '/movimientos?desde=2026-01-10&hasta=2026-01-11&concepto=Registro',
        );
        await settle(tester);
        final c = list(tester);
        final id = c.page!.records.single.id;
        final button = find.text('Abrir Registro 10');
        await tap(tester, button);
        await tap(tester, find.text('Editar'));
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Fecha de valor · AAAA-MM-DD'),
          savedDate,
        );
        await tap(tester, find.text('Guardar movimiento'));
        expect(session.period, NavigationPeriod(2026, 1));
        expect(list(tester), same(c));
        expect(c.from.value, '2026-01-10');
        expect(c.until!.value, '2026-01-11');
        expect(c.concept, 'Registro');
        expect(c.page!.records, isEmpty);
        expect(c.context.focus, id);
        expect(find.text('Ver mes'), findsOneWidget);
        await tap(tester, find.text('Ver mes'));
        expect(list(tester).from.value, '${savedDate.substring(0, 7)}-01');
        expect(
          list(tester).page!.records.length,
          savedDate.startsWith('2026-01') ? 3 : 2,
        );
        expect(session.period, NavigationPeriod(2026, 1));
        nav(tester).pop();
        await settle(tester);
        expect(list(tester), same(c));
        expect(c.from.value, '2026-01-10');
      },
    );
  }

  testWidgets(
    'Presupuesto: cancelar y guardar fuera de mes conserva origen; cambiar periodo reinicia posición',
    (tester) async {
      final ids = <String>[];
      for (var i = 0; i < 20; i++) {
        ids.add(
          (await categories.create(
            name: 'Rama ${i.toString().padLeft(2, '0')}',
            isIncome: false,
          )).node.id,
        );
      }
      await boot(tester);
      await tap(tester, find.byKey(const ValueKey('destination-budget')));
      final row = find.byKey(ValueKey(ids.last));
      final detail = find.descendant(
        of: row,
        matching: find.text('Abrir alta'),
      );
      await tester.ensureVisible(detail);
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.ancestor(
              of: row,
              matching: find.byType(SingleChildScrollView),
            ),
          )
          .controller!;
      final offset = scroll.offset;
      expect(offset, greaterThan(0));
      await tap(tester, detail);
      expect(session.context.scrollOffset, closeTo(offset, 1));
      expect(session.context.focus, ids.last);
      await tap(tester, find.text('Cancelar'));
      expect(session.period, NavigationPeriod(2026, 1));
      expect(scroll.offset, closeTo(offset, 1));
      expect(
        tester
            .widget<TextButton>(
              find.ancestor(of: detail, matching: find.byType(TextButton)),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.tap(detail);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('budget-period')), '2026-02');
      await tester.enterText(
        find.widgetWithText(TextField, 'Importe firmado (€)'),
        '0',
      );
      await tap(tester, find.text('Guardar partida'));
      expect(session.period, NavigationPeriod(2026, 1));
      expect(scroll.offset, closeTo(offset, 1));
      expect(session.context.focus, ids.last);
      expect(find.text('Ver mes'), findsOneWidget);
      await tap(tester, find.text('Ver mes'));
      expect(session.period, NavigationPeriod(2026, 2));
      nav(tester).pop();
      await settle(tester);
      expect(session.period, NavigationPeriod(2026, 1));
      expect(scroll.offset, closeTo(offset, 1));
      await tap(tester, find.text('Mes siguiente'));
      expect(session.period, NavigationPeriod(2026, 2));
      expect(scroll.offset, 0);
      expect(session.context.focus, isNull);
    },
  );

  for (final width in [400.0, 1440.0]) {
    testWidgets(
      'Patrimonio: detalle devuelve scroll y foco de ficha a $width px',
      (tester) async {
        late AccountRecord last;
        for (var i = 0; i < 20; i++) {
          last = await wealth.accounts.create(
            name: 'Z cuenta ${i.toString().padLeft(2, '0')}',
            kind: AccountKind.account,
            activeFrom: Month(2026, 1),
            liquidity: Liquidity.liquid,
          );
        }
        await boot(tester);
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpAndSettle();
        await tap(tester, find.byKey(const ValueKey('destination-wealth')));
        final button = find.widgetWithText(TextButton, last.name);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final scroll = tester
            .widget<SingleChildScrollView>(
              find.ancestor(
                of: button,
                matching: find.byType(SingleChildScrollView),
              ),
            )
            .controller!;
        final offset = scroll.offset;
        expect(offset, greaterThan(0));
        final revision = (await tester.runAsync(db.readState))!.revision;
        await tap(tester, button);
        expect(session.context.scrollOffset, closeTo(offset, 1));
        expect(session.context.focus, 'account:${last.id}');
        await tap(tester, find.text('Volver a Patrimonio, 2026-01'));
        expect(session.period, NavigationPeriod(2026, 1));
        expect(scroll.offset, closeTo(offset, 1));
        expect(tester.widget<TextButton>(button).focusNode!.hasFocus, isTrue);
        expect((await tester.runAsync(db.readState))!.revision, revision);
        await tap(tester, find.text('Mes siguiente'));
        expect(scroll.offset, 0);
        expect(session.context.focus, isNull);
      },
    );
  }

  testWidgets(
    'Movimientos: cancelar borrador y detalle conserva consulta, selección, scroll y foco',
    (tester) async {
      await boot(tester);
      tester.view.physicalSize = const Size(400, 1000);
      nav(tester).pushNamed(
        '/movimientos?desde=2026-01-01&hasta=2026-02-01&concepto=Registro',
      );
      await settle(tester);
      final c = list(tester);
      c.selectPage();
      final button = find.widgetWithText(TextButton, 'Abrir Registro 10');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.ancestor(
              of: button,
              matching: find.byType(SingleChildScrollView),
            ),
          )
          .controller!;
      final offset = scroll.offset;
      final revision = (await tester.runAsync(db.readState))!.revision;
      await tester.tap(button);
      await settle(tester);
      await tap(tester, find.text('Editar'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Concepto'),
        'Borrador sintético',
      );
      await tap(tester, find.text('Cancelar'));
      await tap(tester, find.text('Seguir editando'));
      expect(find.text('Borrador sintético'), findsOneWidget);
      await tap(tester, find.text('Cancelar'));
      await tap(tester, find.text('Descartar cambios'));
      await tap(tester, find.text('Volver a Movimientos'));
      expect(list(tester), same(c));
      expect(c.concept, 'Registro');
      expect(c.selected.length, 3);
      expect(c.pageIndex, 0);
      expect(scroll.offset, closeTo(offset, 1));
      expect(tester.widget<TextButton>(button).focusNode!.hasFocus, isTrue);
      expect(session.period, NavigationPeriod(2026, 1));
      expect((await tester.runAsync(db.readState))!.revision, revision);
    },
  );
}
