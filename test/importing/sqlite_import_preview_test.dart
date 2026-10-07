import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_preview_source.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import 'import_preview_test.dart' as fixture;

void main() {
  late LocalDatabase db;
  late ValidatingImportPreviewer previewer;
  setUp(() async {
    db = LocalDatabase(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    await db.readState();
    previewer = ValidatingImportPreviewer(SqliteImportPreviewSource(db));
  });
  tearDown(() => db.close());

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

  Future<AccountRecord> seedAccount() => SqliteAccountRepository(db).create(
    name: 'Cuenta',
    kind: AccountKind.account,
    activeFrom: Month(2026, 1),
    liquidity: Liquidity.liquid,
  );

  test('Preparar altas, repetir y descartar revisión no escribe ninguna tabla ni revisión', () async {
    final before = await image();
    final session = fixture.draft([
      fixture.real(category: fixture.childRef),
      fixture.budget(category: fixture.childRef),
    ]);
    final pending = await previewer.preview(session);
    fixture.blocked(pending);
    final bindings = ImportReferenceBindings(
      newAccounts: {
        fixture.accountRef: ImportNewAccount(
          name: 'Cuenta sintética',
          activeFrom: Month(2026, 1),
          liquidity: Liquidity.liquid,
        ),
      },
      newCategories: {
        fixture.rootRef: const ImportNewCategory(
          name: 'Gastos',
          isIncome: false,
        ),
        fixture.childRef: ImportNewCategory(
          name: 'Compra',
          parent: ImportCategoryTarget.proposed(fixture.rootRef),
        ),
      },
    );
    for (var i = 0; i < 2; i++) {
      final review = await previewer.preview(session, bindings: bindings);
      expect(review.issues, isEmpty);
      expect(review.canRequestConfirmation, isTrue);
      ImportConfirmationRequest(review: review);
      expect(await image(), before);
    }
    expect((await SqliteAccountRepository(db).list()), isEmpty);
    expect((await SqliteCategoryRepository(db).list()), isEmpty);
    expect(
      await SqliteImportBatchRepository(db)
          .getByFingerprint(session.file.sha256),
      isNull,
    );
  });

  test('Base real: ambigüedades, asignación explícita y errores completos sin escrituras', () async {
    final first = await seedAccount();
    final second = await seedAccount();
    final categories = SqliteCategoryRepository(db);
    final root = await categories.create(name: 'Gastos', isIncome: false);
    await categories.create(name: 'Gastos', isIncome: true);
    final before = await image();
    final session = fixture.draft([
      fixture.real(category: fixture.rootRef),
      fixture.real(ordinal: 3, category: fixture.rootRef),
    ]);
    final pending = await previewer.preview(session);
    fixture.blocked(pending);
    expect(
      pending.pendingReferences.first.candidateIds,
      unorderedEquals([first.id, second.id]),
    );
    final ready = await previewer.preview(
      session,
      bindings: ImportReferenceBindings(
        accounts: {fixture.accountRef: second.id},
        categories: {fixture.rootRef: root.id},
      ),
    );
    expect(ready.canRequestConfirmation, isTrue);
    expect(ready.movementCount, 2);
    await categories.setArchived(root.id, archived: true);
    final archivedImage = await image();
    final rejected = await previewer.preview(session, bindings: ready.bindings);
    fixture.blocked(rejected);
    expect(rejected.issues.map((i) => i.sourceOrdinal), [2, 3]);
    expect(await image(), archivedImage);
    expect(before, isNot(archivedImage));
  });

  test('Consulta meses completos, solapamientos fuera de página y conflictos con cero archivado', () async {
    final account = await seedAccount();
    final categories = SqliteCategoryRepository(db);
    final root = await categories.create(name: 'Gastos', isIncome: false);
    final child = await categories.create(name: 'Compra', parentId: root.id);
    final session = fixture.draft([
      fixture.real(),
      fixture.real(ordinal: 4),
      fixture.budget(ordinal: 5),
    ]);
    final imported = await SqliteImportBatchRepository(db).create(
      sha256: fixture.draft([], bytes: [2]).file.sha256,
      source: ImportSource.historicalCsv,
      originalName: 'anterior.csv',
      contractVersion: 'synthetic-1',
      movements: [
        // Coincidencia deliberadamente después de las primeras 100 filas.
        for (var i = 0; i < 120; i++)
          ImportedMovement(
            i + 2,
            MovementInput(
              accountId: account.id,
              valueDate: ValueDate(2026, 1, 5),
              concept: i == 119 ? ' CAFÉ ' : 'A sintético $i',
              amountCents: -1250,
            ),
          ),
      ],
      budgets: [
        ImportedBudget(
          122,
          BudgetInput(
            month: BudgetMonth(2026, 1),
            categoryId: child.id,
            amountCents: 0,
          ),
        ),
      ],
    );
    await categories.setArchived(child.id, archived: true);
    final before = await image();
    final review = await previewer.preview(session);
    fixture.blocked(review);
    expect(review.overlaps.map((o) => o.sourceOrdinal), [2, 4]);
    expect(review.issues.single.code, ImportIssueCode.budgetConflict);
    expect(review.issues.single.sourceOrdinal, 5);
    final read = await SqliteImportPreviewSource(db).read(session);
    expect(read.movements.length, 120);
    expect(read.movements.every((m) => m.batchId == imported.id), isTrue);
    expect(await image(), before);
  });

  test('Mismos bytes renombrados no son otro archivo; corrección/borrado no se recrean', () async {
    final account = await seedAccount();
    final root = await SqliteCategoryRepository(db)
        .create(name: 'Gastos', isIncome: false);
    final session = fixture.draft([fixture.real(), fixture.budget()]);
    await SqliteImportBatchRepository(db).create(
      sha256: session.file.sha256,
      source: session.file.source,
      originalName: session.file.originalName,
      contractVersion: session.interpretation.formatVersion,
      movements: [
        ImportedMovement(
          2,
          fixture.real().toMovementInput(accountId: account.id),
        ),
      ],
      budgets: [
        ImportedBudget(3, fixture.budget().toBudgetInput(categoryId: root.id)),
      ],
    );
    final renamed = fixture.draft(
      session.interpretation.rows,
      name: 'otro-nombre.csv',
    );
    final before = await image();
    final review = await previewer.preview(renamed);
    expect(review.canRequestConfirmation, isTrue);
    expect(review.overlaps, isEmpty);
    expect(review.issues, isEmpty);
    expect(await image(), before);
    final budgets = SqliteBudgetRepository(db);
    final originalBudget = (await budgets.list(BudgetMonth(2026, 1))).single;
    await budgets.edit(
      originalBudget.id,
      BudgetInput(
        month: BudgetMonth(2026, 1),
        categoryId: root.id,
        amountCents: -2000,
      ),
    );
    final movements = SqliteMovementRepository(db);
    await movements.delete((await movements.readMonth(2026, 1)).single.id);
    final changed = await image();
    expect((await previewer.preview(renamed)).canRequestConfirmation, isTrue);
    expect(await image(), changed);
    // Distintos bytes reactivan la validación de conflictos con la base.
    fixture.blocked(
      await previewer.preview(
        fixture.draft(session.interpretation.rows, bytes: [3]),
      ),
    );
    expect(await image(), changed);
  });

  test('Conflicto entre planes y filas inválidas en base vacía conservan hasta temporales', () async {
    final before = await image();
    final rows = [
      fixture.real(ordinal: 1),
      fixture.budget(category: fixture.rootRef),
      fixture.budget(ordinal: 4, category: fixture.childRef),
    ];
    final review = await previewer.preview(
      fixture.draft(rows),
      bindings: ImportReferenceBindings(
        newAccounts: {
          fixture.accountRef: ImportNewAccount(
            name: 'Cuenta',
            activeFrom: Month(2026, 1),
            liquidity: Liquidity.liquid,
          ),
        },
        newCategories: {
          fixture.rootRef: const ImportNewCategory(
            name: 'Gastos',
            isIncome: false,
          ),
          fixture.childRef: ImportNewCategory(
            name: 'Compra',
            parent: ImportCategoryTarget.proposed(fixture.rootRef),
          ),
        },
      ),
    );
    fixture.blocked(review);
    expect(
      review.issues.any((i) => i.code == ImportIssueCode.invalidOrdinal),
      isTrue,
    );
    expect(
      review.issues
          .where((i) => i.code == ImportIssueCode.budgetConflict)
          .length,
      2,
    );
    expect(await image(), before);
  });
}
