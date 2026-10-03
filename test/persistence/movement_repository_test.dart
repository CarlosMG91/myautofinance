import 'published_schema_fixture.dart';

import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalDatabaseStore store;
  late SqliteMovementRepository repo;
  late SqliteImportBatchRepository batches;
  late String accountId, categoryId;
  MovementInput input({
    int amount = -1000,
    String? account,
    String? category,
    String? discretion,
  }) => MovementInput(
    accountId: account ?? accountId,
    valueDate: ValueDate(2026, 1, 15),
    concept: 'Café',
    amountCents: amount,
    categoryId: category,
    discretion: discretion,
  );
  Future<List<MovementRecord>> all() =>
      repo.list(from: ValueDate(2026, 1, 1), until: ValueDate(2026, 2, 1));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('movements-synthetic-');
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    final db = await store.open();
    repo = SqliteMovementRepository(db);
    batches = SqliteImportBatchRepository(db);
    accountId = (await SqliteAccountRepository(db).create(
      name: 'Cuenta',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    )).id;
    categoryId = (await SqliteCategoryRepository(db).create(name: 'Ocio')).id;
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  test(
    'CRUD, duplicados, filtros, paginación y discrecionalidad tras reapertura',
    () async {
      final a = await repo.create(
        input(category: categoryId, discretion: 'Necesario'),
      );
      await repo.create(input(category: categoryId, discretion: 'Necesario'));
      await repo.create(input(amount: 500));
      expect((await all()).length, 3);
      final page = await repo.list(
        from: ValueDate(2026, 1, 1),
        until: ValueDate(2026, 2, 1),
        accountId: accountId,
        categoryId: categoryId,
        limit: 1,
      );
      final next = await repo.list(
        from: ValueDate(2026, 1, 1),
        until: ValueDate(2026, 2, 1),
        categoryId: categoryId,
        after: MovementCursor(page.single.data.valueDate, page.single.id),
      );
      expect(next.length, 1);
      expect(next.single.id, isNot(page.single.id));
      expect(
        (await repo.list(
          from: ValueDate(2026, 1, 1),
          until: ValueDate(2026, 2, 1),
          unclassifiedOnly: true,
        )).length,
        1,
      );
      await repo.edit(a.id, input(amount: 200, category: categoryId));
      expect((await repo.get(a.id))!.data.discretion, 'Necesario');
      await store.close();
      repo = SqliteMovementRepository(await store.open());
      expect((await repo.get(a.id))!.data.amountCents, 200);
      await repo.setDiscretion(a.id, null);
      expect((await repo.get(a.id))!.data.discretion, isNull);
      await repo.delete(a.id);
      expect(await repo.get(a.id), isNull);
    },
  );
  test('Lote atómico, identidad por ordinal, SHA repetida y borrado conserva procedencia', () async {
    final hash = 'a' * 64;
    final batch = await batches.create(
      sha256: hash,
      source: ImportSource.historicalCsv,
      originalName: 'sintetico.csv',
      contractVersion: '1',
      movements: [
        ImportedMovement(2, input(discretion: 'Opcional')),
        ImportedMovement(3, input(discretion: 'Opcional')),
      ],
    );
    final rows = await all();
    expect(rows.length, 2);
    expect(rows.map((m) => m.sourceOrdinal).toSet(), {2, 3});
    expect(rows.map((m) => m.batchId).toSet(), {batch.id});
    final edited = await repo.edit(rows.first.id, input(amount: 300));
    expect(edited.importRowId, rows.first.importRowId);
    expect(edited.data.discretion, 'Opcional');
    await repo.delete(rows.first.id);
    await expectLater(
      batches.create(
        sha256: hash,
        source: ImportSource.bankXls,
        originalName: 'otro.xls',
        contractVersion: '1',
        movements: [ImportedMovement(2, input())],
      ),
      throwsA(isA<MovementFailure>()),
    );
    expect(
      (await repo.database.customSelect('SELECT * FROM import_rows').get())
          .length,
      2,
    );
    await expectLater(
      batches.create(
        sha256: 'b' * 64,
        source: ImportSource.bankXls,
        originalName: 'error.xls',
        contractVersion: '1',
        movements: [
          ImportedMovement(2, input()),
          ImportedMovement(3, input(account: 'missing')),
        ],
      ),
      throwsA(isA<MovementFailure>()),
    );
    expect(await batches.getByFingerprint('b' * 64), isNull);
    expect((await all()).length, 1);
    await expectLater(
      batches.create(
        sha256: 'c' * 64,
        source: ImportSource.bankXls,
        originalName: 'error.xls',
        contractVersion: '1',
        movements: [ImportedMovement(2, input()), ImportedMovement(2, input())],
      ),
      throwsA(isA<MovementFailure>()),
    );
  });
  test('Dominio y SQLite rechazan importes, fechas, cuenta y cambios de procedencia', () async {
    for (final data in [
      input(amount: 0),
      input(account: 'missing'),
      input(category: 'missing'),
    ]) {
      await expectLater(repo.create(data), throwsA(isA<MovementFailure>()));
    }
    expect(() => ValueDate(2026, 2, 29), throwsA(isA<MovementFailure>()));
    final a = await repo.create(input());
    for (final assignment in [
      "amount_cents=0",
      "amount_cents=1.5",
      "value_date='2026-02-30'",
      "account_id='missing'",
      "import_row_id='missing'",
      "id='invalid'",
      "concept=' '",
    ]) {
      await expectLater(
        repo.database.customStatement(
          'UPDATE movements SET $assignment WHERE id=?',
          [a.id],
        ),
        throwsA(anything),
      );
    }
    await expectLater(
      repo.database.customStatement(
        "UPDATE accounts SET active_from='2026-02-01' WHERE id=?",
        [accountId],
      ),
      throwsA(anything),
    );
    expect((await repo.get(a.id))!.data.amountCents, -1000);
  });
  test('v3 migra a v4 preservando datos y snapshot exacto', () async {
    await store.close();
    final file = File(store.databasePath!);
    final raw = sqlite3.open(file.path);
    usePublishedV6CategoryTriggers(raw);
    for (final sql in [
      ...movementSchemaObjects,
      ...budgetSchemaObjects,
      ...wealthSchemaObjects,
    ].reversed) {
      final name = RegExp(r'CREATE (?:TABLE|INDEX|TRIGGER)\s+"?([a-z_]+)')
          .firstMatch(sql)![1]!;
      final type = sql.startsWith('CREATE TABLE')
          ? 'TABLE'
          : sql.startsWith('CREATE INDEX')
          ? 'INDEX'
          : 'TRIGGER';
      raw.execute('DROP $type "$name"');
    }
    raw.execute('PRAGMA user_version=3');
    raw.execute('UPDATE database_state SET revision=17');
    raw.close();
    final db = await store.open();
    expect((await db.select(db.databaseState).getSingle()).revision, 17);
    expect((await SqliteAccountRepository(db).get(accountId))!.id, accountId);
    final snapshot = jsonDecode(
      File('drift_schemas/autofinance/drift_schema_v7.json').readAsStringSync(),
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
  });
  test('Edición no altera fotos; vigencia, tipo, historia y procedencia protegidos', () async {
    final db = repo.database;
    await SqliteWealthRepository(db)
        .setValue(Month(2026, 1), accountId, 900000);
    final accounts = SqliteAccountRepository(db);
    for (final kind in [AccountKind.debt, AccountKind.portfolio]) {
      final a = await accounts.create(
        name: 'Otra',
        kind: kind,
        activeFrom: Month(2026, 1),
        liquidity: kind == AccountKind.debt ? null : Liquidity.medium,
      );
      await expectLater(
        repo.create(input(account: a.id)),
        throwsA(isA<MovementFailure>()),
      );
    }
    final hash = 'd' * 64;
    await batches.create(
      sha256: hash,
      source: ImportSource.bankXls,
      originalName: 'sintetico.xls',
      contractVersion: '1',
      movements: [
        ImportedMovement(
          2,
          input(category: categoryId, discretion: 'Necesario'),
        ),
      ],
    );
    final a = (await all()).single;
    await SqliteCategoryRepository(db).setArchived(categoryId, archived: true);
    await repo.edit(
      a.id,
      input(category: categoryId, amount: 9223372036854775807),
    );
    await repo.edit(
      a.id,
      input(category: categoryId, amount: -9223372036854775808),
    );
    expect((await repo.get(a.id))!.data.amountCents, -9223372036854775808);
    await expectLater(
      repo.create(input(category: categoryId)),
      throwsA(isA<MovementFailure>()),
    );
    await accounts.close(accountId, Month(2026, 1));
    await repo.edit(a.id, input(category: categoryId, amount: 500));
    await expectLater(
      repo.create(
        MovementInput(
          accountId: accountId,
          valueDate: ValueDate(2026, 2, 1),
          concept: 'Fuera',
          amountCents: 100,
        ),
      ),
      throwsA(isA<MovementFailure>()),
    );
    for (final sql in [
      "UPDATE import_rows SET source_ordinal=4",
      "DELETE FROM import_rows",
      "UPDATE import_batches SET content_sha256='${'e' * 64}'",
      "DELETE FROM import_batches",
      "UPDATE movements SET import_row_id=NULL",
    ]) {
      await expectLater(db.customStatement(sql), throwsA(anything));
    }
    expect(
      (await db
              .customSelect('SELECT amount_cents FROM wealth_values')
              .getSingle())
          .read<int>('amount_cents'),
      900000,
    );
    expect(
      (await db.customSelect('SELECT month FROM wealth_snapshots').getSingle())
          .read<String>('month'),
      '2026-01-01',
    );
    final plan = await db
        .customSelect(
          "EXPLAIN QUERY PLAN SELECT id FROM movements WHERE account_id='synthetic' AND value_date>='2026-01-01' AND value_date<'2026-02-01' ORDER BY value_date,id",
          variables: [],
        )
        .get();
    expect(
      plan.map((r) => r.data.toString()).join(),
      contains('movements_account_date'),
    );
  });
}
