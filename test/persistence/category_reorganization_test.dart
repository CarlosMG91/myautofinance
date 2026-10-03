import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/database_failure.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:sqlite3/sqlite3.dart';

import 'published_schema_fixture.dart';

String id(int n) => '80000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
final income = id(1),
    salary = id(2),
    tax = id(3),
    payroll = id(4),
    expense = id(5);

class FailingReorganizationMigration extends LocalDatabase {
  FailingReorganizationMigration(super.executor);
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) => transaction(() async {
      await super.migration.onUpgrade(m, from, to);
      throw StateError('Interrupción sintética tras sustituir triggers');
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalDatabaseStore store;
  late LocalDatabase db;
  late SqliteCategoryRepository repo;
  var budgetId = 100;

  Future<void> budget(String category, String month, int amount) =>
      db.customStatement('INSERT INTO budgets VALUES(?,?,?,?,?,?,NULL,?,?)', [
        id(budgetId++),
        month,
        category,
        amount,
        'Previsto',
        'Necesario',
        't',
        't',
      ]);

  Future<Map<String, Object?>> snapshot({bool categories = true}) async => {
    for (final table in [
      if (categories) 'categories',
      if (categories) 'database_state',
      'movements',
      'budgets',
      'import_batches',
      'import_rows',
      'accounts',
      'account_liquidity_periods',
      'wealth_snapshots',
      'wealth_values',
    ])
      table: (await db.customSelect('SELECT * FROM $table ORDER BY 1').get())
          .map((r) => r.data)
          .toList(),
  };

  Future<void> move(String node, String? parent, {bool? type}) async {
    final old = (await repo.get(node))!;
    await repo.edit(node, name: old.name, parentId: parent, isIncome: type);
  }

  Future<void> unchangedAfter(
    Future<void> Function() action, {
    Matcher? error,
  }) async {
    final before = await snapshot();
    await expectLater(action(), throwsA(error ?? isA<CategoryFailure>()));
    expect(await snapshot(), before);
  }

  setUp(() async {
    budgetId = 100;
    directory = await Directory.systemTemp.createTemp(
      'category-move-synthetic-',
    );
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    db = await store.open();
    repo = SqliteCategoryRepository(db);
    // Caso L: UUID y datos sintéticos estables, con procedencia conservable.
    for (final row in [
      [income, null, 'INGRESOS', 1],
      [salary, income, 'SALARIO', null],
      [tax, salary, 'IMPUESTOS', null],
      [payroll, salary, 'NÓMINA', null],
      [expense, null, 'GASTOS', 0],
    ]) {
      await db.customStatement('INSERT INTO categories VALUES(?,?,?,?,0,?,?)', [
        ...row,
        't',
        't',
      ]);
    }
    await db.customStatement(
      "INSERT INTO accounts VALUES(?,'Cuenta sintética','account','2025-01-01',NULL,'t','t')",
      [id(10)],
    );
    await db.customStatement(
      "INSERT INTO account_liquidity_periods VALUES(?,?,'2025-01-01',NULL,'liquid','t','t')",
      [id(11), id(10)],
    );
    await db.customStatement(
      "INSERT INTO import_batches VALUES(?,?,'historical_csv','sintetico.csv','1','t','t','t')",
      [id(12), 'a' * 64],
    );
    for (final n in [13, 14]) {
      await db.customStatement(
        "INSERT INTO import_rows VALUES(?,?,?,'movement','t','t')",
        [id(n), id(12), n],
      );
    }
    await db.customStatement(
      "INSERT INTO movements VALUES(?,?,'2026-01-05','Salario bruto',300000,?,NULL,?,'t','t')",
      [id(15), id(10), salary, id(13)],
    );
    await db.customStatement(
      "INSERT INTO movements VALUES(?,?,'2026-01-06','Retención',-60000,?,'Necesario',?,'t','t')",
      [id(16), id(10), tax, id(14)],
    );
    await db.customStatement(
      "INSERT INTO wealth_snapshots VALUES(?,'2026-01-01','t','t')",
      [id(17)],
    );
    await db.customStatement(
      "INSERT INTO wealth_values VALUES(?,?,?,900000,'t','t')",
      [id(18), id(17), id(10)],
    );
    for (var m = 1; m <= 12; m++) {
      final month = '2026-${m.toString().padLeft(2, '0')}-01';
      await budget(tax, month, -60000);
      await budget(payroll, month, 300000);
    }
    await db.customStatement(
      "INSERT INTO import_rows VALUES(?,?,15,'budget','t','t')",
      [id(19), id(12)],
    );
    // Procedencia se asigna al insertar, nunca editando una partida existente.
    await db.customStatement(
      "INSERT INTO budgets VALUES(?,'2025-01-01',?,0,'Histórico','Necesario',?,'t','t')",
      [id(99), tax, id(19)],
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'L/M: traslado con histórico, signos, herencia, revisión, no-op y copia',
    () async {
      final history = await snapshot(categories: false);
      final state = await db.readState();
      final budgets = SqliteBudgetRepository(db);
      final movements = SqliteMovementRepository(db);
      expect((await budgets.readYear(2026, incomeOnly: true)).length, 24);
      await move(salary, expense);
      expect((await db.readState()).revision, state.revision + 1);
      for (final node in [salary, tax, payroll]) {
        expect((await repo.get(node))!.isIncome, false);
      }
      expect((await repo.get(tax))!.depth, 3);
      expect(await snapshot(categories: false), history);
      expect(await budgets.readYear(2026, incomeOnly: true), isEmpty);
      expect(await movements.readYear(2026, categoryId: income), isEmpty);
      final real = await movements.readMonth(2026, 1, categoryId: expense);
      expect(real.map((r) => r.data.categoryId).toSet(), {salary, tax});
      expect(real.fold<int>(0, (sum, r) => sum + r.data.amountCents), 240000);
      final totals = await db.customSelect('''
WITH RECURSIVE tree(id,root,income) AS (
 SELECT id,id,is_income FROM categories WHERE parent_id IS NULL
 UNION ALL SELECT c.id,t.root,t.income FROM categories c JOIN tree t ON c.parent_id=t.id
) SELECT t.root,t.income,sum(b.amount_cents) AS total FROM budgets b
JOIN tree t ON t.id=b.category_id WHERE b.month LIKE '2026-%' GROUP BY t.root,t.income
''').getSingle();
      expect(totals.read<String>('root'), expense);
      expect(totals.read<int>('income'), 0);
      expect(totals.read<int>('total'), 2880000);
      await move(salary, expense);
      expect((await db.readState()).revision, state.revision + 1);
      await move(salary, income);
      expect((await budgets.readYear(2026, incomeOnly: true)).length, 24);
      expect((await repo.get(tax))!.isIncome, true);
      expect((await db.readState()).revision, state.revision + 2);
      final copy = await store.createConsistentBackup();
      final raw = sqlite3.open(copy.path, mode: OpenMode.readOnly);
      validateExistingDatabase(raw);
      expect(
        raw.select('SELECT parent_id FROM categories WHERE id=?', [
          salary,
        ]).single['parent_id'],
        income,
      );
      raw.close();
      await store.close();
      db = await store.open();
      repo = SqliteCategoryRepository(db);
      expect(await snapshot(categories: false), history);
      expect((await repo.get(tax))!.isIncome, true);
    },
  );

  test(
    'M: promoción conserva ambos tipos y bloqueo solo del cambio directo usado',
    () async {
      await unchangedAfter(() => move(income, null, type: false));
      await unchangedAfter(() => move(salary, null, type: false));
      await move(salary, null);
      expect((await repo.get(salary))!.isIncome, true);
      expect((await repo.get(tax))!.depth, 2);
      await unchangedAfter(() => move(salary, null, type: false));
      await move(salary, expense);
      await unchangedAfter(() => move(salary, null, type: true));
      await move(salary, null, type: false);
      expect((await repo.get(tax))!.isIncome, false);
      await unchangedAfter(() => move(salary, null, type: true));
      await move(income, null, type: false); // Ahora sin referencias.
      expect((await repo.get(income))!.isIncome, false);
      final root = await repo.create(name: 'Raíz usada', isIncome: true);
      await budget(root.id, '2024-04-01', -123);
      await move(root.id, expense);
      expect((await repo.get(root.id))!.isIncome, false);
    },
  );

  test('M/N: subárbol completo, ciclos, destino ausente/archivado y archivo conservado', () async {
    final nested = await repo.create(name: 'Segundo nivel', parentId: expense);
    await unchangedAfter(() => move(salary, nested.id));
    await unchangedAfter(
      () => db.customStatement('UPDATE categories SET parent_id=? WHERE id=?', [
        nested.id,
        salary,
      ]),
      error: anything,
    );
    await unchangedAfter(() => move(income, tax));
    await unchangedAfter(() => move(salary, salary));
    await unchangedAfter(() => move(salary, id(900)));
    await repo.setArchived(expense, archived: true);
    await unchangedAfter(() => move(salary, expense));
    await repo.setArchived(expense, archived: false);
    await repo.setArchived(salary, archived: true);
    final history = await snapshot(categories: false);
    final revision = (await db.readState()).revision;
    await move(salary, expense);
    expect((await db.readState()).revision, revision + 1);
    for (final node in [salary, tax, payroll]) {
      expect((await repo.get(node))!.archived, true);
      expect((await repo.get(node))!.isIncome, false);
    }
    await repo.setArchived(expense, archived: true);
    await unchangedAfter(() => repo.setArchived(salary, archived: false));
    await repo.setArchived(expense, archived: false);
    expect((await repo.list(includeArchived: false)).length, 6);
    expect(await snapshot(categories: false), history);
  });

  test('O: informa todos los meses y pares, incluidos cero, históricos y archivados', () async {
    await budget(expense, '2025-01-01', 0);
    await budget(expense, '2026-02-01', 0);
    await budget(expense, '2026-12-01', -100);
    await repo.setArchived(salary, archived: true);
    final before = await snapshot();
    try {
      await move(salary, expense);
      fail('Debe rechazar todos los solapamientos');
    } on CategoryFailure catch (e) {
      expect(e.budgetConflicts.length, 5);
      expect(e.budgetConflicts.map((c) => c.month).toSet(), {
        '2025-01-01',
        '2026-02-01',
        '2026-12-01',
      });
      for (final conflict in e.budgetConflicts) {
        expect(conflict.ancestorId, expense);
        expect(conflict.ancestorPath, 'GASTOS');
        expect(conflict.descendantId, isIn([tax, payroll]));
        expect(conflict.descendantPath, startsWith('GASTOS / SALARIO / '));
      }
    }
    expect(await snapshot(), before);
    await store.close();
    db = await store.open();
    repo = SqliteCategoryRepository(db);
    expect(await snapshot(), before);
  });

  test(
    'O: hermanas y meses distintos válidos, sin reasignar partidas',
    () async {
      await budget(expense, '2024-02-01', -1000);
      final sibling = await repo.create(name: 'IMPUESTOS', parentId: expense);
      await budget(sibling.id, '2026-01-01', -10000);
      final history = await snapshot(categories: false);
      await move(tax, expense);
      expect(await snapshot(categories: false), history);
      await move(salary, expense);
      expect(await snapshot(categories: false), history);
    },
  );

  test('SQL directo: traslados/promoción válidos y protecciones de tipo y destino', () async {
    final history = await snapshot(categories: false);
    await db.writeTransaction(
      () => db.customStatement(
        'UPDATE categories SET parent_id=?,is_income=NULL WHERE id=?',
        [expense, salary],
      ),
    );
    expect((await db.readState()).revision, 1);
    expect((await repo.get(tax))!.isIncome, false);
    for (final sql in [
      "UPDATE categories SET parent_id=NULL,is_income=1 WHERE id='$salary'",
      "UPDATE categories SET is_income=1 WHERE id='$expense'",
      "UPDATE categories SET parent_id='$tax',is_income=NULL WHERE id='$expense'",
      "UPDATE categories SET parent_id='$tax',is_income=NULL WHERE id='$salary'",
      "UPDATE categories SET parent_id='${id(900)}',is_income=NULL WHERE id='$salary'",
    ]) {
      await unchangedAfter(() => db.customStatement(sql), error: anything);
    }
    await db.writeTransaction(
      () => db.customStatement(
        'UPDATE categories SET parent_id=NULL,is_income=0 WHERE id=?',
        [salary],
      ),
    );
    expect((await db.readState()).revision, 2);
    expect((await repo.get(tax))!.isIncome, false);
    await repo.setArchived(expense, archived: true);
    await unchangedAfter(
      () => db.customStatement(
        'UPDATE categories SET parent_id=?,is_income=NULL WHERE id=?',
        [expense, salary],
      ),
      error: anything,
    );
    await unchangedAfter(
      () => db.customStatement(
        "INSERT INTO categories VALUES(?,?,'Nuevo',NULL,0,'t','t')",
        [id(901), expense],
      ),
      error: anything,
    );
    expect(await snapshot(categories: false), history);
  });

  test('SQL directo: raíz usada solo por movimientos bloqueada, herencia permitida', () async {
    await db.customStatement('DELETE FROM budgets');
    await repo.setArchived(salary, archived: true);
    await unchangedAfter(
      () => db.customStatement('UPDATE categories SET is_income=0 WHERE id=?', [
        income,
      ]),
      error: anything,
    );
    await move(salary, expense);
    expect((await repo.get(tax))!.isIncome, false);
  });

  for (final direct in [false, true]) {
    test(
      'O: rollback de unidad completa incluido renombrado (SQL=$direct)',
      () async {
        await budget(expense, '2025-01-01', 0);
        await unchangedAfter(
          () => db.run(() async {
            await repo.edit(
              salary,
              name: 'Renombrado',
              parentId: income,
              isIncome: null,
            );
            if (direct) {
              await db.customStatement(
                'UPDATE categories SET parent_id=? WHERE id=?',
                [expense, salary],
              );
            } else {
              await move(salary, expense);
            }
          }),
          error: anything,
        );
        await unchangedAfter(
          () => db.customStatement(
            'UPDATE categories SET parent_id=? WHERE id=?',
            [expense, salary],
          ),
          error: anything,
        );
      },
    );
  }

  test(
    'v6 → v7 con respaldo, rollback, snapshot, linaje e histórico intactos',
    () async {
      final before = await snapshot();
      final path = store.databasePath!;
      await store.close();
      final previous = sqlite3.open(path);
      usePublishedV6CategoryTriggers(previous);
      previous.execute('PRAGMA user_version=6');
      validateExistingDatabase(previous);
      previous.close();
      final failing = FailingReorganizationMigration(
        NativeDatabase(File(path), setup: configureConnection),
      );
      await expectLater(
        failing.customSelect('SELECT 1').get(),
        throwsStateError,
      );
      await failing.close();
      final original = sqlite3.open(path, mode: OpenMode.readOnly);
      validateExistingDatabase(original);
      expect(readSchemaVersion(original), 6);
      original.close();
      db = await store.open();
      repo = SqliteCategoryRepository(db);
      expect(await snapshot(), before);
      final backup = sqlite3.open(
        store.migrationBackupPath!,
        mode: OpenMode.readOnly,
      );
      validateExistingDatabase(backup);
      expect(readSchemaVersion(backup), 6);
      for (final entry in before.entries) {
        expect(
          backup
              .select('SELECT * FROM ${entry.key} ORDER BY 1')
              .map((r) => Map<String, Object?>.from(r))
              .toList(),
          entry.value,
        );
      }
      backup.close();
      final backupBytes = File(store.migrationBackupPath!).readAsBytesSync();
      final validated = await const SqliteLocalBackupValidator().validate(
        store.migrationBackupPath!,
      );
      expect(validated.schemaVersion, 6);
      expect(File(store.migrationBackupPath!).readAsBytesSync(), backupBytes);
      final exported = jsonDecode(
        File('drift_schemas/autofinance/drift_schema_v7.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final expected = sqlite3.openInMemory();
      for (final group in exported['fixed_sql'] as List) {
        for (final item in group['sql'] as List) {
          expected.execute(item['sql'] as String);
        }
      }
      expect(
        (await db
                .customSelect(
                  "SELECT sql FROM sqlite_master WHERE name NOT GLOB 'sqlite_*' ORDER BY name",
                )
                .get())
            .map((r) => normalizeSchema(r.read<String>('sql'))),
        expected
            .select(
              "SELECT sql FROM sqlite_master WHERE name NOT GLOB 'sqlite_*' ORDER BY name",
            )
            .map((r) => normalizeSchema(r['sql'] as String)),
      );
      expected.close();
      await move(salary, expense);
      expect((await repo.get(tax))!.isIncome, false);
    },
  );

  for (final corruption in ['overlap', 'cycle', 'depth', 'trigger']) {
    test('Apertura rechaza $corruption manipulada sin cambiar bytes', () async {
      final path = store.databasePath!;
      await store.close();
      final raw = sqlite3.open(path);
      final trigger = corruption == 'overlap'
          ? 'categories_budget_overlap'
          : 'categories_update';
      final sql =
          raw.select('SELECT sql FROM sqlite_master WHERE name=?', [
                trigger,
              ]).single['sql']
              as String;
      raw.execute('DROP TRIGGER $trigger');
      if (corruption == 'overlap') {
        raw.execute(
          "INSERT INTO budgets VALUES(?,'2025-01-01',?,0,NULL,NULL,NULL,'t','t')",
          [id(950), expense],
        );
        raw.execute('UPDATE categories SET parent_id=? WHERE id=?', [
          expense,
          salary,
        ]);
      } else if (corruption == 'cycle') {
        raw.execute('DELETE FROM budgets');
        raw.execute(
          'UPDATE categories SET parent_id=?,is_income=NULL WHERE id=?',
          [tax, income],
        );
      } else if (corruption == 'depth') {
        raw.execute(
          'UPDATE categories SET parent_id=?,is_income=NULL WHERE id=?',
          [expense, income],
        );
      }
      if (corruption != 'trigger') raw.execute(sql);
      raw.close();
      final bytes = File(path).readAsBytesSync();
      await expectLater(store.open(), throwsA(isA<DatabaseFailure>()));
      expect(File(path).readAsBytesSync(), bytes);
      expect(store.migrationBackupPath, isNull);
    });
  }
}
