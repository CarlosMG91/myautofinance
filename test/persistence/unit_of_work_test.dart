import 'dart:io';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/database_failure.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalDatabaseStore store;
  late LocalDatabase db;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('work-synthetic-');
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    db = await store.open();
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<void> importAll({bool fail = false}) => db.run(() async {
    final category = await SqliteCategoryRepository(db)
        .create(name: 'Sintética');
    final account = await SqliteAccountRepository(db).create(
      name: 'Sintética',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    );
    await SqliteImportBatchRepository(db).create(
      sha256: 'a' * 64,
      source: ImportSource.historicalCsv,
      originalName: 'synthetic.csv',
      contractVersion: '1',
      movements: [
        ImportedMovement(
          2,
          MovementInput(
            accountId: account.id,
            valueDate: ValueDate(2026, 1, 2),
            concept: 'Sintético',
            amountCents: -100,
            categoryId: category.id,
          ),
        ),
      ],
      budgets: [
        ImportedBudget(
          3,
          BudgetInput(
            month: BudgetMonth(2026, 1),
            categoryId: category.id,
            amountCents: -200,
          ),
        ),
      ],
    );
    await SqliteWealthRepository(db).setValue(Month(2026, 1), account.id, 900);
    if (fail) throw StateError('fallo sintético');
  });

  test('referencias, lote, registros y revisión revierten juntos', () async {
    final before = await db.readState();
    await expectLater(importAll(fail: true), throwsStateError);
    for (final table in [
      'categories',
      'accounts',
      'account_liquidity_periods',
      'import_batches',
      'import_rows',
      'movements',
      'budgets',
      'wealth_snapshots',
      'wealth_values',
    ]) {
      expect(
        (await db.customSelect('SELECT count(*) AS n FROM $table').getSingle())
            .read<int>('n'),
        0,
        reason: table,
      );
    }
    expect((await db.readState()).revision, before.revision);
    await importAll();
    expect((await db.readState()).revision, 1);
    expect((await db.readState()).datasetId, before.datasetId);
    await store.close();
    db = await store.open();
    expect((await db.readState()).revision, 1);
  });

  test('lecturas, no-op y savepoint fallido no cuentan; concurrencia cuenta una vez', () async {
    final repo = SqliteCategoryRepository(db);
    final node = await repo.create(name: 'A');
    await db.run(() async {
      await repo.list();
      await repo.edit(node.id, name: 'A', parentId: null, isIncome: false);
      try {
        await db.run(() async {
          await repo.create(name: 'Revertida');
          throw StateError('savepoint');
        });
      } on StateError {
        /* Rolled back nested changes. */
      }
    });
    expect((await db.readState()).revision, 1);
    expect((await repo.list()).length, 1);
    await Future.wait([repo.create(name: 'B'), repo.create(name: 'C')]);
    expect((await db.readState()).revision, 3);
    await repo.setArchived(node.id, archived: true);
    expect((await db.readState()).revision, 4);
    await repo.setArchived(node.id, archived: true);
    expect((await db.readState()).revision, 4);
  });

  test('cada repositorio incrementa y reimportación no incrementa', () async {
    await importAll();
    final budgetRepo = SqliteBudgetRepository(db);
    final budget = (await budgetRepo.list(BudgetMonth(2026, 1))).single;
    await budgetRepo.delete(budget.id);
    expect((await db.readState()).revision, 2);
    final movements = SqliteMovementRepository(db);
    final movement = (await movements.list(
      from: ValueDate(2026, 1, 1),
      until: ValueDate(2026, 2, 1),
    )).single;
    await movements.setDiscretion(movement.id, 'Necesario');
    expect((await db.readState()).revision, 3);
    await SqliteWealthRepository(db)
        .setValue(Month(2026, 1), movement.data.accountId, 1000);
    expect((await db.readState()).revision, 4);
    await expectLater(
      SqliteImportBatchRepository(db).create(
        sha256: 'a' * 64,
        source: ImportSource.historicalCsv,
        originalName: 'synthetic.csv',
        contractVersion: '1',
        movements: [ImportedMovement(2, movement.data)],
      ),
      throwsA(isA<MovementFailure>()),
    );
    expect((await db.readState()).revision, 4);
  });

  test('fallo al guardar revisión revierte también datos', () async {
    await db.customStatement(
      'UPDATE database_state SET revision=9223372036854775807',
    );
    await expectLater(
      SqliteCategoryRepository(db).create(name: 'No confirmada'),
      throwsA(
        predicate<Object>(
          (e) => e.toString().contains('CHECK constraint failed'),
        ),
      ),
    );
    expect(await SqliteCategoryRepository(db).list(), isEmpty);
    expect((await db.readState()).revision, 9223372036854775807);
  });

  test(
    'fallo de almacenamiento de copia conserva base y permite reintento',
    () async {
      await importAll();
      final blocker = File('${directory.path}/sqlite/copies');
      await blocker.writeAsString('obstáculo sintético');
      await expectLater(
        store.createConsistentBackup(),
        throwsA(
          isA<DatabaseFailure>().having(
            (e) => e.code,
            'code',
            DatabaseFailureCode.backup,
          ),
        ),
      );
      expect((await db.readState()).revision, 1);
      expect(await SqliteCategoryRepository(db).list(), hasLength(1));
      await blocker.delete();
      expect((await store.createConsistentBackup()).state.revision, 1);
    },
  );

  test('copia concurrente espera el commit y captura su revisión', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final write = db.run(() async {
      await SqliteCategoryRepository(db).create(name: 'Concurrente');
      started.complete();
      await release.future;
    });
    await started.future;
    final pendingCopy = store.createConsistentBackup();
    release.complete();
    await write;
    final backup = await pendingCopy;
    expect(backup.state.revision, 1);
    final copy = sqlite3.open(backup.path, mode: OpenMode.readOnly);
    try {
      expect(
        copy.select('SELECT name FROM categories').single['name'],
        'Concurrente',
      );
    } finally {
      copy.close();
    }
  });

  test(
    'copia con WAL pendiente reabre con relaciones y revisión capturada',
    () async {
      await db.customStatement('PRAGMA journal_mode=WAL');
      await db.customStatement('PRAGMA wal_autocheckpoint=0');
      await importAll();
      expect(await File('${store.databasePath}-wal').length(), greaterThan(0));
      final backup = await store.createConsistentBackup();
      expect(backup.state.revision, 1);
      expect(backup.state.datasetId, (await db.readState()).datasetId);
      final raw = sqlite3.open(backup.path, mode: OpenMode.readOnly);
      try {
        validateExistingDatabase(raw);
        expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
        expect(
          raw
              .select(
                'SELECT m.id FROM movements m JOIN accounts a ON a.id=m.account_id JOIN categories c ON c.id=m.category_id JOIN import_rows r ON r.id=m.import_row_id JOIN import_batches b ON b.id=r.batch_id',
              )
              .length,
          1,
        );
        expect(
          raw
              .select(
                'SELECT v.id FROM wealth_values v JOIN wealth_snapshots s ON s.id=v.snapshot_id JOIN accounts a ON a.id=v.account_id',
              )
              .length,
          1,
        );
      } finally {
        raw.close();
      }
      await store.close();
      final reopened = LocalDatabase(
        NativeDatabase(File(backup.path), setup: configureConnection),
      );
      try {
        expect((await reopened.readState()).revision, 1);
      } finally {
        await reopened.close();
      }
      db = await store.open();
      await SqliteCategoryRepository(db).create(name: 'Posterior');
      expect((await db.readState()).revision, 2);
      expect(backup.state.revision, 1);
      final second = await store.createConsistentBackup();
      expect(second.path, isNot(backup.path));
      expect(second.state.revision, 2);
    },
  );

  test(
    'copia dentro de unidad de trabajo se rechaza sin alterar datos',
    () async {
      await expectLater(
        db.run(() async {
          await SqliteCategoryRepository(db).create(name: 'Revertida');
          await store.createConsistentBackup();
        }),
        throwsA(isA<DatabaseFailure>()),
      );
      expect((await db.readState()).revision, 0);
      expect(await SqliteCategoryRepository(db).list(), isEmpty);
      expect((await store.createConsistentBackup()).state.revision, 0);
    },
  );
}
