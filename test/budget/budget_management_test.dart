import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalDatabaseStore store;
  late SqliteBudgetRepository repository;
  late SqliteCategoryRepository categories;
  late BudgetManagement management;
  late String root, child, leaf, sibling, other;
  final jan = BudgetMonth(2026, 1), feb = BudgetMonth(2026, 2);

  void compose() {
    management = BudgetManagement(
      repository: repository,
      unitOfWork: repository.database,
    );
    categories = SqliteCategoryRepository(repository.database);
  }

  Future<BudgetRecord> create(
    String category, {
    BudgetMonth? month,
    int amount = 0,
  }) => management.create(
    month: month ?? jan,
    categoryId: category,
    amountCents: amount,
  );

  // Incluye timestamps, origen, árbol y revisión; el rechazo no altera nada.
  Future<Map<String, List<Map<String, Object?>>>> snapshot() async => {
    for (final table in [
      'budgets',
      'import_rows',
      'import_batches',
      'categories',
      'database_state',
    ])
      table:
          (await repository.database
                  .customSelect('SELECT * FROM $table ORDER BY rowid')
                  .get())
              .map((r) => Map<String, Object?>.from(r.data))
              .toList(),
  };

  Matcher failure(BudgetFailureCode code) =>
      isA<BudgetFailure>().having((e) => e.code, 'code', code);

  Future<BudgetFailure> conflict(Future<Object?> operation) async {
    try {
      await operation;
      fail('Se esperaba un conflicto');
    } on BudgetFailure catch (error) {
      return error;
    }
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('budget-management-synthetic-');
    store = LocalDatabaseStore(supportDirectory: () async => dir);
    repository = SqliteBudgetRepository(await store.open());
    compose();
    root = (await categories.create(name: 'Alimentación')).id;
    child = (await categories.create(name: 'Supermercado', parentId: root)).id;
    leaf = (await categories.create(
      name: 'Compra semanal',
      parentId: child,
    )).id;
    sibling = (await categories.create(name: 'Restaurante', parentId: root)).id;
    other = (await categories.create(name: 'Ingresos', isIncome: true)).id;
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test(
    'Céntimos firmados, cero registrado, hermanos y meses independientes',
    () async {
      final zero = await create(leaf);
      await create(sibling, amount: -12345);
      await create(root, month: feb, amount: 12345);
      final income = await create(other, amount: -9223372036854775808);
      expect((await repository.list(jan)).length, 3);
      expect((await management.get(zero.id)).data.amountCents, 0);
      final changed = await management.edit(
        income.id,
        amountCents: 9223372036854775807,
      );
      expect(changed.id, income.id);
      expect(changed.data.amountCents, 9223372036854775807);
      await management.edit(zero.id, amountCents: 0);
      expect(await repository.get(zero.id), isNotNull);
      await management.delete(zero.id);
      expect(await repository.get(zero.id), isNull);
    },
  );

  test(
    'Conflictos en ambos sentidos con mes, UUID y rutas completas',
    () async {
      for (final descendant in [child, leaf]) {
        final parent = await create(root);
        final before = await snapshot();
        final rejected = await conflict(create(descendant));
        expect(rejected.code, BudgetFailureCode.ancestorDescendantConflict);
        final context = rejected.conflicts.single;
        expect(context.month.value, jan.value);
        expect(context.requestedCategoryId, descendant);
        expect(
          context.requestedPath,
          descendant == child
              ? 'Alimentación / Supermercado'
              : 'Alimentación / Supermercado / Compra semanal',
        );
        expect(context.existingBudgetId, parent.id);
        expect(context.existingCategoryId, root);
        expect(context.existingPath, 'Alimentación');
        expect(rejected.message, contains('2026-01'));
        expect(rejected.message, contains(context.requestedPath));
        expect(rejected.message, contains(context.existingPath));
        expect(await snapshot(), before);
        await management.delete(parent.id);
        final sub = await create(descendant);
        final reverse = await conflict(create(root));
        expect(reverse.code, BudgetFailureCode.ancestorDescendantConflict);
        expect(reverse.conflicts.single.existingPath, context.requestedPath);
        expect(reverse.conflicts.single.requestedPath, 'Alimentación');
        await management.delete(sub.id);
      }
    },
  );

  test('Explica todos los descendientes y distingue el duplicado', () async {
    final a = await create(leaf), b = await create(sibling);
    final before = await snapshot();
    final parent = await conflict(create(root));
    expect(
      parent.conflicts.map((c) => c.existingBudgetId),
      unorderedEquals([a.id, b.id]),
    );
    expect(
      parent.conflicts.map((c) => c.existingPath),
      unorderedEquals([
        'Alimentación / Supermercado / Compra semanal',
        'Alimentación / Restaurante',
      ]),
    );
    final duplicate = await conflict(create(leaf));
    expect(duplicate.code, BudgetFailureCode.duplicateCategoryMonth);
    expect(duplicate.conflicts.single.existingBudgetId, a.id);
    expect(
      duplicate.conflicts.single.requestedPath,
      duplicate.conflicts.single.existingPath,
    );
    expect(await snapshot(), before);
    await expectLater(
      create(leaf),
      throwsA(failure(BudgetFailureCode.duplicateCategoryMonth)),
    );
    expect(await snapshot(), before);
  });

  test('Edición parcial de CSV conserva identidad, textos, origen y fecha de alta al reabrir', () async {
    final batches = SqliteImportBatchRepository(repository.database);
    final batch = await batches.create(
      sha256: 'a' * 64,
      source: ImportSource.historicalCsv,
      originalName: 'sintetico.csv',
      contractVersion: '1',
      budgets: [
        ImportedBudget(
          2,
          BudgetInput.fromHistoricalCsv(
            month: jan,
            categoryId: leaf,
            csvAmountCents: 35025,
            concept: '  Previsión histórica  ',
            discretion: ' Necesario ',
          ),
        ),
      ],
    );
    final old = (await repository.list(jan)).single;
    final before = await snapshot();
    final revision = (await repository.database.readState()).revision;
    final edited = await management.edit(
      old.id,
      month: feb,
      categoryId: sibling,
      amountCents: 0,
    );
    expect(edited.id, old.id);
    expect(edited.data.month.value, feb.value);
    expect(edited.data.categoryId, sibling);
    expect(edited.data.amountCents, 0);
    expect(edited.data.concept, old.data.concept);
    expect(edited.data.discretion, old.data.discretion);
    expect(edited.importRowId, old.importRowId);
    expect(edited.batchId, batch.id);
    expect(edited.sourceOrdinal, 2);
    final after = await snapshot();
    expect(
      after['budgets']!.single['created_at'],
      before['budgets']!.single['created_at'],
    );
    expect(after['import_rows'], before['import_rows']);
    expect(after['import_batches'], before['import_batches']);
    expect((await repository.database.readState()).revision, revision + 1);
    await management.edit(
      old.id,
      month: feb,
      categoryId: sibling,
      amountCents: 0,
    );
    expect(
      await snapshot(),
      after,
    ); // Reintento exacto: sin nueva fila ni timestamp.
    await store.close();
    repository = SqliteBudgetRepository(await store.open());
    compose();
    expect(await snapshot(), after);
    final reopened = await management.get(old.id);
    expect(reopened.data.discretion, old.data.discretion);
    expect(reopened.batchId, batch.id);
  });

  test(
    'Edición rechazada conserva todo y permite corregir sin duplicar',
    () async {
      final parent = await create(root);
      final target = await create(leaf, month: feb, amount: -500);
      final before = await snapshot();
      for (var attempt = 0; attempt < 2; attempt++) {
        final error = await conflict(
          management.edit(target.id, month: jan, amountCents: 900),
        );
        expect(error.code, BudgetFailureCode.ancestorDescendantConflict);
        expect(error.conflicts.single.existingBudgetId, parent.id);
        expect(await snapshot(), before);
      }
      await management.delete(parent.id);
      final corrected = await management.edit(
        target.id,
        month: jan,
        amountCents: 900,
      );
      expect(corrected.id, target.id);
      expect((await repository.list(jan)).single.id, target.id);
      expect(await repository.list(feb), isEmpty);
      final siblingBudget = await create(sibling);
      final correctedState = await snapshot();
      await expectLater(
        management.edit(target.id, categoryId: sibling),
        throwsA(failure(BudgetFailureCode.duplicateCategoryMonth)),
      );
      expect(await snapshot(), correctedState);
      expect(await repository.get(siblingBudget.id), isNotNull);
    },
  );

  test('Archivadas conservan referencias y correcciones; nuevas asignaciones solo activas', () async {
    final historical = await create(leaf);
    final active = await create(other, month: feb);
    await categories.setArchived(root, archived: true);
    final edited = await management.edit(
      historical.id,
      month: feb,
      amountCents: -200,
    );
    expect(edited.data.categoryId, leaf);
    final before = await snapshot();
    await expectLater(
      create(leaf),
      throwsA(failure(BudgetFailureCode.categoryArchived)),
    );
    await expectLater(
      management.edit(active.id, categoryId: sibling),
      throwsA(failure(BudgetFailureCode.categoryArchived)),
    );
    expect(await snapshot(), before);
    final error = await conflict(create(root, month: feb));
    expect(error.code, BudgetFailureCode.categoryArchived);
    await management.edit(historical.id, categoryId: other, month: jan);
    expect((await management.get(historical.id)).data.categoryId, other);
    expect((await categories.get(leaf))!.archived, isTrue);
  });

  test(
    'Borrar CSV conserva huella y ordinal; repetir no resucita ni duplica',
    () async {
      final batches = SqliteImportBatchRepository(repository.database);
      Future<ImportBatch> import() => batches.create(
        sha256: 'b' * 64,
        source: ImportSource.historicalCsv,
        originalName: 'sintetico.csv',
        contractVersion: '1',
        budgets: [
          ImportedBudget(
            2,
            BudgetInput(month: jan, categoryId: leaf, amountCents: 0),
          ),
        ],
      );
      final batch = await import();
      final record = (await repository.list(jan)).single;
      final before = await snapshot();
      await management.delete(record.id);
      final deleted = await snapshot();
      expect(deleted['budgets'], isEmpty);
      expect(deleted['import_rows'], before['import_rows']);
      expect(deleted['import_batches'], before['import_batches']);
      expect((await batches.getByFingerprint('b' * 64))!.id, batch.id);
      await expectLater(import(), throwsA(isA<MovementFailure>()));
      await expectLater(
        management.delete(record.id),
        throwsA(failure(BudgetFailureCode.notFound)),
      );
      expect(await snapshot(), deleted);
      await store.close();
      repository = SqliteBudgetRepository(await store.open());
      compose();
      expect(await snapshot(), deleted);
    },
  );

  test('SQLite aborta tras escritura: revierte datos y revisión; reintento manual correcto', () async {
    final record = await create(leaf, amount: -500);
    final before = await snapshot();
    await repository.database.customStatement(
      "CREATE TEMP TRIGGER fail_budget_update AFTER UPDATE ON budgets BEGIN SELECT RAISE(ABORT, 'synthetic disk failure'); END",
    );
    await expectLater(
      management.edit(
        record.id,
        month: feb,
        categoryId: sibling,
        amountCents: 900,
      ),
      throwsA(failure(BudgetFailureCode.persistence)),
    );
    expect(await snapshot(), before);
    await repository.database.customStatement(
      'DROP TRIGGER fail_budget_update',
    );
    final retried = await management.edit(
      record.id,
      month: feb,
      categoryId: sibling,
      amountCents: 900,
    );
    expect(retried.id, record.id);
    expect((await repository.list(feb)).single.data.amountCents, 900);
    expect(await repository.list(jan), isEmpty);
  });

  test('Errores identificables por categoría inexistente, partida ausente y mes inválido', () async {
    final before = await snapshot();
    await expectLater(
      create('missing'),
      throwsA(failure(BudgetFailureCode.categoryNotFound)),
    );
    await expectLater(
      management.get('missing'),
      throwsA(failure(BudgetFailureCode.notFound)),
    );
    await expectLater(
      management.edit('missing', amountCents: 0),
      throwsA(failure(BudgetFailureCode.notFound)),
    );
    await expectLater(
      management.delete('missing'),
      throwsA(failure(BudgetFailureCode.notFound)),
    );
    expect(
      () => BudgetMonth(2026, 13),
      throwsA(failure(BudgetFailureCode.invalidMonth)),
    );
    expect(
      () => BudgetMonth.parse('2026-01-15'),
      throwsA(failure(BudgetFailureCode.invalidMonth)),
    );
    expect(await snapshot(), before);
  });
}
