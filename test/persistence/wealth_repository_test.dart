import 'published_schema_fixture.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalDatabaseStore store;
  late SqliteWealthRepository repo;
  late SqliteAccountRepository accounts;
  final jan = Month(2026, 1), feb = Month(2026, 2);
  Future<AccountRecord> account(
    String name, {
    AccountKind kind = AccountKind.account,
    Liquidity liquidity = Liquidity.liquid,
    Month? from,
  }) => accounts.create(
    name: name,
    kind: kind,
    activeFrom: from ?? jan,
    liquidity: kind == AccountKind.debt ? null : liquidity,
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wealth-synthetic-');
    store = LocalDatabaseStore(supportDirectory: () async => dir);
    final db = await store.open();
    repo = SqliteWealthRepository(db);
    accounts = SqliteAccountRepository(db);
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  test(
    'Caso D: ausencia, parcial, cero, deuda, corrección y liquidez histórica',
    () async {
      final main = await account('Principal'),
          savings = await account('Ahorro');
      final portfolio = await account(
        'Cartera',
        kind: AccountKind.portfolio,
        liquidity: Liquidity.medium,
      );
      final debt = await account('Deuda', kind: AccountKind.debt);
      expect((await repo.read(jan)).status, WealthSnapshotStatus.absent);
      expect((await repo.read(jan)).pending.length, 4);
      await repo.prepare(jan);
      expect((await repo.read(jan)).status, WealthSnapshotStatus.absent);
      for (final entry in {
        main.id: 600000,
        savings.id: 300000,
        portfolio.id: 1000000,
        debt.id: 500000,
      }.entries) {
        await repo.setValue(jan, entry.key, entry.value);
      }
      final january = await repo.read(jan);
      expect(january.status, WealthSnapshotStatus.complete);
      expect(january.pending, isEmpty);
      expect(
        january.values
            .where((v) => v.account.liquidity == Liquidity.liquid)
            .fold<int>(0, (s, v) => s + v.amountCents),
        900000,
      );
      expect(
        january.values
            .singleWhere((v) => v.account.kind == AccountKind.debt)
            .amountCents,
        500000,
      );
      expect((await repo.read(feb)).status, WealthSnapshotStatus.absent);
      await repo.setValue(feb, main.id, 620000);
      await repo.setValue(feb, debt.id, 480000);
      final partial = await repo.read(feb);
      expect(partial.status, WealthSnapshotStatus.incomplete);
      expect(
        partial.pending.map((a) => a.id),
        unorderedEquals([savings.id, portfolio.id]),
      );
      await repo.setValue(feb, savings.id, 0);
      await repo.setValue(feb, portfolio.id, 1050000);
      final before = await repo.read(feb);
      expect(before.status, WealthSnapshotStatus.complete);
      await accounts.changeLiquidity(portfolio.id, feb, Liquidity.liquid);
      expect(
        (await repo.read(jan)).values
            .singleWhere((v) => v.account.id == portfolio.id)
            .account
            .liquidity,
        Liquidity.medium,
      );
      expect(
        (await repo.read(feb)).values
            .singleWhere((v) => v.account.id == portfolio.id)
            .account
            .liquidity,
        Liquidity.liquid,
      );
      await accounts.correctHistoricalLiquidity(
        portfolio.id,
        feb,
        Month(2026, 3),
        Liquidity.medium,
      );
      expect(
        (await repo.read(feb)).values
            .singleWhere((v) => v.account.id == portfolio.id)
            .amountCents,
        1050000,
      );
      await repo.setValue(feb, main.id, 650000);
      final after = await repo.read(feb);
      expect(after.snapshotId, before.snapshotId);
      expect(after.month.value, '2026-02-01');
      expect(
        after.values.singleWhere((v) => v.account.id == main.id).id,
        before.values.singleWhere((v) => v.account.id == main.id).id,
      );
      expect(
        after.values.singleWhere((v) => v.account.id == main.id).amountCents,
        650000,
      );
      await store.close();
      repo = SqliteWealthRepository(await store.open());
      expect((await repo.read(feb)).status, WealthSnapshotStatus.complete);
      await repo.deleteValue(feb, savings.id);
      expect((await repo.read(feb)).status, WealthSnapshotStatus.incomplete);
      await repo.deleteSnapshot(feb);
      expect((await repo.read(feb)).snapshotId, isNull);
      expect((await repo.read(jan)).status, WealthSnapshotStatus.complete);
    },
  );
  test('Alta/baja inclusivas, sin fichas, negativas y rollback', () async {
    await repo.prepare(jan);
    expect((await repo.read(jan)).status, WealthSnapshotStatus.absent);
    final a = await account('Nueva', from: feb);
    expect((await repo.read(jan)).pending, isEmpty);
    await expectLater(
      repo.setValue(jan, a.id, 50),
      throwsA(isA<WealthFailure>()),
    );
    await expectLater(
      repo.setValue(feb, a.id, -1),
      throwsA(isA<WealthFailure>()),
    );
    expect((await repo.read(feb)).snapshotId, isNull);
    await repo.setValue(feb, a.id, 0);
    await accounts.close(a.id, feb);
    expect((await repo.read(feb)).status, WealthSnapshotStatus.complete);
    expect((await repo.read(Month(2026, 3))).pending, isEmpty);
    expect(
      (await repo.read(Month(2026, 3))).status,
      WealthSnapshotStatus.absent,
    );
    await repo.setValue(feb, a.id, 9223372036854775807);
    expect(
      (await repo.read(feb)).values.single.amountCents,
      9223372036854775807,
    );
    await expectLater(
      repo.setValue(Month(2026, 3), a.id, 50),
      throwsA(isA<WealthFailure>()),
    );
    final b = await account('Con historia');
    await repo.setValue(Month(2026, 3), b.id, 10);
    await expectLater(
      accounts.close(b.id, feb),
      throwsA(isA<AccountFailure>()),
    );
    expect((await accounts.get(b.id))!.activeThrough, isNull);
  });
  test('SQL directo: unicidad, entero, mes fijo, FK y vigencia', () async {
    final a = await account('Cuenta');
    await repo.setValue(jan, a.id, 100);
    final photo = await repo.read(jan);
    for (final sql in [
      'UPDATE wealth_values SET amount_cents=-1',
      'UPDATE wealth_values SET amount_cents=1.5',
      "UPDATE wealth_values SET account_id='missing'",
      "UPDATE wealth_values SET snapshot_id='missing'",
      "UPDATE wealth_snapshots SET month='2026-02-01'",
      "UPDATE accounts SET active_from='2026-02-01'",
      "INSERT INTO wealth_values SELECT '11111111-2222-4333-8444-555555555555',snapshot_id,account_id,0,created_at,updated_at FROM wealth_values",
      "INSERT INTO wealth_snapshots SELECT '11111111-2222-4333-8444-555555555555',month,created_at,updated_at FROM wealth_snapshots",
      'DELETE FROM wealth_snapshots',
      'DELETE FROM accounts',
    ]) {
      await expectLater(repo.database.customStatement(sql), throwsA(anything));
    }
    await repo.prepare(feb);
    for (final month in ['2026-02-02', '2026-13-01', '0000-01-01']) {
      await expectLater(
        repo.database.customStatement(
          'UPDATE wealth_snapshots SET month=? WHERE month=?',
          [month, feb.value],
        ),
        throwsA(anything),
      );
    }
    expect((await repo.read(jan)).snapshotId, photo.snapshotId);
    expect((await repo.read(jan)).values.single.amountCents, 100);
    final plan = await repo.database
        .customSelect(
          "EXPLAIN QUERY PLAN SELECT * FROM wealth_values WHERE snapshot_id='x' AND account_id='y'",
        )
        .get();
    expect(plan.map((r) => r.read<String>('detail')).join(), contains('INDEX'));
  });
  test('Los movimientos no crean ni alteran fotos; lectura rechaza huecos de liquidez', () async {
    final a = await account('Cuenta');
    final movements = SqliteMovementRepository(repo.database);
    await movements.create(
      MovementInput(
        accountId: a.id,
        valueDate: ValueDate(2026, 1, 15),
        concept: 'Entrada sintética',
        amountCents: 10000,
      ),
    );
    expect((await repo.read(jan)).status, WealthSnapshotStatus.absent);
    await repo.setValue(jan, a.id, 20);
    await movements.create(
      MovementInput(
        accountId: a.id,
        valueDate: ValueDate(2026, 1, 16),
        concept: 'Salida sintética',
        amountCents: -1000,
      ),
    );
    expect((await repo.read(jan)).values.single.amountCents, 20);
    await repo.database.customStatement(
      'DELETE FROM account_liquidity_periods WHERE account_id=?',
      [a.id],
    );
    await expectLater(repo.read(jan), throwsA(isA<AccountFailure>()));
  });
  test(
    'v5 migra sin inventar fotos; respaldo y esquema exacto vigente',
    () async {
      final a = await account('Histórica');
      await store.close();
      final raw = sqlite3.open(store.databasePath!);
      usePublishedV6CategoryTriggers(raw);
      for (final sql in wealthSchemaObjects.reversed) {
        final m = RegExp(r'CREATE (TABLE|INDEX|TRIGGER)\s+"?([a-z_]+)')
            .firstMatch(sql)!;
        raw.execute('DROP ${m[1]} "${m[2]}"');
      }
      raw.execute('UPDATE database_state SET revision=37');
      raw.execute('PRAGMA user_version=5');
      raw.close();
      repo = SqliteWealthRepository(await store.open());
      expect((await repo.read(jan)).status, WealthSnapshotStatus.absent);
      expect((await repo.read(jan)).pending.single.id, a.id);
      expect(
        (await repo.database.select(repo.database.databaseState).getSingle())
            .revision,
        37,
      );
      final backup = sqlite3.open(store.migrationBackupPath!);
      validateExistingDatabase(backup);
      expect(readSchemaVersion(backup), 5);
      backup.close();
      final expected = sqlite3.openInMemory();
      final snap = jsonDecode(
        File('drift_schemas/autofinance/drift_schema_v8.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      for (final group in snap['fixed_sql'] as List) {
        for (final item in group['sql'] as List) {
          expected.execute(item['sql'] as String);
        }
      }
      final actual = await repo.database
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
      await store.close();
      final current = sqlite3.open(store.databasePath!);
      validateExistingDatabase(current);
      expect(readSchemaVersion(current), localSchemaVersion);
      current.close();
    },
  );
}
