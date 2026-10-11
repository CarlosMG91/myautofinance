import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/budget/presentation/budget_list_screen.dart';
import 'package:myautofinance/features/budget/presentation/budget_ui.dart';
import 'package:myautofinance/features/monthly_status/monthly_status.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_controller.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_screen.dart';
import 'package:myautofinance/features/movements/presentation/category_selector.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import 'recovery_reference.dart';

/// Mismo recorrido sobre archivos privados sintéticos en widgets y dispositivos.
/// Usa sesión/composición SQLite, formularios, enlaces y restaurador de producto.
Future<void> monthlyStatusJourney(
  WidgetTester tester,
  Directory directory,
) async {
  final local = LocalBackupSession(supportDirectory: () async => directory);
  final session = NavigationSession(
    initialContext: NavigationContext(
      destination: SessionDestination.status,
      period: NavigationPeriod(2026, 1),
    ),
  );
  Future<T> io<T>(Future<T> Function() action) async =>
      (await tester.runAsync(() async {
        var done = false;
        late T result;
        Object? failure;
        StackTrace? trace;
        final work = action().then<void>(
          (value) {
            result = value;
            done = true;
          },
          onError: (Object error, StackTrace stack) {
            failure = error;
            trace = stack;
            done = true;
          },
        );
        // La invalidación puede iniciar una lectura desde la zona de widgets.
        // Mantener frames/timers en marcha mientras la operación real espera.
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!done && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        if (!done) fail('La operación SQLite integrada no terminó en 30 s.');
        await work;
        if (failure != null) Error.throwWithStackTrace(failure!, trace!);
        return result;
      })) as T;

  // Espera a trabajo SQLite real además de frames, sin sleeps de duración fija.
  Future<void> settle({bool allowPending = false, Finder? until}) async {
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 50));
      if (i >= 5 &&
          (until == null || until.evaluate().isNotEmpty) &&
          (allowPending ||
              (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
                  find.byType(CircularProgressIndicator).evaluate().isEmpty &&
                  find
                      .text('Consultando el estado del mes…')
                      .evaluate()
                      .isEmpty))) {
        if (!allowPending) await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return;
      }
    }
    fail('Estado o su fuente no terminó de leer SQLite.');
  }

  Future<void> tap(Finder finder, {bool allowPending = false}) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(finder));
    await settle(allowPending: allowPending);
  }

  Future<void> press(String label) async {
    debugPrint('MA-TSK-164 pulsar: $label');
    await tap(find.text(label).last);
  }

  Finder key(String token) => find.byKey(ValueKey(token));
  Future<void> back() async {
    // La misma acción de navegación Back que recibe la app nativa.
    await tester.binding.handlePopRoute();
    await settle();
    expect(find.text('Estado del mes'), findsOneWidget);
  }

  MovementListController list() => tester
      .widget<MovementListScreen>(find.byType(MovementListScreen))
      .controller;
  Future<MonthlyStatus> status() => io(() async {
    final query = await local.monthlyStatus();
    return query.read(BudgetMonth(session.period.year, session.period.month));
  });
  MonthlyStatusRow row(MonthlyStatus data, String id) =>
      data.rows.singleWhere((r) => r.categoryId == id);
  Future<void> total(int planned, int actual, int difference) async {
    final data = await status();
    expect(data.total.plannedCents, planned);
    expect(data.total.actualCents, actual);
    expect(data.total.differenceCents, difference);
    // Comprobar también las cifras presentadas, no solo la consulta.
    expect(find.text(budgetTotal(BigInt.from(planned))), findsWidgets);
    expect(find.text(budgetTotal(BigInt.from(actual))), findsWidgets);
    expect(
      find.textContaining(budgetTotal(BigInt.from(difference))),
      findsWidgets,
    );
  }

  Future<List<Map<String, Object?>>> photos() => io(() async {
    final db = await local.store.open();
    return [
      for (final table in ['wealth_snapshots', 'wealth_values'])
        for (final r
            in await db
                .customSelect('SELECT * FROM $table ORDER BY rowid')
                .get())
          {'table': table, ...r.data},
    ];
  });

  Completer<MonthlyStatusQuery>? pending;
  var failRead = false;
  Future<MonthlyStatusQuery> load() async {
    if (failRead) throw StateError('Fallo de lectura sintético MA-TSK-164');
    if (pending != null) return pending.future;
    return local.monthlyStatus();
  }

  try {
    debugPrint('MA-TSK-164: abrir y preparar SQLite sintético');
    expect(await io(local.open), isTrue);
    final db = await io(local.store.open);
    final account = await io(() => seedRecoveryReference(db));
    final protectedPhotos = await photos();
    final categories = await io(local.categories);
    final ids = {for (final c in await io(categories.list)) c.path: c.node.id};
    final root = ids['Alimentación']!;
    final child = ids['Alimentación / Supermercado']!;
    final leaf = ids['Alimentación / Supermercado / Compra semanal']!;
    final ocio = ids['Ocio']!;
    debugPrint('MA-TSK-164: montar Estado y comprobar referencias');
    await tester.pumpWidget(
      AutofinanceApp(
        navigationSession: session,
        monthlyStatus: load,
        categories: local.categories,
        wealth: local.wealth,
        budgets: local.budgets,
        movements: local.movements,
        localBackups: local.controller,
      ),
    );
    await settle();
    await total(110000, 122975, 12975);
    expect(key('$child:real'), findsNothing);
    await tap(key('$root:expandir'));
    await tap(key('$child:expandir'));
    expect(key('$leaf:directo'), findsOneWidget);

    final jan = await status();
    expect(row(jan, root).totals.plannedCents, -40000);
    expect(row(jan, root).totals.actualCents, -35025);
    expect(row(jan, root).totals.differenceCents, 4975);
    expect(row(jan, ocio).totals.hasBudget, isFalse);
    final allReal = await io(
      () => SqliteMovementRepository(db).readMonth(2026, 1),
    );
    final allBudgets = await io(
      () => SqliteBudgetRepository(db).list(BudgetMonth(2026, 1)),
    );
    final parents = {for (final c in jan.tree) c.node.id: c.node.parentId};
    bool inBranch(String? id, String? branch) {
      if (branch == null) return true;
      while (id != null) {
        if (id == branch) return true;
        id = parents[id];
      }
      return false;
    }

    Future<void> checkReal(
      String token,
      String? id, {
      bool direct = false,
    }) async {
      final expected = allReal
          .where(
            (r) => direct
                ? r.data.categoryId == id
                : inBranch(r.data.categoryId, id),
          )
          .toList();
      final cents = expected.fold<int>(0, (sum, r) => sum + r.data.amountCents);
      expect(
        find.descendant(
          of: key('$token:${direct ? 'directo' : 'real'}'),
          matching: find.text(budgetTotal(BigInt.from(cents))),
        ),
        findsOneWidget,
      );
      await tap(key('$token:${direct ? 'directo' : 'real'}'));
      final c = list();
      expect(c.error, isNull);
      expect(c.from.value, '2026-01-01');
      expect(c.until!.value, '2026-02-01');
      expect(c.accountId, isNull);
      expect(c.categoryId, id);
      expect(
        c.scope,
        direct ? MovementCategoryScope.direct : MovementCategoryScope.branch,
      );
      expect(
        c.page!.records.map((r) => r.id),
        unorderedEquals(expected.map((r) => r.id)),
      );
      expect(
        c.page!.subtotalCents,
        expected.fold<int>(0, (sum, r) => sum + r.data.amountCents),
      );
      if (id == ocio) {
        expect(c.page!.records, hasLength(2));
        expect(c.page!.records.map((r) => r.id).toSet(), hasLength(2));
        expect(find.textContaining('Café'), findsWidgets);
      }
      final offset = session.context.scrollOffset;
      final expanded = session.context.filters['abiertas'];
      await back();
      expect(session.period, NavigationPeriod(2026, 1));
      expect(session.context.filters['abiertas'], expanded);
      expect(session.context.scrollOffset, closeTo(offset, 1));
      expect(
        FocusManager.instance.primaryFocus,
        same(
          tester
              .widget<TextButton>(key('$token:${direct ? 'directo' : 'real'}'))
              .focusNode,
        ),
      );
    }

    Future<void> checkBudget(String token, String? id) async {
      final expected = allBudgets
          .where((r) => inBranch(r.data.categoryId, id))
          .toList();
      final cents = expected.fold<int>(0, (sum, r) => sum + r.data.amountCents);
      expect(
        find.descendant(
          of: key('$token:previsto'),
          matching: find.text(
            expected.isEmpty
                ? 'Sin presupuesto'
                : budgetTotal(BigInt.from(cents)),
          ),
        ),
        findsOneWidget,
      );
      await tap(key('$token:previsto'));
      final screen = tester.widget<BudgetListScreen>(
        find.byType(BudgetListScreen),
      );
      expect(screen.query.month.value, '2026-01-01');
      expect(screen.query.categoryId, id);
      for (final record in expected) {
        expect(find.text(record.id), findsOneWidget);
      }
      expect(find.text('Abrir'), findsNWidgets(expected.length));
      if (expected.isEmpty) {
        expect(
          find.text('Sin presupuesto · No hay partidas en este alcance.'),
          findsOneWidget,
        );
      }
      await back();
    }

    // Abrir TODAS las filas presentes, incluidos los antecesores sin directos.
    for (final r in jan.rows) {
      debugPrint('MA-TSK-164 fuentes: ${r.category.path}');
      final expand = key('${r.categoryId}:expandir');
      if (expand.evaluate().isNotEmpty &&
          !(session.context.filters['abiertas'] ?? '').contains(r.categoryId)) {
        await tap(expand);
      }
      await checkReal(r.categoryId, r.categoryId, direct: true);
      await checkReal(r.categoryId, r.categoryId);
      await checkBudget(r.categoryId, r.categoryId);
      expect(
        find.descendant(
          of: key('${r.categoryId}:diferencia'),
          matching: find.textContaining(
            budgetTotal(BigInt.from(r.totals.differenceCents)),
          ),
        ),
        findsOneWidget,
      );
      await tap(key('${r.categoryId}:diferencia'));
      await press('Ver movimientos reales');
      expect(list().page!.subtotalCents, r.totals.actualCents);
      await back();
      await tap(key('${r.categoryId}:diferencia'));
      await press('Ver partidas previstas');
      expect(find.text('Abrir'), findsNWidgets(r.totals.budgetCount));
      await back();
    }
    await checkReal('total', null);
    await checkBudget('total', null);
    await tap(key('total:diferencia'));
    await press('Ver movimientos reales');
    expect(
      list().page!.records.map((r) => r.id),
      unorderedEquals(allReal.map((r) => r.id)),
    );
    expect(list().page!.subtotalCents, 122975);
    await back();
    await tap(key('total:diferencia'));
    await press('Ver partidas previstas');
    expect(find.text('Abrir'), findsNWidgets(4));
    await back();
    expect((await io(db.readState)).revision, jan.datasetState.revision);
    expect(await photos(), protectedPhotos);

    await press('Mes siguiente');
    await total(110000, 109990, -10);
    final feb = await status();
    expect(row(feb, root).totals.actualCents, -42010);
    expect(row(feb, root).totals.differenceCents, -2010);
    expect(
      (await io(() => SqliteWealthRepository(db).read(Month(2026, 2)))).status,
      WealthSnapshotStatus.absent,
    );
    await tap(key('$root:real'));
    expect(list().page!.subtotalCents, -42010);
    expect(list().from.value, '2026-02-01');
    await back();
    expect(session.period, NavigationPeriod(2026, 2));
    await press('Mes anterior');

    // Alta, edición/categorización y borrado mediante formularios entregados.
    debugPrint('MA-TSK-164: periodo y formularios');
    await tap(key('status-add'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Concepto'),
      'Alta integrada sintética',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Importe firmado (EUR)'),
      '-12,00',
    );
    await tap(find.byType(DropdownButtonFormField<String>));
    await tap(find.textContaining('Cuenta principal ·').last);
    await press('Guardar movimiento');
    await settle(until: find.text('Estado del mes'));
    await total(110000, 121775, 11775);
    await tap(key('sin-clasificar:previsto'));
    expect(
      find.text('Sin presupuesto · No hay partidas en este alcance.'),
      findsOneWidget,
    );
    await back();
    await tap(key('sin-clasificar:diferencia'));
    await press('Ver partidas previstas');
    expect(find.text('Abrir'), findsNothing);
    await back();
    await tap(key('sin-clasificar:real'));
    expect(list().unclassified, isTrue);
    expect(list().page!.subtotalCents, -1200);
    final addedId = list().page!.records.single.id;
    await press('Abrir Alta integrada sintética');
    await press('Editar');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Importe firmado (EUR)'),
      '-13,00',
    );
    await press('Seleccionar categoría');
    await settle(until: find.byType(CategorySelector));
    await tester.scrollUntilVisible(
      find.text('Alimentación / Supermercado / Compra semanal'),
      200,
      scrollable: find.descendant(
        of: find.byType(CategorySelector),
        matching: find.byType(Scrollable),
      ),
    );
    await press('Alimentación / Supermercado / Compra semanal');
    await press('Seleccionar');
    await press('Guardar movimiento');
    await settle(until: find.byType(MovementListScreen));
    expect(list().page!.records, isEmpty);
    await back();
    await total(110000, 121675, 11675);
    expect((await status()).unclassified.movementCount, 0);
    expect(row(await status(), leaf).actualDirectCents, -36325);
    await tap(key('$root:previsto'));
    await press('Abrir');
    await press('Editar');
    await tester.enterText(
      find.byKey(const Key('budget-form-amount')),
      '-450,00',
    );
    await press('Guardar partida');
    await settle(until: find.byType(BudgetListScreen));
    await back();
    await total(105000, 121675, 16675);
    await tap(key('$root:real'));
    expect(list().page!.records.map((r) => r.id), contains(addedId));
    await press('Abrir Alta integrada sintética');
    await press('Borrar movimiento');
    await press('Confirmar borrado');
    await settle(until: find.byType(MovementListScreen));
    expect(list().page!.subtotalCents, -35025);
    expect(list().page!.records.map((r) => r.id), isNot(contains(addedId)));
    await back();
    await total(105000, 122975, 17975);
    expect(await photos(), protectedPhotos);

    // Backup real antes de variantes independientes; restauración reconecta app.
    debugPrint('MA-TSK-164: variantes, archivo, traslado y restauración');
    await io(local.controller.create);
    debugPrint('MA-TSK-164: copia local creada');
    expect(local.controller.error, isNull);
    final backup = local.controller.listing!.entries.single.backupId;
    final zero = (await io(
      () => categories.create(name: 'Cero sintético', isIncome: false),
    )).node.id;
    await io(
      () => SqliteBudgetRepository(db).create(
        BudgetInput(
          month: BudgetMonth(2026, 1),
          categoryId: zero,
          amountCents: 0,
        ),
      ),
    );
    final savings = (await io(() => SqliteAccountRepository(db).list()))
        .singleWhere((a) => a.name == 'Cuenta de ahorro')
        .id;
    for (final cents in [-125, 125]) {
      await io(
        () => SqliteMovementRepository(db).create(
          MovementInput(
            accountId: cents < 0 ? account : savings,
            valueDate: ValueDate(2026, 1, 12),
            concept: 'Neto cero sintético',
            amountCents: cents,
            categoryId: zero,
          ),
        ),
      );
    }
    await tap(key('status-refresh'));
    debugPrint('MA-TSK-164: cero explícito y neto cero preparados');
    expect(find.text('0,00 € (registrado)'), findsOneWidget);
    await tap(key('$zero:real'));
    expect(list().page!.records, hasLength(2));
    expect(list().page!.records.map((r) => r.data.accountId).toSet(), {
      account,
      savings,
    });
    expect(list().page!.subtotalCents, 0);
    await back();
    // Partida padre no repartida a un hijo con datos y sin partida propia.
    final parent = (await io(
      () => categories.create(name: 'Padre sintético', isIncome: false),
    )).node.id;
    await io(
      () => SqliteBudgetRepository(db).create(
        BudgetInput(
          month: BudgetMonth(2026, 1),
          categoryId: parent,
          amountCents: -900,
        ),
      ),
    );
    final noBudgetChild = (await io(
      () => categories.create(name: 'Hijo sin partida', parentId: parent),
    )).node.id;
    await io(
      () => SqliteMovementRepository(db).create(
        MovementInput(
          accountId: account,
          valueDate: ValueDate(2026, 1, 12),
          concept: 'Directo hijo sintético',
          amountCents: -125,
          categoryId: noBudgetChild,
        ),
      ),
    );
    // Las escrituras de preparación por repositorio no simulan un retorno UI.
    // Solicitar la relectura explícita después de terminar el fixture.
    await tap(key('status-refresh'));
    await tap(key('$parent:expandir'));
    expect(row(await status(), noBudgetChild).totals.hasBudget, isFalse);
    await tap(key('$noBudgetChild:previsto'));
    expect(find.text('Abrir'), findsNothing);
    await back();
    await tap(key('$parent:previsto'));
    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text('−9,00 €'), findsWidgets);
    await back();
    final relocated = (await io(
      () => categories.create(name: 'Destino sintético', isIncome: false),
    )).node.id;
    await io(() => categories.move(child, parentId: relocated));
    await settle();
    await tap(key('$relocated:expandir'));
    final moved = await status();
    expect(row(moved, child).category.path, 'Destino sintético / Supermercado');
    expect(row(moved, child).totals.plannedCents, -45000);
    expect(row(moved, relocated).totals.actualCents, -35025);
    await io(() => categories.archive(child));
    await settle();
    expect(find.textContaining('Supermercado · Archivada'), findsOneWidget);
    await tap(key('$relocated:real'));
    expect(
      list().paths[leaf],
      'Destino sintético / Supermercado / Compra semanal',
    );
    expect(list().page!.subtotalCents, -35025);
    await back();
    await io(() => local.controller.restore(backup, confirmed: true));
    debugPrint('MA-TSK-164: restauración local terminada');
    expect(local.controller.error, isNull);
    expect(local.controller.restoreResult!.status, LocalRestoreStatus.restored);
    expect(local.controller.restoreResult!.previousBackupId, isNotNull);
    await settle();
    await total(105000, 122975, 17975);
    final restored = await status();
    expect(
      row(restored, leaf).category.path,
      'Alimentación / Supermercado / Compra semanal',
    );
    expect(row(restored, leaf).category.node.archived, isFalse);
    expect(restored.rows.map((r) => r.categoryId), isNot(contains(parent)));
    expect(find.textContaining('Padre sintético'), findsNothing);
    await tap(key('$root:real'));
    expect(list().paths[leaf], 'Alimentación / Supermercado / Compra semanal');
    expect(list().page!.subtotalCents, -35025);
    await back();
    expect(await photos(), protectedPhotos);

    // Carga retenida, periodo posterior y error nunca aparentan un cero válido.
    debugPrint('MA-TSK-164: lectura tardía, error y vacío');
    pending = Completer<MonthlyStatusQuery>();
    await tap(key('status-refresh'), allowPending: true);
    expect(find.text('Consultando el estado del mes…'), findsOneWidget);
    expect(key('total:real'), findsNothing);
    final held = pending;
    pending = null;
    await press('Mes siguiente');
    await total(110000, 109990, -10);
    held.complete(await io(local.monthlyStatus));
    await settle();
    await total(110000, 109990, -10);
    failRead = true;
    await tap(key('status-refresh'));
    expect(
      find.text('No se pudo consultar el estado del mes. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(key('total:real'), findsNothing);
    expect(
      find.text('No hay movimientos en este mes. Real: 0,00 €.'),
      findsNothing,
    );
    failRead = false;
    await press('Reintentar');
    await total(110000, 109990, -10);
    await io(() => session.selectPeriod(NavigationPeriod(2027, 1)));
    await settle();
    expect(
      find.text('No hay movimientos en este mes. Real: 0,00 €.'),
      findsOneWidget,
    );
    expect(find.textContaining('Sin presupuesto en este mes.'), findsOneWidget);
    await total(0, 0, 0);
    expect(await photos(), protectedPhotos);
  } finally {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    local.controller.dispose();
    await io(local.categoryInvalidation.close);
    await io(local.store.close);
  }
}
