import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalDatabaseStore store;
  late SqliteBudgetRepository repo;
  late SqliteCategoryRepository categories;
  late String root, child, leaf, sibling;
  BudgetInput input(String category, {int month = 1, int amount = 0}) =>
      BudgetInput(
        month: BudgetMonth(2026, month),
        categoryId: category,
        amountCents: amount,
      );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('budgets-synthetic-');
    store = LocalDatabaseStore(supportDirectory: () async => dir);
    final db = await store.open();
    repo = SqliteBudgetRepository(db);
    categories = SqliteCategoryRepository(db);
    root = (await categories.create(name: 'Alimentación')).id;
    child = (await categories.create(name: 'Supermercado', parentId: root)).id;
    leaf = (await categories.create(
      name: 'Compra semanal',
      parentId: child,
    )).id;
    sibling = (await categories.create(name: 'Restaurante', parentId: root)).id;
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  test(
    'Cero explícito, hermanos, meses independientes, CRUD y reapertura',
    () async {
      expect(await repo.list(BudgetMonth(2026, 1)), isEmpty);
      final a = await repo.create(input(child));
      await repo.create(input(sibling, amount: -40000));
      await repo.create(input(root, month: 2));
      await repo.create(input(leaf, month: 3));
      expect((await repo.list(BudgetMonth(2026, 1))).length, 2);
      expect((await repo.get(a.id))!.data.amountCents, 0);
      await repo.edit(a.id, input(child, amount: 9223372036854775807));
      await repo.edit(a.id, input(child, amount: -9223372036854775808));
      await store.close();
      repo = SqliteBudgetRepository(await store.open());
      expect((await repo.get(a.id))!.data.amountCents, -9223372036854775808);
      await repo.delete(a.id);
      expect(await repo.get(a.id), isNull);
      expect((await repo.list(BudgetMonth(2026, 1))).length, 1);
      expect(
        (await repo.database.customSelect('PRAGMA table_info(budgets)').get())
            .map((r) => r.read<String>('name')),
        isNot(contains('account_id')),
      );
    },
  );
  test(
    'Padre y descendiente en ambos órdenes, duplicados y edición atómica',
    () async {
      for (final descendant in [child, leaf]) {
        final parent = await repo.create(input(root));
        await expectLater(
          repo.create(input(descendant)),
          throwsA(isA<BudgetFailure>()),
        );
        await repo.delete(parent.id);
        final sub = await repo.create(input(descendant));
        await expectLater(
          repo.create(input(root)),
          throwsA(isA<BudgetFailure>()),
        );
        await expectLater(
          repo.create(input(descendant)),
          throwsA(isA<BudgetFailure>()),
        );
        final feb = await repo.create(input(root, month: 2, amount: 500));
        await expectLater(
          repo.edit(feb.id, input(root, amount: 900)),
          throwsA(isA<BudgetFailure>()),
        );
        expect((await repo.get(feb.id))!.data.month.value, '2026-02-01');
        expect((await repo.get(feb.id))!.data.amountCents, 500);
        await repo.delete(feb.id);
        await repo.delete(sub.id);
      }
    },
  );
  test(
    'Lotes mixtos, signo normalizado, procedencia y reversión completa',
    () async {
      final batches = SqliteImportBatchRepository(repo.database);
      final account = (await SqliteAccountRepository(repo.database).create(
        name: 'Cuenta',
        kind: AccountKind.account,
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      )).id;
      final movement = ImportedMovement(
        2,
        MovementInput(
          accountId: account,
          valueDate: ValueDate(2026, 1, 3),
          concept: 'Compra',
          amountCents: -500,
        ),
      );
      Future<ImportBatch> batch(
        String hash,
        List<ImportedBudget> budgets, {
        bool withMovement = false,
      }) => batches.create(
        sha256: hash * 64,
        source: ImportSource.historicalCsv,
        originalName: 'sintetico.csv',
        contractVersion: '1',
        movements: withMovement ? [movement] : [],
        budgets: budgets,
      );
      final data = BudgetInput.fromHistoricalCsv(
        month: BudgetMonth(2026, 1),
        categoryId: leaf,
        csvAmountCents: 40000,
        concept: 'Presupuesto',
        discretion: 'Necesario',
      );
      final b = await batch('a', [ImportedBudget(3, data)], withMovement: true);
      final row = (await repo.list(BudgetMonth(2026, 1))).single;
      expect(row.data.amountCents, -40000);
      expect(row.data.concept, 'Presupuesto');
      expect(row.data.discretion, 'Necesario');
      expect(row.batchId, b.id);
      expect(row.sourceOrdinal, 3);
      final edited = await repo.edit(row.id, data);
      expect(edited.importRowId, row.importRowId);
      for (final budgets in [
        [ImportedBudget(3, input(root))],
        [
          ImportedBudget(3, input(root, month: 2)),
          ImportedBudget(4, input(child, month: 2)),
        ],
        [
          ImportedBudget(3, input(child, month: 2)),
          ImportedBudget(4, input(root, month: 2)),
        ],
        [
          ImportedBudget(3, input(child, month: 2)),
          ImportedBudget(4, input(child, month: 2)),
        ],
      ]) {
        await expectLater(
          batch('b', budgets, withMovement: true),
          throwsA(isA<BudgetFailure>()),
        );
        expect(await batches.getByFingerprint('b' * 64), isNull);
        expect(await repo.list(BudgetMonth(2026, 2)), isEmpty);
        expect(
          (await repo.database.customSelect('SELECT * FROM movements').get())
              .length,
          1,
        );
        expect(
          (await repo.database.customSelect('SELECT * FROM import_rows').get())
              .length,
          2,
        );
      }
      await expectLater(
        batch('c', [
          ImportedBudget(2, input(root, month: 2)),
        ], withMovement: true),
        throwsA(isA<MovementFailure>()),
      );
      await batch('d', [
        ImportedBudget(
          2,
          BudgetInput.fromHistoricalCsv(
            month: BudgetMonth(2026, 2),
            categoryId: root,
            csvAmountCents: -300000,
          ),
        ),
      ]);
      expect(
        (await repo.list(BudgetMonth(2026, 2))).single.data.amountCents,
        300000,
      );
      expect(
        BudgetInput.fromHistoricalCsv(
          month: BudgetMonth(2026, 3),
          categoryId: root,
          csvAmountCents: 0,
        ).amountCents,
        0,
      );
      expect(
        () => BudgetInput.fromHistoricalCsv(
          month: BudgetMonth(2026, 3),
          categoryId: root,
          csvAmountCents: -9223372036854775808,
        ),
        throwsA(isA<BudgetFailure>()),
      );
      await repo.delete(row.id);
      await expectLater(
        batch('a', [ImportedBudget(2, input(root))]),
        throwsA(isA<MovementFailure>()),
      );
    },
  );
  test(
    'SQL directo protege solapamiento, tipos, mes, FK, origen e historia',
    () async {
      final a = await repo.create(input(root));
      final b = await repo.create(input(child, month: 2));
      for (final assignment in [
        "month='2026-01-01'",
        "amount_cents=1.5",
        "month='2026-13-01'",
        "category_id='missing'",
        "concept=' '",
        "import_row_id='missing'",
      ]) {
        await expectLater(
          repo.database.customStatement(
            'UPDATE budgets SET $assignment WHERE id=?',
            [b.id],
          ),
          throwsA(anything),
        );
      }
      await expectLater(
        categories.edit(root, name: 'Otra', parentId: null, isIncome: true),
        throwsA(isA<CategoryFailure>()),
      );
      await expectLater(
        repo.database.customStatement(
          'UPDATE categories SET is_income=1 WHERE id=?',
          [root],
        ),
        throwsA(anything),
      );
      await categories.setArchived(root, archived: true);
      await repo.edit(a.id, input(root, amount: 12));
      await expectLater(
        repo.create(input(root, month: 3)),
        throwsA(isA<BudgetFailure>()),
      );
      expect(
        () => BudgetMonth.parse('2026-01-15'),
        throwsA(isA<BudgetFailure>()),
      );
    },
  );
  test('v4 migra a la esquema vigente preservando categorías, revisión y esquema validado', () async {
    await store.close();
    final raw = sqlite3.open(store.databasePath!);
    for (final sql in [
      ...budgetSchemaObjects,
      ...wealthSchemaObjects,
    ].reversed) {
      final m = RegExp(r'CREATE (TABLE|INDEX|TRIGGER)\s+"?([a-z_]+)')
          .firstMatch(sql)!;
      raw.execute('DROP ${m[1]} "${m[2]}"');
    }
    raw.execute('PRAGMA user_version=4');
    raw.execute('UPDATE database_state SET revision=27');
    raw.close();
    repo = SqliteBudgetRepository(await store.open());
    expect(
      (await repo.database.select(repo.database.databaseState).getSingle())
          .revision,
      27,
    );
    expect((await SqliteCategoryRepository(repo.database).get(root))!.id, root);
    await repo.create(input(root));
    await store.close();
    final current = sqlite3.open(store.databasePath!);
    validateExistingDatabase(current);
    expect(readSchemaVersion(current), localSchemaVersion);
    current.close();
  });
}
