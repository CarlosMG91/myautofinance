import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalDatabaseStore store;
  late MovementRepository movements;
  late BudgetRepository budgets;
  late CategoryRepository categories;
  late WealthRepository wealth;
  late AccountRepository accounts;
  late String mainAccount, savings, portfolio, debt;
  late Map<String, String> nodes;
  final jan = Month(2026, 1), feb = Month(2026, 2);

  int sumMovements(List<MovementRecord> rows) =>
      rows.fold(0, (s, r) => s + r.data.amountCents);
  int sumBudgets(List<BudgetRecord> rows) =>
      rows.fold(0, (s, r) => s + r.data.amountCents);
  int liquid(WealthSnapshot photo) => photo.values
      .where((v) => v.account.liquidity == Liquidity.liquid)
      .fold(0, (s, v) => s + v.amountCents);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('report-synthetic-');
    store = LocalDatabaseStore(supportDirectory: () async => dir);
    final db = await store.open();
    movements = SqliteMovementRepository(db);
    budgets = SqliteBudgetRepository(db);
    categories = SqliteCategoryRepository(db);
    wealth = SqliteWealthRepository(db);
    accounts = SqliteAccountRepository(db);
    nodes = {};
    // Misma jerarquía y registros que los casos A–G de EP-001.
    for (final root in [
      'Ingresos',
      'Vivienda',
      'Alimentación',
      'Ahorro',
      'Ocio',
    ]) {
      nodes[root] = (await categories.create(
        name: root,
        isIncome: root == 'Ingresos',
      )).id;
    }
    for (final pair in {
      'Salario': 'Ingresos',
      'Alquiler': 'Vivienda',
      'Supermercado': 'Alimentación',
      'Cuenta de ahorro': 'Ahorro',
      'Compra semanal': 'Supermercado',
    }.entries) {
      nodes[pair.key] = (await categories.create(
        name: pair.key,
        parentId: nodes[pair.value],
      )).id;
    }
    Future<String> account(
      String name,
      AccountKind kind,
      Liquidity? liquidity,
    ) async => (await accounts.create(
      name: name,
      kind: kind,
      activeFrom: jan,
      liquidity: liquidity,
    )).id;
    mainAccount = await account(
      'Cuenta principal',
      AccountKind.account,
      Liquidity.liquid,
    );
    savings = await account(
      'Cuenta de ahorro',
      AccountKind.account,
      Liquidity.liquid,
    );
    portfolio = await account(
      'Cartera',
      AccountKind.portfolio,
      Liquidity.medium,
    );
    debt = await account('Deuda familiar', AccountKind.debt, null);
    final importedBudgets = <ImportedBudget>[];
    for (var month = 1; month <= 12; month++) {
      for (final entry in {
        'Salario': 300000,
        'Alquiler': -100000,
        'Compra semanal': -40000,
        'Cuenta de ahorro': -50000,
      }.entries) {
        importedBudgets.add(
          ImportedBudget(
            importedBudgets.length + 2,
            BudgetInput(
              month: BudgetMonth(2026, month),
              categoryId: nodes[entry.key]!,
              amountCents: entry.value,
            ),
          ),
        );
      }
    }
    final importedMovements = <ImportedMovement>[];
    for (var month = 1; month <= 2; month++) {
      for (final entry in {
        'Salario': month == 1 ? 310000 : 302000,
        'Alquiler': -100000,
        'Compra semanal': month == 1 ? -35025 : -42010,
        'Cuenta de ahorro': -50000,
      }.entries) {
        importedMovements.add(
          ImportedMovement(
            importedMovements.length + 50,
            MovementInput(
              accountId: mainAccount,
              valueDate: ValueDate(
                2026,
                month,
                5 + importedMovements.length % 4,
              ),
              concept: entry.key,
              categoryId: nodes[entry.key],
              amountCents: entry.value,
              discretion: entry.key == 'Compra semanal' ? 'Discrecional' : null,
            ),
          ),
        );
      }
      if (month == 1) {
        for (var i = 0; i < 2; i++) {
          importedMovements.add(
            ImportedMovement(
              importedMovements.length + 50,
              MovementInput(
                accountId: mainAccount,
                valueDate: ValueDate(2026, 1, 9),
                concept: 'Café',
                categoryId: nodes['Ocio'],
                amountCents: -1000,
              ),
            ),
          );
        }
      }
    }
    await SqliteImportBatchRepository(db).create(
      sha256: 'a' * 64,
      source: ImportSource.historicalCsv,
      originalName: 'synthetic.csv',
      contractVersion: '1',
      movements: importedMovements,
      budgets: importedBudgets,
    );
    for (final entry in {
      mainAccount: 600000,
      savings: 300000,
      portfolio: 1000000,
      debt: 500000,
    }.entries) {
      await wealth.setValue(jan, entry.key, entry.value);
    }
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test(
    'Cuatro vistas y colchón reconstruidos solo con contratos públicos',
    () async {
      final db = await store.open();
      final revision = (await db.readState()).revision;
      final real = await movements.readYear(2026);
      final planned = await budgets.readYear(2026);
      final tree = await categories.list();
      expect(real.length, 10);
      expect(real.map((r) => r.id).toSet().length, 10);
      expect(
        real.every((r) => r.batchId != null && r.sourceOrdinal != null),
        isTrue,
      );
      expect(planned.length, 48);
      expect(planned.every((r) => r.importRowId != null), isTrue);
      expect(sumMovements(real), 232965);
      expect(sumBudgets(planned), 1320000);
      // La reconstrucción sube el nodo directo por el árbol, sin leer SQL.
      Set<String> branch(String root) {
        final result = <String>{root};
        for (var depth = 0; depth < 3; depth++) {
          result.addAll(
            tree.where((n) => result.contains(n.parentId)).map((n) => n.id),
          );
        }
        return result;
      }

      final expected = {
        'Ingresos': (310000, 300000),
        'Vivienda': (-100000, -100000),
        'Alimentación': (-35025, -40000),
        'Ahorro': (-50000, -50000),
        'Ocio': (-2000, 0),
      };
      final january = await movements.readMonth(2026, 1);
      final januaryBudget = await budgets.list(BudgetMonth(2026, 1));
      for (final entry in expected.entries) {
        final ids = branch(nodes[entry.key]!);
        expect(
          sumMovements(
            january.where((r) => ids.contains(r.data.categoryId)).toList(),
          ),
          entry.value.$1,
        );
        expect(
          sumBudgets(
            januaryBudget
                .where((r) => ids.contains(r.data.categoryId))
                .toList(),
          ),
          entry.value.$2,
        );
      }
      expect(sumMovements(january) - sumBudgets(januaryBudget), 12975);
      expect(sumMovements(await movements.readMonth(2026, 2)), 109990);
      expect(await movements.readMonth(2026, 3), isEmpty);
      expect(january.where((r) => r.data.concept == 'Café').length, 2);
      expect(
        januaryBudget.any((r) => r.data.categoryId == nodes['Ocio']),
        isFalse,
      );
      expect(
        (await movements.readYear(
          2026,
          categoryId: nodes['Alimentación'],
        )).length,
        2,
      );
      final photos = await wealth.readYear(2026);
      expect(photos.length, 12);
      expect(photos.first.status, WealthSnapshotStatus.complete);
      expect(
        photos
            .skip(1)
            .every(
              (p) =>
                  p.status == WealthSnapshotStatus.absent &&
                  p.values.isEmpty &&
                  p.pending.length == 4,
            ),
        isTrue,
      );
      final assets = photos.first.values
          .where((v) => v.account.kind != AccountKind.debt)
          .fold<int>(0, (s, v) => s + v.amountCents);
      expect(assets, 1900000);
      expect(
        assets -
            photos.first.values
                .singleWhere((v) => v.account.kind == AccountKind.debt)
                .amountCents,
        1400000,
      );
      final income = await budgets.readYear(2026, incomeOnly: true);
      expect(income.length, 12);
      expect(liquid(photos.first) / (sumBudgets(income) / 12), 3);
      expect((await db.readState()).revision, revision);
    },
  );

  test(
    'Casos D/G: ausencia, parcial, cero explícito y liquidez histórica',
    () async {
      var income = await budgets.readYear(2026, incomeOnly: true);
      await budgets.delete(
        income.singleWhere((r) => r.data.month.value == '2026-03-01').id,
      );
      income = await budgets.readYear(2026, incomeOnly: true);
      expect(income.map((r) => r.data.month.value).toSet().length, 11);
      await budgets.create(
        BudgetInput(
          month: BudgetMonth(2026, 3),
          categoryId: nodes['Ingresos']!,
          amountCents: 0,
        ),
      );
      income = await budgets.readYear(2026, incomeOnly: true);
      expect(income.length, 12);
      expect(
        income
            .singleWhere((r) => r.data.month.value == '2026-03-01')
            .data
            .amountCents,
        0,
      );
      for (final row in income) {
        await budgets.edit(
          row.id,
          BudgetInput(
            month: row.data.month,
            categoryId: row.data.categoryId,
            amountCents: -10000,
          ),
        );
      }
      expect(
        sumBudgets(await budgets.readYear(2026, incomeOnly: true)),
        -120000,
      );
      await wealth.setValue(feb, mainAccount, 620000);
      await wealth.setValue(feb, debt, 480000);
      expect(
        (await wealth.readYear(2026))[1].status,
        WealthSnapshotStatus.incomplete,
      );
      expect(
        (await wealth.read(feb)).pending.map((a) => a.id),
        unorderedEquals([savings, portfolio]),
      );
      await wealth.setValue(feb, savings, 0);
      await wealth.setValue(feb, portfolio, 1050000);
      expect((await wealth.read(feb)).status, WealthSnapshotStatus.complete);
      expect(liquid(await wealth.read(feb)), 620000);
      await accounts.changeLiquidity(portfolio, feb, Liquidity.liquid);
      final photos = await wealth.readYear(2026);
      expect(liquid(photos[0]), 900000);
      expect(liquid(photos[1]), 1670000);
      final newer = await accounts.create(
        name: 'Nueva',
        kind: AccountKind.account,
        activeFrom: Month(2026, 3),
        liquidity: Liquidity.liquid,
      );
      await accounts.close(newer.id, Month(2026, 4));
      final updated = await wealth.readYear(2026);
      expect(updated[0].pending, isEmpty);
      expect(updated[2].pending.any((a) => a.id == newer.id), isTrue);
      expect(updated[4].pending.any((a) => a.id == newer.id), isFalse);
    },
  );

  test(
    'Caso J: reales directos, sin clasificar y signo ajeno a ingreso',
    () async {
      for (final entry in <(String?, int)>[
        (nodes['Alimentación'], -1200),
        (nodes['Supermercado'], 200),
        (null, 700),
        (null, -300),
        (nodes['Cuenta de ahorro'], 500),
        (nodes['Salario'], -400),
      ]) {
        await movements.create(
          MovementInput(
            accountId: mainAccount,
            valueDate: ValueDate(2026, 1, 31),
            concept: 'Ajuste sintético',
            categoryId: entry.$1,
            amountCents: entry.$2,
          ),
        );
      }
      expect(sumMovements(await movements.readMonth(2026, 1)), 122475);
      expect(
        sumMovements(
          await movements.readMonth(2026, 1, categoryId: nodes['Alimentación']),
        ),
        -36025,
      );
      expect(
        sumMovements(
          await movements.readMonth(2026, 1, categoryId: nodes['Supermercado']),
        ),
        -34825,
      );
      expect(
        sumMovements(
          await movements.readMonth(2026, 1, categoryId: nodes['Ingresos']),
        ),
        309600,
      );
      expect(
        sumMovements(
          (await movements.readYear(2026))
              .where((r) => r.data.categoryId == null)
              .toList(),
        ),
        400,
      );
      await categories.setArchived(nodes['Alimentación']!, archived: true);
      expect(
        (await movements.readMonth(
          2026,
          1,
          categoryId: nodes['Alimentación'],
        )).length,
        3,
      );
      expect(
        (await categories.list()).any(
          (n) => n.id == nodes['Alimentación'] && n.archived,
        ),
        isTrue,
      );
      expect(liquid(await wealth.read(jan)), 900000);
    },
  );

  test('Lecturas completas, límites civiles e índices existentes', () async {
    final db = await store.open();
    await db.run(() async {
      for (var i = 0; i < 501; i++) {
        await movements.create(
          MovementInput(
            accountId: mainAccount,
            valueDate: ValueDate(2026, 12, 31),
            concept: 'Sintético $i',
            amountCents: 1,
          ),
        );
      }
    });
    expect((await movements.readYear(2026)).length, 511);
    expect((await movements.readMonth(2026, 12)).length, 501);
    expect(await movements.readYear(2027), isEmpty);
    expect(await budgets.readYear(2027), isEmpty);
    await movements.create(
      MovementInput(
        accountId: mainAccount,
        valueDate: ValueDate(9999, 12, 31),
        concept: 'Último día',
        amountCents: 1,
      ),
    );
    await budgets.create(
      BudgetInput(
        month: BudgetMonth(9999, 12),
        categoryId: nodes['Salario']!,
        amountCents: 0,
      ),
    );
    expect((await movements.readYear(9999)).length, 1);
    expect((await movements.readMonth(9999, 12)).length, 1);
    expect((await budgets.readYear(9999)).length, 1);
    expect((await wealth.readYear(9999)).length, 12);
    await expectLater(budgets.readYear(0), throwsA(isA<BudgetFailure>()));
    expect(
      () => movements.readMonth(2026, 13),
      throwsA(isA<MovementFailure>()),
    );
    expect(() => wealth.readYear(10000), throwsA(isA<AccountFailure>()));
    for (final sql in [
      "SELECT * FROM movements WHERE value_date>='2026-01-01' AND value_date<'2027-01-01' ORDER BY value_date,id",
      "SELECT * FROM budgets WHERE month>='2026-01-01' AND month<'2027-01-01'",
    ]) {
      final plan = await db.customSelect('EXPLAIN QUERY PLAN $sql').get();
      expect(
        plan.map((r) => r.read<String>('detail')).join(),
        contains('INDEX'),
      );
    }
  });
}
