import 'dart:io';
import 'dart:convert';

import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:drift/native.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:sqlite3/sqlite3.dart';

class FailingCategoryMigration extends LocalDatabase {
  FailingCategoryMigration(super.executor);
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) => transaction(() async {
      await super.migration.onUpgrade(m, from, to);
      throw StateError('Fallo sintético tras crear categorías');
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late LocalDatabaseStore store;
  late SqliteCategoryRepository repo;
  setUp(() async {
    support = await Directory.systemTemp.createTemp('categories-synthetic-');
    store = LocalDatabaseStore(supportDirectory: () async => support);
    repo = SqliteCategoryRepository(await store.open());
  });
  tearDown(() async {
    await store.close();
    await support.delete(recursive: true);
  });

  test(
    'CRUD, tres niveles, ingreso heredado, nombres y archivo de rama',
    () async {
      final root = await repo.create(name: '  Ingresos Á  ', isIncome: true);
      final child = await repo.create(name: 'Nómina', parentId: root.id);
      final leaf = await repo.create(name: 'Nómina', parentId: child.id);
      expect(leaf.depth, 3);
      expect(leaf.isIncome, true);
      await repo.edit(
        child.id,
        name: 'Sueldo',
        parentId: root.id,
        isIncome: null,
      );
      await repo.setArchived(root.id, archived: true);
      expect(await repo.list(includeArchived: false), isEmpty);
      expect((await repo.get(root.id))!.name, '  Ingresos Á  ');
      expect((await repo.get(leaf.id))!.isIncome, true);
      await expectLater(
        repo.create(name: 'nuevo', parentId: root.id),
        throwsA(isA<CategoryFailure>()),
      );
      await expectLater(
        repo.setArchived(child.id, archived: false),
        throwsA(isA<CategoryFailure>()),
      );
      await store.close();
      repo = SqliteCategoryRepository(await store.open());
      expect((await repo.list()).length, 3);
      await repo.setArchived(root.id, archived: false);
      expect((await repo.list(includeArchived: false)).length, 3);
    },
  );

  test('Rechaza cuarto nivel, ciclos, padre inexistente, ingreso descendiente y nombre vacío', () async {
    final a = await repo.create(name: 'A');
    final b = await repo.create(name: 'B', parentId: a.id);
    final c = await repo.create(name: 'C', parentId: b.id);
    for (final action in <Future<Object?> Function()>[
      () => repo.create(name: 'D', parentId: c.id),
      () => repo.create(name: 'D', parentId: 'missing'),
      () => repo.create(name: 'D', parentId: a.id, isIncome: false),
      () => repo.create(name: '  '),
      () => repo.edit(a.id, name: 'A', parentId: c.id, isIncome: null),
      () => repo.edit(b.id, name: 'B', parentId: b.id, isIncome: null),
    ]) {
      await expectLater(action(), throwsA(isA<CategoryFailure>()));
    }
    final other = await repo.create(name: 'Otra');
    final nested = await repo.create(name: 'Hija', parentId: other.id);
    await expectLater(
      repo.edit(a.id, name: 'A', parentId: nested.id, isIncome: null),
      throwsA(isA<CategoryFailure>()),
    );
    expect((await repo.get(a.id))!.parentId, isNull);
    await repo.edit(c.id, name: 'C', parentId: other.id, isIncome: null);
    expect((await repo.get(c.id))!.depth, 2);
  });

  test('SQLite defiende CHECK, FK, ciclos y profundidad incluso sin repositorio', () async {
    final a = await repo.create(name: 'A');
    final b = await repo.create(name: 'B', parentId: a.id);
    final c = await repo.create(name: 'C', parentId: b.id);
    final d = await repo.create(name: 'D');
    for (final sql in [
      "UPDATE categories SET parent_id='missing',is_income=NULL WHERE id='${d.id}'",
      "UPDATE categories SET parent_id='${c.id}',is_income=NULL WHERE id='${d.id}'",
      "UPDATE categories SET parent_id='${c.id}',is_income=NULL WHERE id='${a.id}'",
      "UPDATE categories SET is_income=1 WHERE id='${b.id}'",
      "UPDATE categories SET is_income=NULL WHERE id='${a.id}'",
      "UPDATE categories SET name=' ' WHERE id='${a.id}'",
      "UPDATE categories SET archived=2 WHERE id='${a.id}'",
      "UPDATE categories SET id='invalid' WHERE id='${d.id}'",
      "DELETE FROM categories WHERE id='${a.id}'",
    ]) {
      await expectLater(repo.database.customStatement(sql), throwsA(anything));
    }
    expect((await repo.list()).length, 4);
  });

  test('Archivo conserva referencias históricas', () async {
    final root = await repo.create(name: 'Ingresos', isIncome: true);
    final leaf = await repo.create(name: 'Nómina', parentId: root.id);
    await repo.database.customStatement(
      "INSERT INTO accounts(id,name,kind,active_from,created_at,updated_at) VALUES('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee','Sintética','account','2026-01-01','t','t')",
    );
    await repo.database.customStatement(
      "INSERT INTO account_liquidity_periods VALUES('dddddddd-bbbb-4ccc-8ddd-eeeeeeeeeeee','aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee','2026-01-01',NULL,'liquid','t','t')",
    );
    await repo.database.customStatement(
      "INSERT INTO movements(id,account_id,value_date,concept,amount_cents,category_id,created_at,updated_at) VALUES('bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee','aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee','2026-01-01','Sintético',-100,?,'t','t')",
      [leaf.id],
    );
    await repo.database.customStatement(
      "INSERT INTO budgets(id,month,category_id,amount_cents,created_at,updated_at) VALUES('cccccccc-bbbb-4ccc-8ddd-eeeeeeeeeeee','2026-01-01',?,300000,'t','t')",
      [leaf.id],
    );
    await repo.setArchived(root.id, archived: true);
    for (final table in ['movements', 'budgets']) {
      expect(
        (await repo.database
                .customSelect('SELECT category_id FROM $table')
                .getSingle())
            .read<String>('category_id'),
        leaf.id,
      );
    }
    expect((await repo.get(leaf.id))!.name, 'Nómina');
  });

  test(
    'Migra v1 con respaldo, preserva metadatos y coincide con snapshot vigente',
    () async {
      final path = store.databasePath!;
      await store.close();
      File(path).deleteSync();
      final previous = sqlite3.open(path);
      previous.execute(initialStateSchema);
      previous.execute(
        "INSERT INTO database_state VALUES(1,'11111111-2222-4333-8444-555555555555',17)",
      );
      previous.execute('PRAGMA application_id=$localApplicationId');
      previous.execute('PRAGMA user_version=1');
      previous.close();
      final failing = FailingCategoryMigration(
        NativeDatabase(File(path), setup: configureConnection),
      );
      await expectLater(
        failing.customSelect('SELECT 1').get(),
        throwsStateError,
      );
      await failing.close();
      final unchanged = sqlite3.open(path);
      validateExistingDatabase(unchanged);
      expect(readSchemaVersion(unchanged), 1);
      expect(
        unchanged
            .select('SELECT revision FROM database_state')
            .single['revision'],
        17,
      );
      unchanged.close();
      final db = await store.open();
      final state = await db.select(db.databaseState).getSingle();
      expect(state.revision, 17);
      expect(state.datasetId, '11111111-2222-4333-8444-555555555555');
      expect(store.migrationBackupPath, isNotNull);
      final backup = sqlite3.open(store.migrationBackupPath!);
      expect(readSchemaVersion(backup), 1);
      backup.close();
      final snapshot = jsonDecode(
        File('drift_schemas/autofinance/drift_schema_v8.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final expected = sqlite3.openInMemory();
      for (final group in snapshot['fixed_sql'] as List) {
        for (final item in group['sql'] as List) {
          expected.execute(item['sql'] as String);
        }
      }
      final actual = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name NOT GLOB 'sqlite_*' ORDER BY name",
          )
          .get();
      expect(
        actual.map((r) => normalizeSchema(r.read<String>('sql'))).toList(),
        expected
            .select(
              "SELECT sql FROM sqlite_master WHERE name NOT GLOB 'sqlite_*' ORDER BY name",
            )
            .map((r) => normalizeSchema(r['sql'] as String))
            .toList(),
      );
      expected.close();
    },
  );
}
