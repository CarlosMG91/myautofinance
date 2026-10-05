import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';

/// MA-TSK-104 F1–F4, W1–W8, H1/H3 y R1–R6 sobre la composición real.
/// La carpeta suministrada es desechable y nunca contiene la base personal.
Future<void> budgetLifecycleJourney(
  WidgetTester tester,
  Directory directory, {
  required bool desktop,
}) async {
  var session = LocalBackupSession(supportDirectory: () async => directory);
  final january = BudgetMonth(2026, 1);
  final february = BudgetMonth(2026, 2);
  Future<T> io<T>(Future<T> Function() action) async {
    Object? error;
    StackTrace? trace;
    final value = await tester.runAsync(() async {
      try {
        return await action().timeout(const Duration(seconds: 45));
      } catch (caught, stack) {
        error = caught;
        trace = stack;
        return null;
      }
    });
    if (error != null) Error.throwWithStackTrace(error!, trace!);
    return value as T;
  }

  Future<void> settle() async {
    for (var turn = 0; turn < 150; turn++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 100));
      final pending =
          find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
          find.textContaining('Cargando').evaluate().isNotEmpty ||
          find.textContaining('Consultando').evaluate().isNotEmpty ||
          find.textContaining('Leyendo').evaluate().isNotEmpty ||
          find.textContaining('Guardando').evaluate().isNotEmpty ||
          find.textContaining('Persistiendo').evaluate().isNotEmpty;
      if (turn >= 5 && !pending) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return;
      }
    }
    fail('La operación de presupuesto no terminó.');
  }

  Future<void> tap(Finder target) async {
    await settle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(target));
    await settle();
  }

  Future<void> press(String label) => tap(find.text(label).last);
  Finder field(String key) => find.byKey(Key(key));
  String value(String key) =>
      tester.widget<TextField>(field(key)).controller!.text;
  Future<void> enter(String key, String text) async {
    await settle();
    await tester.ensureVisible(field(key));
    await tester.enterText(field(key), text);
    await tester.pump();
  }

  Finder row(String id, String label) => find.descendant(
    of: find.byKey(ValueKey(id)),
    matching: find.widgetWithText(TextButton, label),
  );
  NavigatorState navigator() =>
      tester.state<NavigatorState>(find.byType(Navigator).first);
  Future<void> route(String name) async {
    navigator().pushNamedAndRemoveUntil(name, (_) => false);
    await settle();
  }

  Future<void> month(int number) =>
      route('/presupuesto?a=2026&m=${number.toString().padLeft(2, '0')}');
  Future<void> open(String id, {int origin = 1}) => route(
    '/presupuesto/partidas/$id?a=2026&m=${origin.toString().padLeft(2, '0')}',
  );
  Future<Map<String, Object?>> snapshot({bool protectedOnly = false}) =>
      io(() async {
        final db = await session.store.open();
        return {
          for (final table in [
            'categories',
            'import_batches',
            'import_rows',
            'movements',
            'accounts',
            'account_liquidity_periods',
            'wealth_snapshots',
            'wealth_values',
            if (!protectedOnly) ...['budgets', 'database_state'],
          ])
            table:
                (await db.customSelect('SELECT * FROM $table ORDER BY 1').get())
                    .map((r) => r.data)
                    .toList(),
        };
      });
  Future<int> revision() =>
      io(() async => (await (await session.store.open()).readState()).revision);
  Future<List<BudgetRecord>> records(BudgetMonth period) => io(
    () async => SqliteBudgetRepository(await session.store.open()).list(period),
  );
  Future<Map<String, Object?>> raw(String id) => io(() async {
    final rows = await (await session.store.open())
        .customSelect('SELECT * FROM budgets')
        .get();
    return rows.singleWhere((r) => r.data['id'] == id).data;
  });
  Future<void> trigger(String event) => io(() async {
    await (await session.store.open()).customStatement(
      'CREATE TEMP TRIGGER reject_budget BEFORE $event ON budgets '
      "BEGIN SELECT RAISE(ABORT,'synthetic-105'); END",
    );
  });
  Future<void> unblock() => io(() async {
    await (await session.store.open()).customStatement(
      'DROP TRIGGER reject_budget',
    );
  });
  Future<void> mount() async {
    expect(await io(session.open), isTrue);
    await tester.pumpWidget(AutofinanceApp(localSession: session));
    await month(1);
  }

  Future<void> reopen() async {
    debugPrint('EP-011 reapertura: comparar, cerrar y abrir SQLite');
    final before = await snapshot();
    await tester.pumpWidget(const SizedBox.shrink());
    await io(session.store.close);
    session.controller.dispose();
    await io(session.categoryInvalidation.close);
    session = LocalBackupSession(supportDirectory: () async => directory);
    await mount();
    expect(await snapshot(), before);
    debugPrint('EP-011 reapertura: estado idéntico');
  }

  Future<void> editRow(String id, String current, String amount) async {
    await tap(row(id, desktop ? current : 'Abrir alta'));
    await enter(desktop ? 'budget-cell-input' : 'budget-form-amount', amount);
  }

  Future<void> confirm() =>
      press(desktop ? 'Confirmar celda' : 'Guardar partida');
  Future<void> discard() async {
    await press('Cancelar');
    await press('Seguir editando');
    await press('Cancelar');
    await press('Descartar cambios');
  }

  Future<void> pick(String path) async {
    await press('Seleccionar categoría');
    await tester.scrollUntilVisible(
      find.text(path),
      250,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await press(path);
    await tap(find.widgetWithText(FilledButton, 'Seleccionar'));
  }

  void preserved(Map<String, Object?> after, Map<String, Object?> before) {
    expect(
      {...after}
        ..remove('month')
        ..remove('category_id')
        ..remove('amount_cents')
        ..remove('updated_at'),
      {...before}
        ..remove('month')
        ..remove('category_id')
        ..remove('amount_cents')
        ..remove('updated_at'),
    );
  }

  late CategoryDetails income,
      salary,
      payroll,
      taxes,
      duplicate,
      expenses,
      housing,
      rent,
      light,
      food,
      market,
      leaf;
  late BudgetRecord historical;
  try {
    await io(() async {
      final categories = await session.categories();
      income = await categories.create(name: 'INGRESOS', isIncome: true);
      salary = await categories.create(
        name: 'Salario',
        parentId: income.node.id,
      );
      payroll = await categories.create(
        name: 'NÓMINA',
        parentId: salary.node.id,
      );
      taxes = await categories.create(
        name: 'IMPUESTOS',
        parentId: salary.node.id,
      );
      duplicate = await categories.create(
        name: 'IMPUESTOS',
        parentId: salary.node.id,
      );
      expenses = await categories.create(name: 'GASTOS', isIncome: false);
      housing = await categories.create(
        name: 'Vivienda',
        parentId: expenses.node.id,
      );
      rent = await categories.create(
        name: 'Alquiler',
        parentId: housing.node.id,
      );
      light = await categories.create(name: 'Luz', parentId: housing.node.id);
      // Alimentación como raíz: raíz/intermedio/hoja, nunca un cuarto nivel.
      food = await categories.create(name: 'Alimentación', isIncome: false);
      market = await categories.create(
        name: 'Supermercado',
        parentId: food.node.id,
      );
      leaf = await categories.create(
        name: 'Compra semanal',
        parentId: market.node.id,
      );
      final db = await session.store.open();
      final repo = SqliteBudgetRepository(db);
      for (final period in [january, february]) {
        await repo.create(
          BudgetInput(
            month: period,
            categoryId: payroll.node.id,
            amountCents: 300000,
          ),
        );
        await repo.create(
          BudgetInput(
            month: period,
            categoryId: taxes.node.id,
            amountCents: -60000,
          ),
        );
      }
      await repo.create(
        BudgetInput(
          month: february,
          categoryId: housing.node.id,
          amountCents: -100000,
        ),
      );
      await SqliteImportBatchRepository(db).create(
        sha256: 'b' * 64,
        source: ImportSource.historicalCsv,
        originalName: 'synthetic-105.csv',
        contractVersion: '1',
        budgets: [
          ImportedBudget(
            7,
            BudgetInput.fromHistoricalCsv(
              month: january,
              categoryId: food.node.id,
              csvAmountCents: 40000,
              concept: 'Presupuesto histórico',
              discretion: 'Necesario',
            ),
          ),
        ],
      );
      historical = (await repo.list(january))
          .singleWhere((r) => r.data.categoryId == food.node.id);
    });
    var protected = await snapshot(protectedOnly: true);
    await mount();
    for (final category in [
      income,
      salary,
      payroll,
      taxes,
      duplicate,
      expenses,
      housing,
      rent,
      light,
      food,
      market,
      leaf,
    ]) {
      expect(find.byKey(ValueKey(category.node.id)), findsOneWidget);
    }
    expect(find.text('Total mensual: +2.000,00 €'), findsOneWidget);
    expect(historical.data.amountCents, -40000);

    debugPrint('EP-011 W1/L3/R2: alta cero, fallo, reintento y reapertura');
    await trigger('INSERT');
    var before = await snapshot();
    await editRow(rent.node.id, 'Sin presupuesto', '0');
    await confirm();
    expect(await snapshot(), before);
    expect(value(desktop ? 'budget-cell-input' : 'budget-form-amount'), '0');
    await unblock();
    final rev = await revision();
    await press('Reintentar');
    expect(await revision(), rev + 1);
    var created = (await records(january))
        .singleWhere((r) => r.data.categoryId == rent.node.id);
    expect(created.data.amountCents, 0);
    await reopen();
    expect(row(rent.node.id, '0,00 € (registrado)'), findsOneWidget);

    debugPrint('EP-011 R1/R6: editar, rollback, reintento y no-op');
    if (desktop) {
      await tap(row(rent.node.id, '0,00 € (registrado)'));
    } else {
      await tap(row(rent.node.id, 'Abrir detalle'));
      await press('Editar');
    }
    final amountKey = desktop ? 'budget-cell-input' : 'budget-form-amount';
    await enter(amountKey, '-900');
    await trigger('UPDATE');
    before = await snapshot();
    await confirm();
    expect(await snapshot(), before);
    expect(value(amountKey), '-900');
    await unblock();
    final editRev = await revision();
    await press('Reintentar');
    expect(await revision(), editRev + 1);
    await reopen();
    expect(row(rent.node.id, '−900,00 €'), findsOneWidget);
    before = await snapshot();
    if (desktop) {
      await tap(row(rent.node.id, '−900,00 €'));
    } else {
      await tap(row(rent.node.id, 'Abrir detalle'));
      await press('Editar');
    }
    await confirm();
    expect(await snapshot(), before);

    debugPrint('EP-011 W2/W3/W6: conflictos en ambos sentidos');
    await month(1);
    before = await snapshot();
    await editRow(housing.node.id, 'Sin presupuesto', '-1000');
    await confirm();
    expect(
      find.textContaining(
        '2026-01: GASTOS / Vivienda ↔ GASTOS / Vivienda / Alquiler',
      ),
      findsOneWidget,
    );
    expect(await snapshot(), before);
    expect(value(amountKey), '-1000');
    await discard();
    await month(2);
    before = await snapshot();
    await editRow(rent.node.id, 'Sin presupuesto', '-950');
    await confirm();
    expect(
      find.textContaining(
        '2026-02: GASTOS / Vivienda / Alquiler ↔ GASTOS / Vivienda',
      ),
      findsOneWidget,
    );
    expect(await snapshot(), before);
    expect(value(amountKey), '-950');
    await discard();

    debugPrint('EP-011 W5/W7: detalle, cancelación y cambio mes/categoría');
    await month(1);
    await tap(row(rent.node.id, 'Abrir detalle'));
    await press('Editar');
    await enter('budget-period', '2026-02');
    await enter('budget-form-amount', '-950');
    before = await snapshot();
    await press('Guardar partida');
    expect(await snapshot(), before);
    expect(value('budget-period'), '2026-02');
    await pick(light.path);
    await enter('budget-period', '2026-03');
    final original = await raw(created.id);
    await press('Reintentar');
    final moved = await raw(created.id);
    expect(moved['month'], '2026-03-01');
    expect(moved['category_id'], light.node.id);
    expect(moved['amount_cents'], -95000);
    preserved(moved, original);
    await press('Ver mes');
    expect(row(light.node.id, '−950,00 €'), findsOneWidget);
    expect(row(rent.node.id, 'Sin presupuesto'), findsOneWidget);

    debugPrint('EP-011 H1/H3: histórico archivado, signo y metadatos');
    await io(() async => (await session.categories()).archive(food.node.id));
    protected = await snapshot(protectedOnly: true);
    await month(1);
    expect(
      find.text('Histórico archivado · incluido en el total'),
      findsOneWidget,
    );
    await tap(row(food.node.id, 'Abrir detalle'));
    expect(find.textContaining('Presupuesto histórico'), findsOneWidget);
    await press('Editar');
    before = await snapshot();
    await press('Guardar partida');
    expect(await snapshot(), before); // No segunda inversión del signo CSV.
    await open(historical.id);
    await press('Editar');
    final historicalBefore = await raw(historical.id);
    await enter('budget-period', '2026-04');
    await enter('budget-form-amount', '0');
    await press('Seleccionar categoría');
    expect(find.text(food.path), findsNothing);
    expect(find.text(market.path), findsNothing);
    await press('Cancelar');
    await press('Guardar partida');
    final historicalAfter = await raw(historical.id);
    preserved(historicalAfter, historicalBefore);
    expect(historicalAfter['category_id'], food.node.id);
    expect(historicalAfter['month'], '2026-04-01');
    expect(historicalAfter['amount_cents'], 0);
    expect(historicalAfter['import_row_id'], isNotNull);

    debugPrint('EP-011 W8/R3/R5: cancelar borrado, fallo y reconfirmación');
    await open(historical.id, origin: 4);
    before = await snapshot();
    await press('Eliminar partida');
    await press('Cancelar');
    expect(await snapshot(), before);
    await trigger('DELETE');
    await press('Eliminar partida');
    await tap(find.widgetWithText(FilledButton, 'Eliminar partida'));
    expect(await snapshot(), before);
    expect(find.textContaining('No se pudo completar'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
    await unblock();
    final deleteRev = await revision();
    await press('Eliminar partida');
    expect(find.byType(AlertDialog), findsOneWidget);
    await tap(find.widgetWithText(FilledButton, 'Eliminar partida'));
    expect(await revision(), deleteRev + 1);
    expect((await records(BudgetMonth(2026, 4))), isEmpty);
    expect(await snapshot(protectedOnly: true), protected);
    await reopen();
    expect((await records(BudgetMonth(2026, 3))).single.id, created.id);
    expect(await snapshot(protectedOnly: true), protected);
    debugPrint('EP-011 recorrido completo correcto');
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await io(session.store.close);
    session.controller.dispose();
    await io(session.categoryInvalidation.close);
  }
}
