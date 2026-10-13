import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/data/historical_csv_reader.dart';
import 'package:myautofinance/features/importing/historical_csv.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/synchronization/domain/local_restore.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import 'budget_proposal_reference_csv.dart';

/// Misma app, consulta, EP-011/016/018 y recuperación local en host y nativo.
/// Solo recibe una carpeta sintética desechable; nunca abre la instalación real.
Future<void> annualBudgetLifecycleJourney(
  WidgetTester tester,
  Directory directory, {
  required bool desktop,
}) async {
  var local = LocalBackupSession(supportDirectory: () async => directory);
  final navigation = NavigationSession(
    initialContext: NavigationContext(
      destination: SessionDestination.budget,
      period: NavigationPeriod(2026, 1),
    ),
  );
  Future<T> io<T>(Future<T> Function() action) async {
    Object? error;
    StackTrace? trace;
    final value = await tester.runAsync(() async {
      T? result;
      var finished = false;
      Future<void> perform() async {
        try {
          result = await action().timeout(const Duration(seconds: 45));
        } catch (caught, stack) {
          error = caught;
          trace = stack;
        } finally {
          finished = true;
        }
      }

      final operation = perform();
      // Una lectura de la ruta anterior puede seguir cerrando su transacción.
      // Avanzar también sus callbacks de Flutter mientras se espera SQLite;
      // no bloquear el reloj del test con una segunda lectura encolada.
      while (!finished) {
        await tester.pump(const Duration(milliseconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await operation;
      return result;
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
      if (turn >= 6 &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.textContaining('Cargando').evaluate().isEmpty &&
          find.textContaining('Calculando o comprobando').evaluate().isEmpty &&
          find.textContaining('Guardando…').evaluate().isEmpty &&
          find.textContaining('Leyendo').evaluate().isEmpty) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return;
      }
    }
    fail('La operación anual no terminó.');
  }

  Future<void> tap(Finder finder) async {
    await settle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(finder));
    await settle();
  }

  Future<void> press(String label) => tap(find.text(label).last);
  Future<void> enter(String key, String text) async {
    final field = find.byKey(Key(key));
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tester.pump();
  }

  Future<void> route(String name) async {
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .pushNamedAndRemoveUntil(name, (_) => false);
    await settle();
  }

  Future<void> annual(int year) async {
    await route('/presupuesto?a=$year&m=01');
    await tap(find.byKey(const Key('budget-show-detail')));
  }

  Future<LocalDatabase> db() => local.store.open();
  Future<List<BudgetRecord>> records(int year) =>
      io(() async => SqliteBudgetRepository(await db()).readYear(year));
  Future<Map<String, Object?>> snapshot({bool protectedOnly = false}) =>
      io(() async {
        final database = await db();
        return {
          for (final table in [
            'categories',
            'accounts',
            'account_liquidity_periods',
            'movements',
            'wealth_snapshots',
            'wealth_values',
            'import_batches',
            'import_rows',
            if (!protectedOnly) ...['budgets', 'database_state'],
          ])
            table:
                (await database
                        .customSelect('SELECT * FROM $table ORDER BY 1')
                        .get())
                    .map((r) => r.data)
                    .toList(),
        };
      });
  Future<Map<String, Object?>> raw(String id) => io(
    () async => (await (await db()).customSelect('SELECT * FROM budgets').get())
        .singleWhere((r) => r.data['id'] == id)
        .data,
  );
  Future<void> trigger(String event) => io(
    () async => (await db()).customStatement(
      'CREATE TEMP TRIGGER reject_annual BEFORE $event ON budgets '
      "BEGIN SELECT RAISE(ABORT,'synthetic-172'); END",
    ),
  );
  Future<void> unblock() => io(
    () async => (await db()).customStatement('DROP TRIGGER reject_annual'),
  );
  Future<AnnualBudget> projection(int year) =>
      io(() async => (await local.budgets()).annual!.read(year));
  Future<void> total(int cents, int count, {int year = 2026}) async {
    await settle();
    if (find.byKey(const Key('budget-show-detail')).evaluate().isNotEmpty) {
      await tap(find.byKey(const Key('budget-show-detail')));
    }
    final data = await projection(year);
    expect(data.annualTotal.amountCents, cents);
    expect(data.annualTotal.budgetCount, count);
    final summary = find.descendant(
      of: find.byKey(const ValueKey('summary-year')),
      matching: find.byType(Text),
    );
    expect(summary, findsOneWidget);
    // Verificar el valor presentado, además de la consulta y su presencia.
    final euros = (cents.abs() / 100).toStringAsFixed(2).split('.');
    final grouped = euros.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    final sign = cents < 0
        ? '−'
        : cents > 0
        ? '+'
        : '';
    expect(
      tester.widget<Text>(summary).data,
      '${count == 0 ? 'Sin presupuesto' : '$sign$grouped,${euros.last} €'}\n$count ${count == 1 ? 'partida' : 'partidas'} · Ver origen',
    );
  }

  Future<void> mount() async {
    expect(await io(local.open), isTrue);
    await tester.pumpWidget(
      AutofinanceApp(localSession: local, navigationSession: navigation),
    );
    await settle();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await io(local.store.close);
    local.controller.dispose();
    await io(local.categoryInvalidation.close);
  }

  Future<void> reopen() async {
    final before = await snapshot();
    await close();
    local = LocalBackupSession(supportDirectory: () async => directory);
    await mount();
    expect(await snapshot(), before);
  }

  Future<void> expand(String id) async {
    if (!navigation.context.filters['abiertas']
        .toString()
        .split(',')
        .contains(id)) {
      await tap(find.byKey(ValueKey('expand-$id')));
    }
  }

  Future<void> cell(String id, int month) async {
    await settle();
    if (!desktop) {
      final months = find.byKey(ValueKey('annual-months-$id'));
      final tile = tester.widget<ExpansionTile>(months);
      // La sesión conserva expansión; no alternar accidentalmente al volver.
      if (!(navigation.context.filters['meses'] ?? '')
          .split(',')
          .contains(id)) {
        await tap(
          find.descendant(
            of: months,
            matching: find.text(
              tile.title is Text
                  ? (tile.title as Text).data!
                  : 'Los doce meses',
            ),
          ),
        );
      }
    }
    await tap(
      find.byKey(ValueKey('cell-$id:${month.toString().padLeft(2, '0')}')),
    );
  }

  final amountKey = desktop ? 'annual-cell-input' : 'budget-form-amount';
  Future<void> edit(
    String id,
    int month,
    String value, {
    bool existing = false,
  }) async {
    await cell(id, month);
    if (!desktop && existing) await press('Editar');
    await enter(amountKey, value);
  }

  Future<void> save() => desktop
      ? tap(find.byTooltip('Confirmar celda'))
      : press(
          find.text('Reintentar').evaluate().isEmpty
              ? 'Guardar partida'
              : 'Reintentar',
        );
  Future<void> discard() async {
    await (desktop
        ? tap(find.byTooltip('Cancelar edición'))
        : press('Cancelar'));
    if (find.text('Descartar cambios').evaluate().isNotEmpty) {
      await press('Descartar cambios');
    }
  }

  Future<void> form(String id, int month) async {
    await cell(id, month);
    if (desktop) await tap(find.byTooltip('Formulario / Eliminar partida'));
  }

  final nodes = <String, String>{};
  final importedBudgets = <ImportedBudget>[];
  final importedMovements = <ImportedMovement>[];
  final bytes = utf8.encode(budgetProposalReferenceCsv);
  Future<ImportBatch> importCsv() => io(
    () async => SqliteImportBatchRepository(await db()).create(
      sha256: sha256.convert(bytes).toString(),
      source: ImportSource.historicalCsv,
      originalName: 'historico-ejemplo.csv',
      contractVersion: '1',
      budgets: importedBudgets,
      movements: importedMovements,
    ),
  );
  try {
    await io(() async {
      final database = await db();
      final categories = await local.categories();
      final accounts = SqliteAccountRepository(database);
      final account = await accounts.create(
        name: 'Cuenta sintética',
        kind: AccountKind.account,
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      );
      final csv = const HistoricalCsvReader().read(bytes);
      expect(csv.isValid, isTrue);
      var ordinal = 1;
      for (final row in csv.records) {
        ordinal++;
        String? parent;
        for (var level = 0; level < row.categoryPath.length; level++) {
          final path = row.categoryPath.take(level + 1).join(' / ');
          parent = nodes[path] ??= (await categories.create(
            name: row.categoryPath[level],
            parentId: parent,
            isIncome: parent == null
                ? row.categoryPath.first == 'Ingresos'
                : null,
          )).node.id;
        }
        if (row.type == HistoricalCsvType.budget) {
          importedBudgets.add(
            ImportedBudget(
              ordinal,
              BudgetInput.fromHistoricalCsv(
                month: BudgetMonth.parse(row.date),
                categoryId: parent!,
                csvAmountCents: row.csvAmountCents,
                concept: row.concept,
                discretion: row.discretion,
              ),
            ),
          );
        } else {
          importedMovements.add(
            ImportedMovement(
              ordinal,
              MovementInput(
                accountId: account.id,
                valueDate: ValueDate.parse(row.date),
                categoryId: parent,
                amountCents: row.csvAmountCents,
                concept: row.concept,
                discretion: row.discretion,
              ),
            ),
          );
        }
      }
      await SqliteWealthRepository(database)
          .setValue(Month(2026, 1), account.id, 600000);
    });
    await importCsv();
    final protected = await snapshot(protectedOnly: true);
    final food = nodes['Alimentación']!;
    final market = nodes['Alimentación / Supermercado']!;
    final leaf = nodes['Alimentación / Supermercado / Compra semanal']!;
    final leisure = nodes['Ocio']!;
    final originalLeaf = (await records(2026)).singleWhere(
      (r) => r.data.categoryId == leaf && r.data.month.value == '2026-01-01',
    );
    final originalRaw = await raw(originalLeaf.id);
    await mount();

    debugPrint('EP-021 E: matriz real, doce meses y 48 UUID de origen');
    await tap(find.byKey(const Key('budget-show-detail')));
    await total(1320000, 48);
    final reference = await projection(2026);
    expect(reference.months.map((m) => m.amountCents), List.filled(12, 110000));
    for (final (name, cents) in [
      ('Ingresos', 3600000),
      ('Vivienda', -1200000),
      ('Alimentación', -480000),
      ('Ahorro', -600000),
    ]) {
      final row = reference.rows.singleWhere(
        (r) => r.categoryId == nodes[name],
      );
      expect(row.annualTotal.amountCents, cents);
      expect(
        row.months.map((m) => m.total.amountCents),
        List.filled(12, cents ~/ 12),
      );
    }
    for (var month = 1; month <= 12; month++) {
      final details = await io(
        () async => (await local.budgets()).entries!.read(
          BudgetListQuery(month: BudgetMonth(2026, month)),
        ),
      );
      expect(
        details.map((e) => e.record.id).toSet(),
        reference.months[month - 1].budgetIds.toSet(),
      );
      expect(
        details.fold<int>(0, (n, e) => n + e.record.data.amountCents),
        110000,
      );
    }
    await tap(find.byKey(const ValueKey('summary-year')));
    expect(find.text('Partidas del año'), findsOneWidget);
    expect(find.text('Total de partidas: +13.200,00 €'), findsOneWidget);
    await press('Volver al origen');
    await expand(food);
    await expand(market);
    await cell(food, 1);
    final origin = navigation.context;
    expect(find.text('Total de partidas: −400,00 €'), findsOneWidget);
    await press('Volver al origen');
    expect(navigation.context.filters, origin.filters);
    expect(navigation.period, origin.period);
    expect(navigation.context.scrollOffset, closeTo(origin.scrollOffset, 1));
    expect(navigation.context.focus, origin.focus);
    await total(1320000, 48);

    debugPrint(
      'EP-021 alta cero: fallo INSERT, borrador, reintento, reapertura',
    );
    await trigger('INSERT');
    var before = await snapshot();
    await edit(leisure, 1, '0');
    await save();
    expect(await snapshot(), before);
    expect(
      tester.widget<TextField>(find.byKey(Key(amountKey))).controller!.text,
      '0',
    );
    expect(find.text('Partida guardada'), findsNothing);
    await unblock();
    await save();
    await total(1320000, 49);
    await reopen();
    await total(1320000, 49);
    final zero = (await records(2026))
        .singleWhere((r) => r.data.categoryId == leisure);
    expect(zero.data.amountCents, 0);

    debugPrint('EP-021 corrección: rollback UPDATE y metadatos importados');
    await expand(food);
    await expand(market);
    await edit(leaf, 1, '-375,25', existing: true);
    await trigger('UPDATE');
    before = await snapshot();
    await save();
    expect(await snapshot(), before);
    expect(
      tester.widget<TextField>(find.byKey(Key(amountKey))).controller!.text,
      '-375,25',
    );
    await unblock();
    await save();
    await total(1322475, 49);
    final edited = await raw(originalLeaf.id);
    expect(
      {...edited}
        ..remove('amount_cents')
        ..remove('updated_at'),
      {...originalRaw}
        ..remove('amount_cents')
        ..remove('updated_at'),
    );
    expect(edited['concept'], 'Presupuesto compra');
    expect(edited['import_row_id'], isNotNull);
    expect((await projection(2026)).months[1].amountCents, 110000);

    debugPrint('EP-021 conflicto padre→hija y hija→padre sin sustitución');
    await cell(food, 1);
    await press('Crear partida');
    await enter('budget-form-amount', '-400');
    before = await snapshot();
    await press('Guardar partida');
    expect(await snapshot(), before);
    expect(
      find.textContaining(
        'Alimentación ↔ Alimentación / Supermercado / Compra semanal',
      ),
      findsWidgets,
    );
    await press('Cancelar');
    await press('Descartar cambios');
    await press('Volver al origen');
    // Otro año permite un padre en enero y una hija en febrero.
    await annual(2028);
    await edit(food, 1, '-10');
    await save();
    await expand(food);
    await expand(market);
    await edit(leaf, 1, '-5');
    before = await snapshot();
    await save();
    expect(await snapshot(), before);
    expect(find.textContaining('Compra semanal ↔ Alimentación'), findsWidgets);
    await discard();
    await edit(leaf, 2, '-5');
    await save();
    await total(-1500, 2, year: 2028);
    final differentLevels = await projection(2028);
    final leafRow = differentLevels.rows.singleWhere(
      (r) => r.categoryId == leaf,
    );
    expect(leafRow.months.first.total.hasBudget, isFalse);
    expect(leafRow.months[1].ownAmountCents, -500);

    debugPrint('EP-021 editar fuera del año conserva origen y cambia lectura');
    await annual(2026);
    await expand(food);
    await expand(market);
    await form(leaf, 1);
    await press('Editar');
    await enter('budget-period', '2027-04');
    await press('Guardar partida');
    expect(navigation.period, NavigationPeriod(2026, 1));
    await total(1360000, 48);
    expect((await raw(originalLeaf.id))['month'], '2027-04-01');
    await annual(2027);
    await total(-37525, 1, year: 2027);
    await annual(2026);
    await total(1360000, 48);

    debugPrint('EP-021 borrar: cancelación, rollback DELETE y confirmación');
    await annual(2027);
    await expand(food);
    await expand(market);
    await form(leaf, 4);
    before = await snapshot();
    await press('Eliminar partida');
    await press('Cancelar');
    expect(await snapshot(), before);
    await trigger('DELETE');
    await press('Eliminar partida');
    await tap(find.widgetWithText(FilledButton, 'Eliminar partida'));
    expect(await snapshot(), before);
    expect(find.textContaining('No se pudo completar'), findsOneWidget);
    await unblock();
    await press('Eliminar partida');
    await tap(find.widgetWithText(FilledButton, 'Eliminar partida'));
    await total(0, 0, year: 2027);
    before = await snapshot();
    var duplicateRejected = false;
    try {
      await importCsv();
    } on MovementFailure catch (failure) {
      expect(failure.message, 'El archivo ya fue importado.');
      duplicateRejected = true;
    }
    expect(duplicateRejected, isTrue);
    expect(await snapshot(), before);
    expect(await records(2027), isEmpty);
    await reopen();
    await total(0, 0, year: 2027);
    expect(await snapshot(protectedOnly: true), protected);

    debugPrint('EP-021 archivo/reubicación y cero neto conservan orígenes');
    await annual(2026);
    await io(() async => (await local.categories()).archive(leaf));
    await settle();
    await expand(food);
    await expand(market);
    final archived = (await projection(2026)).rows
        .singleWhere((r) => r.categoryId == leaf);
    expect(archived.category.node.archived, isTrue);
    expect(archived.annualTotal.budgetCount, 11);
    final newRoot = await io(
      () async => (await local.categories()).create(name: 'Reubicada'),
    );
    await io(
      () async =>
          (await local.categories()).move(leaf, parentId: newRoot.node.id),
    );
    await settle();
    await expand(newRoot.node.id);
    expect(
      desktop
          ? find.byTooltip('Reubicada / Compra semanal')
          : find.text('Reubicada / Compra semanal'),
      findsWidgets,
    );
    await total(1360000, 48);
    final left = await io(
      () async => (await local.categories()).create(name: 'Compensación'),
    );
    final a = await io(
      () async => (await local.categories()).create(
        name: 'Igual',
        parentId: left.node.id,
      ),
    );
    final b = await io(
      () async => (await local.categories()).create(
        name: 'Igual',
        parentId: left.node.id,
      ),
    );
    await io(() async {
      final management = (await local.budgets()).management;
      await management.create(
        month: BudgetMonth(2026, 1),
        categoryId: a.node.id,
        amountCents: -1234,
      );
      await management.create(
        month: BudgetMonth(2026, 1),
        categoryId: b.node.id,
        amountCents: 1234,
      );
    });
    await press('Actualizar año');
    final net = (await projection(2026)).rows
        .singleWhere((r) => r.categoryId == left.node.id);
    expect(net.months.first.total.hasBudget, isTrue);
    expect(net.months.first.total.amountCents, 0);
    expect(net.months.first.total.budgetCount, 2);
    await cell(left.node.id, 1);
    expect(find.text('Total de partidas: 0,00 €'), findsOneWidget);
    expect(find.text('Abrir'), findsNWidgets(2));
    await press('Volver al origen');
    await total(1360000, 50);

    debugPrint(
      'EP-021 EP-018 disponible: cancelar y guardar vuelve al destino anual',
    );
    await annual(2026);
    before = await snapshot();
    await press('Preparar año siguiente');
    await press('Generar propuesta');
    await press('Cancelar propuesta');
    await press('Descartar cambios');
    expect(await snapshot(), before);
    await total(1360000, 50);
    await press('Preparar año siguiente');
    await press('Generar propuesta');
    await press('Revisar y guardar');
    await tap(find.textContaining('He revisado la comparación y confirmo'));
    await press('Guardar propuesta');
    expect(navigation.period.year, 2027);
    expect(find.text('Presupuesto anual'), findsOneWidget);
    final savedProposal = await projection(2027);
    expect(savedProposal.annualTotal.amountCents, 231000);
    expect(savedProposal.annualTotal.budgetCount, 84);
    await total(
      savedProposal.annualTotal.amountCents,
      savedProposal.annualTotal.budgetCount,
      year: 2027,
    );

    debugPrint(
      'EP-021 restauración real sustituye conexión y refresca año/UUID',
    );
    await annual(2026);
    final beforeRestore = await snapshot();
    await io(local.controller.create);
    expect(local.controller.error, isNull);
    final copy = local.controller.listing!.entries.single.backupId;
    final prior = await projection(2026);
    await edit(leisure, 1, '25', existing: true);
    await save();
    await total(
      prior.annualTotal.amountCents + 2500,
      prior.annualTotal.budgetCount,
    );
    final oldIdentity = await io(() async => (await local.budgets()).identity);
    await io(() => local.controller.restore(copy, confirmed: true));
    expect(local.controller.restoreResult!.status, LocalRestoreStatus.restored);
    await settle();
    expect(
      identical(
        await io(() async => (await local.budgets()).identity),
        oldIdentity,
      ),
      isFalse,
    );
    await total(prior.annualTotal.amountCents, prior.annualTotal.budgetCount);
    expect(await snapshot(), beforeRestore);
    await reopen();
    await total(prior.annualTotal.amountCents, prior.annualTotal.budgetCount);
    // Las categorías cambiaron expresamente; entidades ajenas permanecen exactas.
    final finalProtected = await snapshot(protectedOnly: true);
    expect(
      {...finalProtected}..remove('categories'),
      {...protected}..remove('categories'),
    );
    debugPrint('EP-021 recorrido anual completo correcto');
  } finally {
    await close();
    navigation.dispose();
  }
}
