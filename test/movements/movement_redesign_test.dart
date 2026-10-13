import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Contador/subtotal globales: duplicados legítimos, neto cero y páginas',
    () async {
      final db = LocalDatabase(
        NativeDatabase.memory(setup: configureConnection),
      );
      addTearDown(db.close);
      final account = await SqliteAccountRepository(db).create(
        name: 'Cuenta de prueba',
        kind: AccountKind.account,
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      );
      await SqliteImportBatchRepository(db).create(
        sha256: 'd' * 64,
        source: ImportSource.historicalCsv,
        originalName: 'actividad-sintetica.csv',
        contractVersion: '1',
        movements: [
          for (final (i, amount) in [-1234, -1234, 2468].indexed)
            ImportedMovement(
              i + 2,
              MovementInput(
                accountId: account.id,
                valueDate: ValueDate(2026, 3, 15),
                concept: 'Actividad sintética',
                amountCents: amount,
                discretion: 'Texto original conservado',
              ),
            ),
        ],
        budgets: [],
      );
      final repo = SqliteMovementRepository(db);
      final seen = <String>{};
      MovementCursor? cursor;
      do {
        final page = await repo.readPage(
          from: ValueDate(2026, 3, 1),
          until: ValueDate(2026, 4, 1),
          after: cursor,
          limit: 1,
        );
        expect(page.totalCount, 3);
        expect(page.subtotalCents, 0);
        expect(page.records, hasLength(1));
        expect(seen.add(page.records.single.id), isTrue);
        cursor = page.nextCursor;
      } while (cursor != null);
      expect(seen, hasLength(3));
      final pending = await repo.readPendingPage(limit: 1);
      expect(pending.totalCount, 3);
      expect(pending.subtotalCents, 0);
      final second = await repo.readPendingPage(
        after: pending.nextCursor,
        limit: 1,
      );
      expect(second.totalCount, 3);
      expect(second.subtotalCents, 0);
      expect(second.records.single.id, isNot(pending.records.single.id));
      expect(
        second.records.single.data.discretion,
        'Texto original conservado',
      );
      expect(second.records.single.importRowId, isNotNull);
      expect(second.records.single.sourceOrdinal, isNotNull);
      final filtered = await repo.readPage(
        from: ValueDate(2026, 3, 1),
        until: ValueDate(2026, 4, 1),
        concept: 'No existe',
        limit: 1,
      );
      expect(filtered.totalCount, 0);
      expect(filtered.subtotalCents, 0);
      expect(filtered.records, isEmpty);
      final emptyPending = await repo.readPendingPage(
        query: PendingMovementQuery(concept: 'No existe'),
      );
      expect(emptyPending.totalCount, 0);
      expect(emptyPending.subtotalCents, 0);
      expect(emptyPending.records, isEmpty);
    },
  );
}
