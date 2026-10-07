import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_history_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_preview_source.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import 'import_preview_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalDatabaseStore store;
  late LocalDatabase db;
  late SqliteImportBatchRepository batches;
  late SqliteImportHistoryRepository history;
  late String accountId, categoryId;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('history-synthetic-');
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    db = await store.open();
    batches = SqliteImportBatchRepository(db);
    history = SqliteImportHistoryRepository(db);
    accountId = (await SqliteAccountRepository(db).create(
      name: 'Cuenta',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    )).id;
    categoryId = (await SqliteCategoryRepository(
      db,
    ).create(name: 'Gastos', isIncome: false)).id;
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<ImportConfirmationRequest> request(ImportSession session) async {
    final review = await ValidatingImportPreviewer(
      SqliteImportPreviewSource(db),
    ).preview(session);
    return ImportConfirmationRequest(
      review: review,
      reviewedOverlapKeys: review.overlaps.map((o) => o.key).toSet(),
    );
  }

  Future<ImportBatch> confirm(ImportSession session) async =>
      (await batches.confirm(await request(session)) as ImportConfirmed).batch;

  Future<Map<String, Object?>> image() async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();
    return {
      for (final table in tables)
        table.read<String>(
          'name',
        ): (await db
                .customSelect(
                  'SELECT * FROM "${table.read<String>('name')}" ORDER BY rowid',
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

  test('Vacío, inexistentes y cursores inválidos no escriben', () async {
    final before = await image();
    expect((await history.listBatches()).items, isEmpty);
    expect((await history.listRows('ausente')).items, isEmpty);
    expect(await history.getBatch('ausente'), isNull);
    expect(await history.getRow('ausente'), isNull);
    for (final limit in [0, -1, 501]) {
      await expectLater(history.listBatches(limit: limit), throwsArgumentError);
      await expectLater(
        history.listRows('ausente', limit: limit),
        throwsArgumentError,
      );
    }
    await expectLater(
      history.listBatches(cursor: const ImportBatchCursor('')),
      throwsArgumentError,
    );
    await expectLater(
      history.listRows('a', cursor: const ImportRowCursor('b', 2)),
      throwsArgumentError,
    );
    await expectLater(
      history.listRows('a', cursor: const ImportRowCursor('a', 1)),
      throwsArgumentError,
    );
    expect(await image(), before);
  });

  test(
    'Metadatos, originales completos y enlaces actuales; reapertura',
    () async {
      final real = InterpretedMovement(
        sourceOrdinal: 2,
        originalFields: const [
          ImportOriginalField('importe', ' -92233720368547758.08 '),
          ImportOriginalField('dato', ' \n;"á '),
          ImportOriginalField('dato', ''),
        ],
        concept: ' Café ',
        discretion: ' Necesario ',
        amount: const ImportAmount.economic(-9223372036854775808),
        valueDate: ValueDate(2026, 1, 5),
        account: fixture.accountRef,
      );
      final session = fixture.draft([
        fixture.budget(ordinal: 20),
        real,
        fixture.budget(ordinal: 30, month: 2, amount: 0),
      ]);
      final batch = await confirm(session);
      await store.close();
      db = await store.open();
      history = SqliteImportHistoryRepository(db);
      final before = await image();
      final page = await history.listBatches();
      final metadata = page.items.single;
      expect(metadata.id, batch.id);
      expect(metadata.sha256, session.file.sha256);
      expect(metadata.originalName, 'sintetico.csv');
      expect(metadata.importedAt, batch.importedAt);
      expect(metadata.source, ImportSource.historicalCsv);
      expect(metadata.contractVersion, importContractVersion);
      expect(metadata.formatVersion, 'synthetic-1');
      expect(metadata.movementCount, 1);
      expect(metadata.budgetCount, 2);
      expect(page.next, isNull);
      final rows = (await history.listRows(batch.id)).items;
      expect(rows.map((r) => r.sourceOrdinal), [2, 20, 30]);
      final original = rows.first.original as InterpretedMovement;
      expect(original.originalFields.map((f) => f.name), [
        'importe',
        'dato',
        'dato',
      ]);
      expect(
        original.originalFields.map((f) => f.value),
        real.originalFields.map((f) => f.value),
      );
      expect(original.amount.originalCents, -9223372036854775808);
      expect(original.discretion, ' Necesario ');
      expect(original.account, fixture.accountRef);
      expect(original.category, isNull);
      expect(rows.first.currentMovement!.data.accountId, accountId);
      expect(rows.first.currentMovement!.data.categoryId, isNull);
      expect(rows.first.currentBudget, isNull);
      expect(rows.first.isDeleted, isFalse);
      final budget = rows[1].original as InterpretedBudget;
      expect(budget.amount.originalCents, 1000);
      expect(budget.amount.internalCents, -1000);
      expect(rows[1].currentBudget!.data.amountCents, -1000);
      expect(rows[2].currentBudget!.data.amountCents, 0);
      for (final row in rows) {
        final detail = (await history.getRow(row.id))!;
        expect(detail.batchId, batch.id);
        expect(detail.sourceOrdinal, row.sourceOrdinal);
        expect(
          detail.currentMovement?.importRowId ??
              detail.currentBudget?.importRowId,
          row.id,
        );
      }
      expect(await image(), before);
      expect(() => rows.add(rows.first), throwsUnsupportedError);
      expect(() => original.originalFields.clear(), throwsUnsupportedError);
    },
  );

  test('Corrección, borrado y repetición conservan origen y conteos', () async {
    final session = fixture.draft([
      fixture.real(),
      fixture.real(ordinal: 3),
      fixture.budget(ordinal: 4),
      fixture.budget(ordinal: 5, month: 2),
    ]);
    final batch = await confirm(session);
    final rows = (await history.listRows(batch.id)).items;
    final firstPage = await history.listRows(batch.id, limit: 1);
    await SqliteMovementRepository(db).edit(
      rows[0].currentMovement!.id,
      MovementInput(
        accountId: accountId,
        valueDate: ValueDate(2026, 3, 10),
        concept: 'Corregido',
        amountCents: 2500,
        categoryId: categoryId,
      ),
    );
    await SqliteMovementRepository(db).delete(rows[1].currentMovement!.id);
    await SqliteBudgetRepository(db).edit(
      rows[2].currentBudget!.id,
      BudgetInput(
        month: BudgetMonth(2026, 4),
        categoryId: categoryId,
        concept: 'Nueva partida',
        amountCents: -3000,
      ),
    );
    await SqliteBudgetRepository(db).delete(rows[3].currentBudget!.id);
    final before = await image();
    final current = (await history.listRows(batch.id, limit: 500)).items;
    expect(current[0].original!.concept, ' Café ');
    expect(current[0].original!.amount.internalCents, -1250);
    expect(current[0].currentMovement!.data.concept, 'Corregido');
    expect(current[0].currentMovement!.data.amountCents, 2500);
    expect(current[1].isDeleted, isTrue);
    expect(current[1].original, isNotNull);
    expect(current[2].original!.concept, 'Presupuesto');
    expect(current[2].currentBudget!.data.concept, 'Nueva partida');
    expect(current[3].isDeleted, isTrue);
    expect(current[3].original, isNotNull);
    final continuation = await history.listRows(
      batch.id,
      cursor: firstPage.next,
    );
    expect(continuation.items.map((r) => r.sourceOrdinal), [3, 4, 5]);
    expect(continuation.items.first.isDeleted, isTrue);
    final metadata = (await history.getBatch(batch.id))!;
    expect(metadata.movementCount, 2);
    expect(metadata.budgetCount, 2);
    expect(await image(), before);
    final renamed = fixture.draft(
      session.interpretation.rows,
      name: 'otro.csv',
    );
    expect(
      await batches.confirm(await request(renamed)),
      isA<ImportAlreadyImported>(),
    );
    expect(await image(), before);
    expect((await history.listBatches()).items.length, 1);
  });

  test('Todas las filas de una carga grande, sin truncar duplicados', () async {
    final batch = await confirm(
      fixture.draft([
        for (var ordinal = 2; ordinal < 1207; ordinal++)
          fixture.real(ordinal: ordinal),
      ]),
    );
    final before = await image();
    ImportRowCursor? cursor;
    final all = <ImportRowHistory>[];
    do {
      final page = await history.listRows(batch.id, limit: 137, cursor: cursor);
      all.addAll(page.items);
      cursor = page.next;
    } while (cursor != null);
    expect(all.length, 1205);
    expect(all.map((r) => r.sourceOrdinal), List.generate(1205, (i) => i + 2));
    expect(all.map((r) => r.currentMovement!.id).toSet().length, 1205);
    expect(
      all.every((r) => r.original!.originalFields.single.value == ' Café '),
      isTrue,
    );
    expect((await history.getBatch(batch.id))!.movementCount, 1205);
    expect(await image(), before);
    // SQLite usa la unicidad lote/ordinal y los índices de origen del destino.
    final plan = await db.customSelect(
      '''EXPLAIN QUERY PLAN SELECT r.id, m.id
      FROM import_rows r LEFT JOIN movements m ON m.import_row_id=r.id
      WHERE r.batch_id='x' AND r.source_ordinal>10 ORDER BY r.source_ordinal LIMIT 138''',
    ).get();
    expect(
      plan.map((r) => r.read<String>('detail')).join('\n'),
      contains('INDEX'),
    );
  });

  test(
    'Lotes paginados estables al confirmar otro archivo entre páginas',
    () async {
      final ids = <String>[];
      for (var i = 0; i < 107; i++) {
        final batch = await batches.create(
          sha256: i.toRadixString(16).padLeft(64, '0'),
          source: ImportSource.bankXls,
          originalName: 'sintetico-$i.xls',
          contractVersion: 'legacy-1',
          movements: [
            ImportedMovement(
              2,
              MovementInput(
                accountId: accountId,
                valueDate: ValueDate(2026, 1, 5),
                concept: 'Igual',
                amountCents: -100,
              ),
            ),
          ],
        );
        ids.add(batch.id);
      }
      final first = await history.listBatches(limit: 11);
      await confirm(fixture.draft([fixture.real()]));
      // El cursor guarda UUID, no un rowid que VACUUM pueda renumerar.
      await db.customStatement('VACUUM');
      final before = await image();
      final all = [...first.items];
      var cursor = first.next;
      while (cursor != null) {
        final page = await history.listBatches(limit: 11, cursor: cursor);
        all.addAll(page.items);
        cursor = page.next;
      }
      expect(all.map((b) => b.id), ids.reversed);
      expect(all.map((b) => b.id).toSet().length, 107);
      expect(all.every((b) => b.source == ImportSource.bankXls), isTrue);
      expect((await history.listBatches()).items.first.id, isNot(ids.last));
      final oldRow = (await history.listRows(ids.first)).items.single;
      expect(oldRow.original, isNull);
      expect(oldRow.currentMovement, isNotNull);
      expect((await history.getBatch(ids.first))!.formatVersion, isNull);
      expect(await image(), before);
      await SqliteMovementRepository(db).delete(oldRow.currentMovement!.id);
      final deleted = (await history.getRow(oldRow.id))!;
      expect(deleted.isDeleted, isTrue);
      expect(deleted.original, isNull);
      expect((await history.getBatch(ids.first))!.movementCount, 1);
    },
  );

  test(
    'Original bancario conserva selección global y versión del lector',
    () async {
      final session = ImportSession(
        file: ImportFile.fromBytes(
          bytes: [7, 8],
          fingerprint: const Sha256ImportFingerprint(),
          source: ImportSource.bankXls,
          originalName: 'sintetico.xls',
        ),
        interpretation: ImportInterpretation(
          formatVersion: 'banco-sintetico-1',
          rows: [
            fixture.real(
              account: const ImportAccountReference.selectedAccount(),
            ),
          ],
        ),
      );
      final review =
          await ValidatingImportPreviewer(SqliteImportPreviewSource(db))
              .preview(
                session,
                bindings: ImportReferenceBindings(
                  accounts: {
                    const ImportAccountReference.selectedAccount(): accountId,
                  },
                ),
              );
      final batch = (await batches.confirm(
        ImportConfirmationRequest(review: review),
      ) as ImportConfirmed).batch;
      final before = await image();
      final metadata = (await history.getBatch(batch.id))!;
      expect(metadata.source, ImportSource.bankXls);
      expect(metadata.formatVersion, 'banco-sintetico-1');
      final row = (await history.listRows(batch.id)).items.single;
      expect((row.original as InterpretedMovement).account.name, isNull);
      expect(row.currentMovement!.data.accountId, accountId);
      expect(await image(), before);
    },
  );

  test(
    'Revisión cancelada y confirmación fallida no aparecen en historial',
    () async {
      await confirm(fixture.draft([fixture.real()]));
      final before = await image();
      final cancelled = await request(
        fixture.draft([fixture.real()], bytes: [2]),
      );
      expect(cancelled.review.canRequestConfirmation, isTrue);
      expect(await image(), before);
      await db.customStatement(
        '''CREATE TEMP TRIGGER fail_history_synthetic
      BEFORE INSERT ON import_row_originals BEGIN SELECT RAISE(ABORT, 'sintético'); END''',
      );
      expect(await batches.confirm(cancelled), isA<ImportRejected>());
      expect((await history.listBatches()).items.length, 1);
      expect(await image(), before);
    },
  );
}
