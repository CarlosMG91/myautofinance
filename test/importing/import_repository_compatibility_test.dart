import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import 'import_contract_test.dart' as example;

void main() {
  late LocalDatabase db;
  late SqliteImportBatchRepository batches;
  setUp(() async {
    db = LocalDatabase(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    batches = SqliteImportBatchRepository(db);
    await db.readState();
  });
  tearDown(() => db.close());

  Future<Map<String, Object?>> snapshot() async {
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
    };
  }

  test(
    'Sesión y previsualización conservan todas las tablas y revisión SQLite',
    () async {
      final before = await snapshot();
      final source = example.file();
      final adapter = example.ExampleImportAdapter();
      final draft = ImportSession(
        file: source,
        interpretation: await adapter.interpret(source),
      );
      final previewer = example.ExamplePreviewer(() async {
        return await batches.getByFingerprint(source.sha256) != null;
      });
      final review = await previewer.preview(draft);
      expect(review.canRequestConfirmation, isFalse);
      expect(await snapshot(), before);
      expect(await batches.getByFingerprint(source.sha256), isNull);
    },
  );

  test(
    'Entradas tipadas reutilizan lote mixto, signos y ordinales existentes',
    () async {
      final account = await SqliteAccountRepository(db).create(
        name: 'Cuenta sintética',
        kind: AccountKind.account,
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      );
      final category = await SqliteCategoryRepository(db)
          .create(name: 'Alimentación');
      final rows = [
        example.movement(),
        example.movement(ordinal: 3),
        example.budget(ordinal: 4),
      ];
      final draft = example.session(rows);
      final state = await db.readState();
      final batch = await batches.create(
        sha256: draft.file.sha256,
        source: draft.file.source,
        originalName: draft.file.originalName,
        contractVersion: draft.interpretation.formatVersion,
        movements: [
          for (final row in rows.whereType<InterpretedMovement>())
            ImportedMovement(
              row.sourceOrdinal,
              row.toMovementInput(accountId: account.id),
            ),
        ],
        budgets: [
          for (final row in rows.whereType<InterpretedBudget>())
            ImportedBudget(
              row.sourceOrdinal,
              row.toBudgetInput(categoryId: category.id),
            ),
        ],
      );
      final movements = await SqliteMovementRepository(db).readMonth(2026, 1);
      final budgets = await SqliteBudgetRepository(db)
          .list(BudgetMonth(2026, 1));
      expect(movements.length, 2);
      expect(movements.map((r) => r.sourceOrdinal), unorderedEquals([2, 3]));
      expect(
        movements.every(
          (r) => r.data.categoryId == null && r.data.amountCents == -1250,
        ),
        isTrue,
      );
      expect(budgets.single.data.amountCents, -1000);
      expect(budgets.single.sourceOrdinal, 4);
      expect((await db.readState()).revision, state.revision + 1);
      expect(
        (await batches.getByFingerprint(example.file(name: 'otro.csv').sha256))!
            .id,
        batch.id,
      );
      final after = await snapshot();
      await expectLater(
        batches.create(
          sha256: example.file(bytes: [4]).sha256,
          source: draft.file.source,
          originalName: 'vacio.csv',
          contractVersion: 'synthetic-1',
        ),
        throwsA(isA<MovementFailure>()),
      );
      expect(await snapshot(), after);
    },
  );
}
