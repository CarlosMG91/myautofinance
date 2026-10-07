import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_preview_source.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:sqlite3/sqlite3.dart';

import '../persistence/published_schema_fixture.dart';
import 'import_preview_test.dart' as fixture;

final class _FalseFingerprint implements ImportFingerprint {
  @override
  String ofBytes(List<int> bytes) => 'a' * 64;
}

final class _FailingImportMigration extends LocalDatabase {
  _FailingImportMigration(super.executor);
  @override
  MigrationStrategy get migration {
    final strategy = super.migration;
    return MigrationStrategy(
      onUpgrade: (m, from, to) => transaction(() async {
        await strategy.onUpgrade(m, from, to);
        throw StateError('Fallo sintético tras añadir originales');
      }),
      beforeOpen: strategy.beforeOpen,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalDatabaseStore store;
  late LocalDatabase db;
  late SqliteImportBatchRepository repo;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('confirm-synthetic-');
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    db = await store.open();
    repo = SqliteImportBatchRepository(db);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  ImportReferenceBindings plans() => ImportReferenceBindings(
    newAccounts: {
      fixture.accountRef: ImportNewAccount(
        name: 'Cuenta',
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      ),
    },
    // Hijo primero: se crean los antecesores por dependencia, no por el mapa.
    newCategories: {
      fixture.childRef: ImportNewCategory(
        name: 'Compra',
        parent: ImportCategoryTarget.proposed(fixture.rootRef),
      ),
      fixture.rootRef: const ImportNewCategory(name: 'Gastos', isIncome: true),
    },
  );

  ImportSession mixed({
    List<int> bytes = const [1],
    String name = 'sintetico.csv',
  }) => fixture.draft(
    [
      fixture.real(category: fixture.childRef),
      fixture.real(ordinal: 3, category: fixture.childRef),
      fixture.real(ordinal: 4),
      fixture.budget(ordinal: 5, category: fixture.childRef),
      fixture.budget(
        ordinal: 6,
        category: fixture.childRef,
        month: 2,
        amount: 0,
      ),
    ],
    bytes: bytes,
    name: name,
  );

  Future<ImportConfirmationRequest> request(
    ImportSession session, {
    ImportReferenceBindings? bindings,
  }) async {
    final review = await ValidatingImportPreviewer(
      SqliteImportPreviewSource(db),
    ).preview(session, bindings: bindings);
    expect(review.issues, isEmpty);
    expect(review.pendingReferences, isEmpty);
    return ImportConfirmationRequest(
      review: review,
      reviewedOverlapKeys: review.overlaps.map((o) => o.key).toSet(),
    );
  }

  Future<Map<String, Object?>> image() async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();
    return {
      for (final t in tables)
        t.read<String>(
          'name',
        ): (await db
                .customSelect(
                  'SELECT * FROM "${t.read<String>('name')}" ORDER BY rowid',
                )
                .get())
            .map((r) => r.data)
            .toList(),
      'local_mutation':
          (await db.customSelect('SELECT * FROM local_mutation').get())
              .map((r) => r.data)
              .toList(),
    };
  }

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT count(*) AS n FROM $table').getSingle())
          .read<int>('n');

  test(
    'Alta mixta atómica, originales ordenados, duplicados y una revisión',
    () async {
      final session = mixed();
      final before = await image();
      final req = await request(session, bindings: plans());
      expect(
        await image(),
        before,
      ); // Cancelar/descartar este objeto no escribe.
      final initial = await db.readState();
      final result = await repo.confirm(req) as ImportConfirmed;
      expect(result.movementCount, 3);
      expect(result.budgetCount, 2);
      expect(result.batch.formatVersion, 'synthetic-1');
      expect(result.batch.movementCount, 3);
      expect(result.batch.budgetCount, 2);
      expect((await db.readState()).revision, initial.revision + 1);
      expect(await count('accounts'), 1);
      expect(await count('account_liquidity_periods'), 1);
      expect(await count('categories'), 2);
      final categories = await SqliteCategoryRepository(db).list();
      expect(
        categories.every((c) => c.isIncome),
        isTrue,
      ); // no inferencia del signo.
      expect(await count('wealth_snapshots'), 0);
      final movements = await SqliteMovementRepository(db).readYear(2026);
      expect(movements.length, 3);
      expect(movements.map((m) => m.id).toSet().length, 3);
      expect(movements.where((m) => m.data.categoryId == null).length, 1);
      expect(movements.every((m) => m.data.amountCents == -1250), isTrue);
      expect(
        (await SqliteBudgetRepository(db).list(BudgetMonth(2026, 1)))
            .single
            .data
            .amountCents,
        -1000,
      );
      expect(
        (await SqliteBudgetRepository(db).list(BudgetMonth(2026, 2)))
            .single
            .data
            .amountCents,
        0,
      );
      final rows = await db.customSelect(
        '''SELECT r.source_ordinal,o.payload
      FROM import_rows r JOIN import_row_originals o ON o.import_row_id=r.id ORDER BY r.source_ordinal''',
      ).get();
      expect(rows.map((r) => r.read<int>('source_ordinal')), [2, 3, 4, 5, 6]);
      final payload = jsonDecode(rows[3].read<String>('payload')) as Map;
      expect(payload['originalCents'], '1000');
      expect(payload['internalCents'], '-1000');
      expect(payload['amountConvention'], 'historicalBudget');
      expect(payload.containsKey('accountName'), isFalse);
      expect(jsonDecode(rows.first.read<String>('payload'))['fields'], [
        {'name': 'concepto', 'value': ' Café '},
      ]);
      final contents = await image();
      await store.close();
      db = await store.open();
      repo = SqliteImportBatchRepository(db);
      final reopened = await image();
      expect(
        {...reopened}..remove('local_mutation'),
        {...contents}..remove('local_mutation'),
      );
      final copy = await store
          .createConsistentBackup(); // valida esquema y datos v8.
      final copied = sqlite3.open(copy.path, mode: OpenMode.readOnly);
      validateExistingDatabase(copied);
      expect(readSchemaVersion(copied), 8);
      copied.close();
    },
  );

  test(
    'Conserva columnas repetidas, espacios y texto sin archivo binario',
    () async {
      final real = fixture.real();
      final row = InterpretedMovement(
        sourceOrdinal: 2,
        originalFields: const [
          ImportOriginalField('dato', '  A\nB  '),
          ImportOriginalField('dato', '−12,50'),
        ],
        concept: real.concept,
        amount: real.amount,
        valueDate: real.valueDate,
        account: real.account,
        discretion: '  necesario  ',
      );
      final bindings = ImportReferenceBindings(
        newAccounts: plans().newAccounts,
      );
      expect(
        await repo.confirm(
          await request(fixture.draft([row]), bindings: bindings),
        ),
        isA<ImportConfirmed>(),
      );
      final original =
          (await db
                  .customSelect('SELECT payload FROM import_row_originals')
                  .getSingle())
              .read<String>('payload');
      expect(jsonDecode(original)['fields'], [
        {'name': 'dato', 'value': '  A\nB  '},
        {'name': 'dato', 'value': '−12,50'},
      ]);
      expect(jsonDecode(original)['discretion'], '  necesario  ');
      for (final table in [
        'import_batches',
        'import_rows',
        'import_batch_metadata',
        'import_row_originals',
      ]) {
        final columns = await db
            .customSelect('PRAGMA table_info($table)')
            .get();
        expect(columns.any((c) => c.read<String>('type') == 'BLOB'), isFalse);
      }
    },
  );

  test(
    'Repetición con otro nombre tras editar/borrar y archivar: cero altas',
    () async {
      final original = await request(mixed(), bindings: plans());
      final first = await repo.confirm(original) as ImportConfirmed;
      final movements = await SqliteMovementRepository(db).readYear(2026);
      await SqliteMovementRepository(db)
          .setDiscretion(movements.first.id, 'Corregido');
      await SqliteMovementRepository(db).delete(movements.last.id);
      for (final budget in await SqliteBudgetRepository(
        db,
      ).list(BudgetMonth(2026, 1))) {
        await SqliteBudgetRepository(db).delete(budget.id);
      }
      final root = (await SqliteCategoryRepository(
        db,
      ).list()).firstWhere((c) => c.parentId == null);
      await SqliteCategoryRepository(db).setArchived(root.id, archived: true);
      // Revisión previamente válida: las referencias obsoletas no preceden al SHA.
      final renamed = ImportConfirmationRequest(
        review: ImportReview(
          session: mixed(name: 'renombrado.csv'),
          bindings: original.review.bindings,
        ),
      );
      final before = await image();
      final result = await repo.confirm(renamed) as ImportAlreadyImported;
      expect(result.batch.id, first.batch.id);
      expect(result.batch.originalName, 'sintetico.csv');
      expect(
        result.batch.movementCount,
        3,
      ); // conteos originales incluso tras borrar.
      expect(await image(), before);
    },
  );

  test('Dos envíos simultáneos y reintento son un solo lote', () async {
    final req = await request(mixed(), bindings: plans());
    final results = await Future.wait([
      repo.confirm(req),
      SqliteImportBatchRepository(db).confirm(req),
    ]);
    expect(results.whereType<ImportConfirmed>().length, 1);
    expect(results.whereType<ImportAlreadyImported>().length, 1);
    final before = await image();
    expect(await repo.confirm(req), isA<ImportAlreadyImported>());
    expect(await image(), before);
    expect(await count('import_batches'), 1);
  });

  test('Origen bancario sin clasificar y procedencia inmutable', () async {
    final session = ImportSession(
      file: ImportFile.fromBytes(
        bytes: const [8],
        fingerprint: const Sha256ImportFingerprint(),
        source: ImportSource.bankXls,
        originalName: 'sintetico.xls',
      ),
      interpretation: ImportInterpretation(
        formatVersion: 'synthetic-bank-1',
        rows: [
          fixture.real(account: const ImportAccountReference.selectedAccount()),
        ],
      ),
    );
    final req = await request(
      session,
      bindings: ImportReferenceBindings(
        newAccounts: {
          const ImportAccountReference.selectedAccount():
              plans().newAccounts.values.single,
        },
      ),
    );
    final result = await repo.confirm(req) as ImportConfirmed;
    expect(result.batch.source, ImportSource.bankXls);
    expect(result.budgetCount, 0);
    expect(await count('categories'), 0);
    for (final table in ['import_row_originals', 'import_batch_metadata']) {
      final before = await image();
      final column = table == 'import_row_originals'
          ? 'payload'
          : 'format_version';
      await expectLater(
        db.writeTransaction(
          () => db.customStatement('UPDATE $table SET $column=$column'),
        ),
        throwsA(anything),
      );
      await expectLater(
        db.writeTransaction(() => db.customStatement('DELETE FROM $table')),
        throwsA(anything),
      );
      expect(await image(), before);
    }
  });

  test(
    'Bytes diferentes: avisos revisados conservan todas las filas',
    () async {
      final session = fixture.draft([fixture.real(), fixture.real(ordinal: 3)]);
      await repo.confirm(
        await request(
          session,
          bindings: ImportReferenceBindings(newAccounts: plans().newAccounts),
        ),
      );
      final req = await request(
        fixture.draft([fixture.real(), fixture.real(ordinal: 3)], bytes: [2]),
      );
      expect(req.review.overlaps.length, 4);
      final result = await repo.confirm(req);
      expect(result, isA<ImportConfirmed>());
      expect(await count('movements'), 4);
      expect(await count('import_rows'), 4);
      expect(await count('import_batches'), 2);
    },
  );

  test('Recalcula SHA real y rechaza huella falsa sin escrituras', () async {
    final good = mixed();
    final bad = ImportSession(
      file: ImportFile.fromBytes(
        bytes: good.file.bytes,
        fingerprint: _FalseFingerprint(),
        source: good.file.source,
        originalName: good.file.originalName,
      ),
      interpretation: good.interpretation,
    );
    final req = await request(bad, bindings: plans());
    final before = await image();
    final result = await repo.confirm(req) as ImportRejected;
    expect(result.issues.single.code, ImportIssueCode.invalidFile);
    expect(await image(), before);
  });

  for (final event in [
    'accountClosed',
    'categoryArchived',
    'categoryDeleted',
    'budgetConflict',
    'newOverlap',
  ]) {
    test('Revalida base cambiada desde revisión: $event', () async {
      final session = event == 'accountClosed'
          ? fixture.draft([
              fixture.real(month: 2, category: fixture.childRef),
              fixture.budget(category: fixture.childRef),
            ])
          : mixed();
      final a = await SqliteAccountRepository(db).create(
        name: 'Cuenta',
        kind: AccountKind.account,
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      );
      final c = await SqliteCategoryRepository(db)
          .create(name: 'Gastos', isIncome: false);
      final child = await SqliteCategoryRepository(db)
          .create(name: 'Compra', parentId: c.id);
      final req = await request(session);
      switch (event) {
        case 'accountClosed':
          await SqliteAccountRepository(db).close(a.id, Month(2026, 1));
        case 'categoryArchived':
          await SqliteCategoryRepository(db).setArchived(c.id, archived: true);
        case 'categoryDeleted':
          await db.writeTransaction(
            () => db.customStatement('DELETE FROM categories WHERE id=?', [
              child.id,
            ]),
          );
        case 'budgetConflict':
          await SqliteBudgetRepository(db).create(
            BudgetInput(
              month: BudgetMonth(2026, 1),
              categoryId: c.id,
              amountCents: 0,
            ),
          );
        case 'newOverlap':
          await repo.confirm(
            await request(fixture.draft([fixture.real()], bytes: [9])),
          );
      }
      final before = await image();
      final result = await repo.confirm(req) as ImportRejected;
      expect(result.issues, isNotEmpty);
      expect(result.issues.any((i) => i.sourceOrdinal != null), isTrue);
      expect(await image(), before);
      expect(await count('import_batches'), event == 'newOverlap' ? 1 : 0);
    });
  }

  for (final target in [
    'accounts',
    'categories',
    'import_batches',
    'import_rows',
    'movements',
    'budgets',
    'import_row_originals',
    'import_batch_metadata',
    'database_state',
  ]) {
    for (final action in ['ABORT', 'IGNORE']) {
      test('Rollback completo por $action en $target y reintento seguro', () async {
        final req = await request(mixed(), bindings: plans());
        final event = target == 'database_state' ? 'UPDATE' : 'INSERT';
        final when = target == 'database_state'
            ? 'WHEN NEW.revision>OLD.revision'
            : target == 'movements'
            ? "WHEN (SELECT count(*) FROM movements)=1"
            : '';
        await db.customStatement(
          "CREATE TEMP TRIGGER injected BEFORE $event ON $target $when BEGIN SELECT RAISE($action${action == 'ABORT' ? ",'synthetic failure'" : ''}); END",
        );
        final before = await image();
        expect(await repo.confirm(req), isA<ImportRejected>());
        expect(await image(), before);
        await db.customStatement('DROP TRIGGER injected');
        expect(await repo.confirm(req), isA<ImportConfirmed>());
        expect((await db.readState()).revision, 1);
        expect(await repo.confirm(req), isA<ImportAlreadyImported>());
      });
    }
  }

  test(
    'v7 migra sin inventar originales y conserva dataset/revisión/huella',
    () async {
      final req = await request(mixed(), bindings: plans());
      final first = await repo.confirm(req) as ImportConfirmed;
      final state = await db.readState();
      final path = store.databasePath!;
      await store.close();
      final raw = sqlite3.open(path);
      usePublishedV7ImportSchema(raw);
      raw.execute('PRAGMA user_version=7');
      validateExistingDatabase(raw);
      raw.close();
      final failing = _FailingImportMigration(
        NativeDatabase(File(path), setup: configureConnection),
      );
      await expectLater(failing.readState(), throwsStateError);
      await failing.close();
      final unchanged = sqlite3.open(path, mode: OpenMode.readOnly);
      validateExistingDatabase(unchanged);
      expect(readSchemaVersion(unchanged), 7);
      expect(
        unchanged
            .select('SELECT revision FROM database_state')
            .single['revision'],
        state.revision,
      );
      expect(
        unchanged
            .select('SELECT content_sha256 FROM import_batches')
            .single['content_sha256'],
        first.batch.sha256,
      );
      unchanged.close();
      db = await store.open();
      repo = SqliteImportBatchRepository(db);
      expect((await db.readState()).datasetId, state.datasetId);
      expect((await db.readState()).revision, state.revision);
      expect(await count('import_row_originals'), 0);
      expect(await count('import_batch_metadata'), 0);
      expect(
        (await repo.getByFingerprint(first.batch.sha256))!.formatVersion,
        isNull,
      );
      final before = await image();
      expect(await repo.confirm(req), isA<ImportAlreadyImported>());
      expect(await image(), before);
      final backup = sqlite3.open(
        store.migrationBackupPath!,
        mode: OpenMode.readOnly,
      );
      expect(readSchemaVersion(backup), 7);
      validateExistingDatabase(backup);
      backup.close();
    },
  );

  test('Otra conexión modifica referencias tras revisión; rechazo sin altas parciales', () async {
    final a = await SqliteAccountRepository(db).create(
      name: 'Cuenta',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    );
    final req = await request(fixture.draft([fixture.real(month: 2)]));
    final second = LocalDatabase(
      NativeDatabase(File(store.databasePath!), setup: configureConnection),
    );
    try {
      await SqliteAccountRepository(second).close(a.id, Month(2026, 1));
      final before = await image();
      final result = await repo.confirm(req) as ImportRejected;
      expect(result.issues.single.sourceOrdinal, 2);
      expect(await image(), before);
    } finally {
      await second.close();
    }
  });

  test(
    'Dos conexiones confirman el mismo SHA: una carga y otra repetición',
    () async {
      final req = await request(mixed(), bindings: plans());
      final second = LocalDatabase(
        NativeDatabase.createInBackground(
          File(store.databasePath!),
          setup: configureConnection,
        ),
      );
      try {
        await second.readState();
        await db.customStatement('PRAGMA busy_timeout=5000');
        await second.customStatement('PRAGMA busy_timeout=5000');
        final results = await Future.wait([
          repo.confirm(req),
          SqliteImportBatchRepository(second).confirm(req),
        ]);
        expect(results.whereType<ImportConfirmed>().length, 1);
        expect(results.whereType<ImportAlreadyImported>().length, 1);
        expect(await count('import_batches'), 1);
        expect(await count('accounts'), 1);
        expect(await count('import_rows'), 5);
        expect((await db.readState()).revision, 1);
      } finally {
        await second.close();
      }
    },
  );
}
