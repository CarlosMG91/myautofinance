import 'published_schema_fixture.dart';

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show MigrationStrategy, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/data/sqlite/database_failure.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:sqlite3/sqlite3.dart';

class FailedAccountMigration extends LocalDatabase {
  FailedAccountMigration(super.executor);
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) => transaction(() async {
      await super.migration.onUpgrade(m, from, to);
      throw StateError('Fallo sintético v3');
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late LocalDatabaseStore store;
  late SqliteAccountRepository repo;
  Month m(int month) => Month(2026, month);
  Future<AccountRecord> asset({
    Month? end,
    AccountKind kind = AccountKind.account,
  }) => repo.create(
    name: 'Activo sintético',
    kind: kind,
    activeFrom: m(2),
    activeThrough: end,
    liquidity: Liquidity.liquid,
  );
  Future<Liquidity?> classification(String id, int month) async =>
      (await repo.listForMonth(m(month)))
          .where((a) => a.id == id)
          .single
          .liquidity;
  setUp(() async {
    support = await Directory.systemTemp.createTemp('accounts-synthetic-');
    store = LocalDatabaseStore(supportDirectory: () async => support);
    repo = SqliteAccountRepository(await store.open());
  });
  tearDown(() async {
    await store.close();
    await support.delete(recursive: true);
  });

  test(
    'Alta y baja inclusivas, deuda sin liquidez, cartera y reapertura',
    () async {
      final a = await asset(end: m(4));
      final p = await asset(kind: AccountKind.portfolio);
      final d = await repo.create(
        name: 'Deuda',
        kind: AccountKind.debt,
        activeFrom: m(2),
        activeThrough: m(4),
      );
      expect(await repo.listForMonth(m(1)), isEmpty);
      expect((await repo.listForMonth(m(2))).length, 3);
      expect((await repo.listForMonth(m(4))).length, 3);
      expect((await repo.listForMonth(m(5))).single.id, p.id);
      expect(await classification(d.id, 3), isNull);
      await repo.rename(a.id, 'Cuenta renombrada');
      await store.close();
      repo = SqliteAccountRepository(await store.open());
      expect((await repo.get(a.id))!.name, 'Cuenta renombrada');
      expect((await repo.history(a.id)).single.until!.value, m(5).value);
      expect(await classification(a.id, 2), Liquidity.liquid);
    },
  );
  test('Cambio divide periodo, conserva pasado y cambios programados; corrección acotada', () async {
    final a = await asset();
    await repo.changeLiquidity(a.id, m(9), Liquidity.illiquid);
    await repo.changeLiquidity(a.id, m(5), Liquidity.medium);
    expect(await classification(a.id, 4), Liquidity.liquid);
    expect(await classification(a.id, 5), Liquidity.medium);
    expect(await classification(a.id, 8), Liquidity.medium);
    expect(await classification(a.id, 9), Liquidity.illiquid);
    await repo.correctHistoricalLiquidity(a.id, m(3), m(7), Liquidity.illiquid);
    expect(await classification(a.id, 2), Liquidity.liquid);
    for (final month in [3, 4, 5, 6]) {
      expect(await classification(a.id, month), Liquidity.illiquid);
    }
    expect(await classification(a.id, 7), Liquidity.medium);
    expect(await classification(a.id, 9), Liquidity.illiquid);
    await repo.close(a.id, m(10));
    expect(await classification(a.id, 10), Liquidity.illiquid);
    expect(await repo.listForMonth(m(11)), isEmpty);
    expect((await repo.history(a.id)).last.until!.value, m(11).value);
    expect((await repo.get(a.id))!.id, a.id);
  });
  test(
    'Validaciones, rollback, año máximo y no reutilización de bajas',
    () async {
      final a = await asset(end: m(8));
      final before = (await repo.history(a.id)).map((p) => p.id).toList();
      for (final action in <Future<Object?> Function()>[
        () => repo.create(
          name: 'Deuda',
          kind: AccountKind.debt,
          activeFrom: m(1),
          liquidity: Liquidity.medium,
        ),
        () => repo.create(
          name: 'Activo',
          kind: AccountKind.account,
          activeFrom: m(1),
        ),
        () => repo.create(name: ' ', kind: AccountKind.debt, activeFrom: m(1)),
        () => repo.create(
          name: 'Deuda',
          kind: AccountKind.debt,
          activeFrom: m(5),
          activeThrough: m(4),
        ),
        () => repo.changeLiquidity(a.id, m(1), Liquidity.medium),
        () => repo.correctHistoricalLiquidity(
          a.id,
          m(3),
          m(10),
          Liquidity.medium,
        ),
        () =>
            repo.correctHistoricalLiquidity(a.id, m(3), m(3), Liquidity.medium),
        () => repo.close(a.id, m(10)),
        () => repo.rename('missing', 'X'),
      ]) {
        await expectLater(action(), throwsA(isA<AccountFailure>()));
      }
      expect((await repo.history(a.id)).map((p) => p.id), before);
      final last = await repo.create(
        name: 'Último mes',
        kind: AccountKind.portfolio,
        activeFrom: Month(9999, 12),
        activeThrough: Month(9999, 12),
        liquidity: Liquidity.medium,
      );
      expect(
        (await repo.listForMonth(Month(9999, 12)))
            .where((a) => a.id == last.id)
            .single
            .liquidity,
        Liquidity.medium,
      );
      expect(() => Month(0, 1), throwsA(isA<AccountFailure>()));
      expect(() => Month.parse('2026-13-01'), throwsA(isA<AccountFailure>()));
      expect(() => Month.parse('2026-02-02'), throwsA(isA<AccountFailure>()));
    },
  );
  test('SQLite rechaza solapes INSERT/UPDATE, deuda, fechas, FK y límites', () async {
    final a = await asset();
    final d = await repo.create(
      name: 'Deuda',
      kind: AccountKind.debt,
      activeFrom: m(2),
    );
    await repo.changeLiquidity(a.id, m(6), Liquidity.medium);
    final periods = await repo.history(a.id);
    for (final sql in [
      "INSERT INTO account_liquidity_periods SELECT 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',account_id,'2026-03-01',NULL,liquidity,created_at,updated_at FROM account_liquidity_periods WHERE id='${periods.first.id}'",
      "UPDATE account_liquidity_periods SET from_month='2026-05-01' WHERE id='${periods.last.id}'",
      "UPDATE account_liquidity_periods SET account_id='${d.id}' WHERE id='${periods.last.id}'",
      "UPDATE account_liquidity_periods SET account_id='missing' WHERE id='${periods.last.id}'",
      "UPDATE account_liquidity_periods SET from_month='2026-01-01' WHERE id='${periods.first.id}'",
      "UPDATE account_liquidity_periods SET liquidity='invalid' WHERE id='${periods.first.id}'",
      "UPDATE account_liquidity_periods SET until_month=from_month WHERE id='${periods.first.id}'",
      "UPDATE accounts SET kind='debt' WHERE id='${a.id}'",
      "UPDATE accounts SET active_from='2026-13-01' WHERE id='${a.id}'",
      "UPDATE accounts SET active_through='2026-04-01' WHERE id='${a.id}'",
      "DELETE FROM accounts WHERE id='${a.id}'",
    ]) {
      await expectLater(repo.database.customStatement(sql), throwsA(anything));
    }
    expect((await repo.history(a.id)).length, 2);
  });
  test(
    'Baja conserva referencias y rechaza dejar movimientos/fotos fuera',
    () async {
      final a = await asset();
      final db = repo.database;
      await db.customStatement(
        "INSERT INTO movements(id,account_id,value_date,concept,amount_cents,created_at,updated_at) VALUES('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',?,'2026-05-31','Sintético',-100,'2026-01-01T00:00:00.000Z','2026-01-01T00:00:00.000Z')",
        [a.id],
      );
      await expectLater(repo.close(a.id, m(4)), throwsA(isA<AccountFailure>()));
      await SqliteWealthRepository(db).setValue(m(6), a.id, 0);
      await expectLater(repo.close(a.id, m(5)), throwsA(isA<AccountFailure>()));
      expect((await repo.history(a.id)).single.until, isNull);
      await repo.close(a.id, m(6));
      expect(
        (await db.customSelect('SELECT * FROM movements').get()).length,
        1,
      );
      expect(
        (await db.customSelect('SELECT * FROM wealth_values').get()).length,
        1,
      );
      expect(await classification(a.id, 6), Liquidity.liquid);
    },
  );
  test(
    'Fallo al insertar tras dividir revierte periodos y alta completa',
    () async {
      final a = await asset();
      final before = (await repo.history(a.id)).single;
      await repo.database.customStatement(
        "CREATE TEMP TRIGGER fail_liquidity BEFORE INSERT ON account_liquidity_periods WHEN NEW.liquidity='medium' BEGIN SELECT RAISE(ABORT,'synthetic_failure'); END",
      );
      await expectLater(
        repo.changeLiquidity(a.id, m(5), Liquidity.medium),
        throwsA(anything),
      );
      final after = (await repo.history(a.id)).single;
      expect(after.id, before.id);
      expect(after.from.value, before.from.value);
      expect(after.until, isNull);
      expect(await classification(a.id, 6), Liquidity.liquid);
      await expectLater(
        repo.create(
          name: 'Alta fallida',
          kind: AccountKind.account,
          activeFrom: m(2),
          liquidity: Liquidity.medium,
        ),
        throwsA(anything),
      );
      expect((await repo.listForMonth(m(3))).length, 1);
      final plan = await repo.database
          .customSelect(
            'EXPLAIN QUERY PLAN SELECT * FROM account_liquidity_periods WHERE account_id=? AND from_month<=?',
            variables: [Variable(a.id), Variable(m(6).value)],
          )
          .get();
      expect(
        plan.any((r) => r.read<String>('detail').contains('INDEX')),
        isTrue,
      );
    },
  );
  test(
    'Una base con huecos no se abre ni se interpreta como clasificación actual',
    () async {
      final a = await asset();
      await repo.changeLiquidity(a.id, m(6), Liquidity.medium);
      final p = (await repo.history(a.id)).last;
      await repo.database.customStatement(
        'DELETE FROM account_liquidity_periods WHERE id=?',
        [p.id],
      );
      await expectLater(
        repo.listForMonth(m(3)),
        throwsA(isA<AccountFailure>()),
      );
      await store.close();
      final bytes = File(store.databasePath!).readAsBytesSync();
      await expectLater(store.open(), throwsA(isA<DatabaseFailure>()));
      expect(File(store.databasePath!).readAsBytesSync(), bytes);
    },
  );
  test(
    'v2 a v4 preserva categorías, UUID, revisión; rollback y snapshot exacto',
    () async {
      final path = store.databasePath!;
      await store.close();
      final previous = sqlite3.open(path);
      usePublishedV6CategoryTriggers(previous);
      for (final sql in [
        ...movementSchemaObjects,
        ...budgetSchemaObjects,
        ...wealthSchemaObjects,
      ].reversed) {
        final match = RegExp(r'CREATE (TABLE|INDEX|TRIGGER)\s+"?([a-z_]+)')
            .firstMatch(sql)!;
        previous.execute('DROP ${match[1]} "${match[2]}"');
      }
      // Fixture anterior genuino, reconstruido solo por esta prueba.
      for (final name in [
        'account_period_bounds',
        'account_kind_immutable',
        'liquidity_insert',
        'liquidity_update',
      ]) {
        previous.execute('DROP TRIGGER $name');
      }
      previous.execute('DROP TABLE account_liquidity_periods');
      previous.execute('DROP TABLE accounts');
      previous.execute(
        "INSERT INTO categories VALUES('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',NULL,'Histórica',1,0,'t','t')",
      );
      previous.execute('UPDATE database_state SET revision=23');
      previous.execute('PRAGMA user_version=2');
      final dataset = previous
          .select('SELECT dataset_id FROM database_state')
          .single['dataset_id'];
      validateExistingDatabase(previous);
      previous.close();
      final failing = FailedAccountMigration(
        NativeDatabase(File(path), setup: configureConnection),
      );
      await expectLater(
        failing.customSelect('SELECT 1').get(),
        throwsStateError,
      );
      await failing.close();
      final unchanged = sqlite3.open(path);
      validateExistingDatabase(unchanged);
      expect(readSchemaVersion(unchanged), 2);
      unchanged.close();
      final db = await store.open();
      expect(
        (await db.select(db.databaseState).getSingle()).datasetId,
        dataset,
      );
      expect((await db.select(db.databaseState).getSingle()).revision, 23);
      expect(
        (await db.customSelect('SELECT name FROM categories').getSingle())
            .read<String>('name'),
        'Histórica',
      );
      final backup = sqlite3.open(store.migrationBackupPath!);
      expect(readSchemaVersion(backup), 2);
      backup.close();
      final snap = jsonDecode(
        File('drift_schemas/autofinance/drift_schema_v8.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final expected = sqlite3.openInMemory();
      for (final group in snap['fixed_sql'] as List) {
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
        actual.map((r) => normalizeSchema(r.read<String>('sql'))),
        expected
            .select(
              "SELECT sql FROM sqlite_master WHERE name NOT GLOB 'sqlite_*' ORDER BY name",
            )
            .map((r) => normalizeSchema(r['sql'] as String)),
      );
      expected.close();
    },
  );
}
