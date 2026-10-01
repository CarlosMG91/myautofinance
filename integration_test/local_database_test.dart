import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myautofinance/app/data/sqlite/database_failure.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'SQLite nativa en soporte privado: reapertura, FK y versión futura',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      // El fixture está aislado de la base real de la instalación.
      final fixtures = await Directory(p.join(support.path, 'sqlite-tests'))
          .create(recursive: true);
      final fixture = await fixtures.createTemp('synthetic-');
      final store = LocalDatabaseStore(supportDirectory: () async => fixture);
      try {
        final db = await store.open();
        expect(p.isWithin(support.path, store.databasePath!), isTrue);
        final initial = await db.select(db.databaseState).getSingle();
        final categories = SqliteCategoryRepository(db);
        final root = await categories.create(name: 'Ingresos', isIncome: true);
        final child = await categories.create(
          name: 'Salario',
          parentId: root.id,
        );
        final leaf = await categories.create(name: 'Extra', parentId: child.id);
        expect(leaf.isIncome, isTrue);
        await expectLater(
          categories.create(name: 'Cuarto nivel', parentId: leaf.id),
          throwsA(isA<CategoryFailure>()),
        );
        await categories.setArchived(root.id, archived: true);
        final accounts = SqliteAccountRepository(db);
        final account = await accounts.create(
          name: 'Cuenta sint?tica',
          kind: AccountKind.account,
          activeFrom: Month(2026, 1),
          liquidity: Liquidity.liquid,
        );
        await accounts.changeLiquidity(
          account.id,
          Month(2026, 6),
          Liquidity.medium,
        );
        await accounts.correctHistoricalLiquidity(
          account.id,
          Month(2026, 2),
          Month(2026, 4),
          Liquidity.illiquid,
        );
        await accounts.close(account.id, Month(2026, 8));
        final data = MovementInput(
          accountId: account.id,
          valueDate: ValueDate(2026, 1, 15),
          concept: 'Café sintético',
          amountCents: -1000,
          discretion: 'Opcional',
        );
        await SqliteImportBatchRepository(db).create(
          sha256: 'a' * 64,
          source: ImportSource.historicalCsv,
          originalName: 'sintetico.csv',
          contractVersion: '1',
          movements: [ImportedMovement(2, data), ImportedMovement(3, data)],
        );
        await db.customStatement('UPDATE database_state SET revision=42');
        await store.close();
        final reopened = await store.open();
        final state = await reopened.select(reopened.databaseState).getSingle();
        expect(state.datasetId, initial.datasetId);
        expect(state.revision, 42);
        final movements = await SqliteMovementRepository(reopened).list(
          from: ValueDate(2026, 1, 1),
          until: ValueDate(2026, 2, 1),
          accountId: account.id,
        );
        expect(movements.length, 2);
        expect(movements.map((m) => m.sourceOrdinal).toSet(), {2, 3});
        expect(movements.first.data.discretion, 'Opcional');
        final accountHistory = SqliteAccountRepository(reopened);
        expect(
          (await accountHistory.listForMonth(Month(2026, 1))).single.liquidity,
          Liquidity.liquid,
        );
        expect(
          (await accountHistory.listForMonth(Month(2026, 2))).single.liquidity,
          Liquidity.illiquid,
        );
        expect(
          (await accountHistory.listForMonth(Month(2026, 4))).single.liquidity,
          Liquidity.liquid,
        );
        expect(
          (await accountHistory.listForMonth(Month(2026, 8))).single.liquidity,
          Liquidity.medium,
        );
        expect(await accountHistory.listForMonth(Month(2026, 9)), isEmpty);
        expect(
          (await SqliteCategoryRepository(reopened).get(leaf.id))!.archived,
          isTrue,
        );
        expect(
          (await reopened.customSelect('PRAGMA foreign_keys').getSingle())
              .data
              .values
              .single,
          1,
        );
        await reopened.customStatement(
          'CREATE TEMP TABLE parent(id INTEGER PRIMARY KEY)',
        );
        await reopened.customStatement(
          'CREATE TEMP TABLE child(id INTEGER REFERENCES parent(id))',
        );
        await expectLater(
          reopened.customStatement('INSERT INTO child VALUES (9)'),
          throwsA(
            predicate<Object>(
              (error) =>
                  error.toString().contains('FOREIGN KEY constraint failed'),
            ),
          ),
        );
        await store.close();

        final file = File(store.databasePath!);
        final raw = sqlite3.open(file.path);
        raw.execute('PRAGMA user_version=99');
        raw.close();
        final before = file.readAsBytesSync();
        await expectLater(
          store.open(),
          throwsA(
            isA<DatabaseFailure>().having(
              (error) => error.code,
              'versión futura',
              DatabaseFailureCode.futureVersion,
            ),
          ),
        );
        expect(file.readAsBytesSync(), before);
      } finally {
        await store.close();
        await fixture.delete(recursive: true);
      }
    },
  );
}
