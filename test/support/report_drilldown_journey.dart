import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/features/budget/presentation/budget_list_screen.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_controller.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_screen.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

import 'drilldown_reference.dart';

/// Composición, rutas, informes, filtros y formularios originales sobre SQLite
/// en archivo. El mismo recorrido sirve a widgets y al runner nativo.
Future<void> reportDrilldownJourney(
  WidgetTester tester,
  Directory directory,
) async {
  final local = LocalBackupSession(supportDirectory: () async => directory);
  final navigation = NavigationSession(
    initialContext: NavigationContext(
      destination: SessionDestination.status,
      period: NavigationPeriod(2026, 1),
    ),
  );
  Future<T> io<T>(Future<T> Function() action) async {
    Object? error;
    StackTrace? trace;
    final value = await tester.runAsync(() async {
      var done = false;
      T? value;
      final work = action()
          .timeout(const Duration(seconds: 45))
          .then<void>(
            (result) {
              value = result;
              done = true;
            },
            onError: (Object caught, StackTrace stack) {
              error = caught;
              trace = stack;
              done = true;
            },
          );
      while (!done) {
        await tester.pump(const Duration(milliseconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await work;
      return value;
    });
    if (error != null) Error.throwWithStackTrace(error!, trace!);
    return value as T;
  }

  Future<void> settle() async {
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 100));
      if (i >= 6 &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.textContaining('Cargando').evaluate().isEmpty &&
          find.textContaining('Guardando…').evaluate().isEmpty) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return;
      }
    }
    fail('El recorrido conjunto no terminó de cargar.');
  }

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(finder));
    await settle();
  }

  Future<void> press(String label) => tap(find.text(label).last);
  Future<void> back() async {
    await tester.binding.handlePopRoute();
    await settle();
  }

  Future<void> route(String name) async {
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .pushNamedAndRemoveUntil(name, (_) => false);
    await settle();
  }

  Future<void> enter(String label, String value) async {
    final field = find.widgetWithText(TextFormField, label);
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
  }

  MovementListController list() => tester
      .widget<MovementListScreen>(find.byType(MovementListScreen))
      .controller;
  void real(Set<String> ids, int cents) {
    final c = list();
    expect(c.error, isNull);
    expect(c.page!.totalCount, ids.length);
    expect(c.page!.subtotalCents, cents);
    expect(c.page!.records.map((r) => r.id), unorderedEquals(ids));
  }

  Future<Map<String, Object?>> snapshot(
    LocalDatabase db,
    List<String> tables,
  ) => io(
    () async => {
      for (final table in tables)
        table: (await db.customSelect('SELECT * FROM $table ORDER BY 1').get())
            .map((r) => r.data)
            .toList(),
    },
  );
  const protectedTables = [
    'wealth_snapshots',
    'wealth_values',
    'accounts',
    'account_liquidity_periods',
    'import_rows',
    'import_batches',
  ];
  const allTables = [
    ...protectedTables,
    'movements',
    'budgets',
    'categories',
    'database_state',
  ];
  Object metadata(Map<String, Object?> snapshot, String table) => [
    for (final row in snapshot[table]! as List)
      Map<String, Object?>.from(row as Map)
        ..remove('amount_cents')
        ..remove('updated_at'),
  ];
  final fixture = DrilldownReference();
  try {
    final db = await io(local.store.open);
    await io(() => fixture.seed(db, local.categoryInvalidation));
    final protected = await snapshot(db, protectedTables);
    expect(await io(local.open), isTrue);
    await tester.pumpWidget(
      AutofinanceApp(localSession: local, navigationSession: navigation),
    );
    await settle();
    final food = fixture.categories['ALI']!;
    final leaf = fixture.categories['COMP']!;
    final r03 = fixture.movements['R03']!.id;
    final p03 = fixture.budgets['P03']!.id;

    debugPrint(
      'EP-024 Estado → real: origen, filtro local, cancelar/guardar y retorno',
    );
    await tap(find.byKey(ValueKey('$food:real')));
    real({r03}, -35025);
    final origin = navigation.context;
    final c = list();
    c.categoryId = leaf;
    c.scope = MovementCategoryScope.direct;
    c.accountId = fixture.accounts['C1'];
    await io(c.apply);
    await settle();
    expect(find.textContaining('Nuevo ámbito local'), findsWidgets);
    expect(navigation.context.period, origin.period);
    expect(navigation.context.filters, origin.filters);
    await press('Abrir R03');
    final listOffset = c.scrollOffset;
    final rawBefore = await snapshot(db, ['movements']);
    await press('Editar');
    await enter('Importe firmado (EUR)', '-999');
    await press('Cancelar');
    await press('Descartar cambios');
    expect(await snapshot(db, ['movements']), rawBefore);
    await press('Editar');
    await enter('Importe firmado (EUR)', '-360');
    await press('Guardar movimiento');
    real({r03}, -36000);
    expect(
      metadata(await snapshot(db, ['movements']), 'movements'),
      metadata(rawBefore, 'movements'),
    );
    expect(c.scrollOffset, closeTo(listOffset, 1));
    expect(list().categoryId, leaf);
    expect(list().scope, MovementCategoryScope.direct);
    expect(list().accountId, fixture.accounts['C1']);
    final open = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Abrir R03'),
    );
    expect(open.focusNode!.hasFocus, isTrue);
    await press('Restablecer filtros del informe');
    real({r03}, -36000);
    expect(list().categoryId, food);
    expect(list().accountId, isNull);
    await back();
    expect(navigation.period, origin.period);
    expect(navigation.context.filters, origin.filters);
    expect(navigation.context.focus, origin.focus);
    final status = await io(
      () async => (await local.monthlyStatus()).read(BudgetMonth(2026, 1)),
    );
    expect(status.total.actualCents, 171500);

    debugPrint(
      'EP-024 Estado → partidas: sin cuenta, alcance y formulario original',
    );
    await tap(find.byKey(ValueKey('$food:previsto')));
    expect(find.text(p03), findsOneWidget);
    expect(find.text('Cuenta'), findsNothing);
    expect(find.text('Sin clasificar'), findsNothing);
    final budgetsBefore = await snapshot(db, ['budgets']);
    await press('Abrir');
    await press('Editar');
    await tester.enterText(find.byKey(const Key('budget-form-amount')), '-410');
    await press('Guardar partida');
    expect(find.text('Total de partidas: −410,00 €'), findsOneWidget);
    expect(
      metadata(await snapshot(db, ['budgets']), 'budgets'),
      metadata(budgetsBefore, 'budgets'),
    );
    await press('Volver al origen');

    debugPrint(
      'EP-024 Presupuesto anual → lista: rango local, reset y mismo UUID',
    );
    await route('/presupuesto?a=2026&m=10');
    await tap(
      find.descendant(
        of: find.byKey(ValueKey('budget-summary-$food')),
        matching: find.text('Abrir partidas'),
      ),
    );
    expect(find.text('Total de partidas: −810,00 €'), findsOneWidget);
    final budgetOrigin = navigation.context;
    expect(
      tester
          .widget<BudgetListScreen>(find.byType(BudgetListScreen))
          .query
          .isAnnual,
      isTrue,
    );
    await tap(find.byType(DropdownButtonFormField<String>).first);
    await press('Rango de meses');
    await tester.enterText(find.byType(TextField).first, '2025-12');
    await tester.enterText(find.byType(TextField).last, '2026-01');
    await press('Aplicar filtros');
    expect(find.text(p03), findsOneWidget);
    expect(find.text('Total de partidas: −410,00 €'), findsOneWidget);
    final budgetScroll = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .firstWhere((scroll) => scroll.controller != null)
        .controller!;
    await press('Abrir');
    final budgetOffset = budgetScroll.offset;
    await press('Editar');
    await press('Cancelar');
    expect(find.text('Total de partidas: −410,00 €'), findsOneWidget);
    expect(budgetScroll.offset, closeTo(budgetOffset, 1));
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Abrir'))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await press('Restablecer filtros del informe');
    expect(find.text('Total de partidas: −810,00 €'), findsOneWidget);
    await press('Volver al origen');
    expect(navigation.period, budgetOrigin.period);
    expect(navigation.context.filters, budgetOrigin.filters);
    expect(navigation.context.focus, budgetOrigin.focus);

    debugPrint('EP-024 Real anual: neto cero, vacío y duplicados legítimos');
    await route('/real/detalle?a=2026&m=10');
    await tap(find.byKey(ValueKey('actual-${fixture.categories['NET']}:year')));
    real({'R12', 'R13'}.map((n) => fixture.movements[n]!.id).toSet(), 0);
    await back();
    await tap(
      find.byKey(ValueKey('actual-${fixture.categories['EMPTY']}:year')),
    );
    real({}, 0);
    await back();
    await tap(
      find.byKey(ValueKey('actual-${fixture.categories['OCIO']}:year')),
    );
    real(
      {'R04', 'R05', 'R10', 'R14'}.map((n) => fixture.movements[n]!.id).toSet(),
      -2000,
    );
    await back();

    debugPrint(
      'EP-024 Real anual: páginas, escritura y restauración con lista abierta',
    );
    await tap(find.byKey(const ValueKey('actual-all:year')));
    final pageController = list();
    final annualOrigin = navigation.context;
    await tester.enterText(
      find.widgetWithText(TextField, 'Desde · AAAA-MM-DD'),
      '2026-01-01',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Hasta exclusivo · AAAA-MM-DD'),
      '2026-02-01',
    );
    await press('Aplicar filtros');
    real(
      {
        'R01',
        'R02',
        'R03',
        'R04',
        'R05',
        'R06',
        'R12',
        'R13',
      }.map((n) => fixture.movements[n]!.id).toSet(),
      171500,
    );
    expect(navigation.period, annualOrigin.period);
    await press('Restablecer filtros del informe');
    expect(pageController.page!.totalCount, 13);
    expect(pageController.page!.subtotalCents, 331490);
    await io(() async {
      for (var i = 0; i < 205; i++) {
        await SqliteMovementRepository(db).create(
          MovementInput(
            accountId: fixture.accounts['C1']!,
            valueDate: ValueDate(2026, 1, 31),
            categoryId: food,
            amountCents: -100,
            concept: 'Página $i',
          ),
        );
      }
      await pageController.refresh(restart: true);
    });
    await settle();
    final ids = <String>{};
    for (var page = 0; page < 3; page++) {
      expect(pageController.page!.totalCount, 218);
      expect(pageController.page!.subtotalCents, 310990);
      for (final record in pageController.page!.records) {
        expect(ids.add(record.id), isTrue);
      }
      if (page < 2) await press('Página siguiente');
    }
    expect(ids, hasLength(218));
    final selected = pageController.page!.records.first.id;
    await io(local.controller.create);
    expect(local.controller.error, isNull);
    final backup = local.controller.listing!.entries.single.backupId;
    final beforeRestore = await snapshot(db, allTables);
    pageController.toggle(selected, true);
    await io(() async => SqliteMovementRepository(db).delete(selected));
    await io(pageController.refresh);
    await settle();
    expect(pageController.selected, isEmpty);
    expect(pageController.pageIndex, 0);
    expect(pageController.page!.totalCount, 217);
    await io(() => local.controller.restore(backup, confirmed: true));
    expect(local.controller.restoreResult!.status, LocalRestoreStatus.restored);
    await settle();
    final restored = await io(local.store.open);
    await io(pageController.refresh);
    await settle();
    expect(pageController.selected, isEmpty);
    expect(pageController.pageIndex, 0);
    expect(pageController.page!.totalCount, 218);
    expect(pageController.page!.subtotalCents, 310990);
    expect(await snapshot(restored, allTables), beforeRestore);
    expect(await snapshot(restored, protectedTables), protected);
    await back();
    expect(navigation.period, NavigationPeriod(2026, 10));
    expect(
      (await io(() async => (await local.annualActual()).read(2026)))
          .annualTotal
          .amountCents,
      310990,
    );
    debugPrint('EP-024 recorrido conjunto correcto');
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await io(local.store.close);
    local.controller.dispose();
    await io(local.categoryInvalidation.close);
    navigation.dispose();
  }
}
