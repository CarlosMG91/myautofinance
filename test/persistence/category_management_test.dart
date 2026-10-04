import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/database_failure.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/movements/movements.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalDatabaseStore store;
  late LocalDatabase db;
  late CategoryManagement management;
  const account = '81000000-0000-4000-8000-000000000001';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('management-synthetic-');
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    db = await store.open();
    management = createCategoryManagement(database: db);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<int> revision() async => (await db.readState()).revision;
  Future<List<Map<String, Object?>>> rows(String table) async =>
      (await db.customSelect('SELECT * FROM $table ORDER BY id').get())
          .map((row) => row.data)
          .toList();

  Future<MovementInput> movement(String category) async {
    await db.run(() async {
      await db.customStatement(
        "INSERT INTO accounts VALUES(?,'Cuenta sintética','account','2026-01-01',NULL,'t','t')",
        [account],
      );
      await db.customStatement(
        "INSERT INTO account_liquidity_periods VALUES('81000000-0000-4000-8000-000000000002',?,'2026-01-01',NULL,'liquid','t','t')",
        [account],
      );
    });
    return MovementInput(
      accountId: account,
      valueDate: ValueDate(2026, 1, 10),
      concept: 'Impuesto sintético',
      amountCents: -10025,
      categoryId: category,
    );
  }

  test(
    'Crear, consultar, editar y renombrar persisten; no-op y revisión',
    () async {
      final root = await management.create(
        name: '  Ingresos  ',
        isIncome: true,
      );
      expect(root.path, 'Ingresos');
      expect(await revision(), 1);
      final child = await management.create(
        name: 'Sueldo',
        parentId: root.node.id,
      );
      expect(child.path, 'Ingresos / Sueldo');
      expect(child.node.isIncome, isTrue);
      expect(await revision(), 2);
      await management.rename(child.node.id, name: '  Salario  ');
      expect(await revision(), 3);
      await management.rename(child.node.id, name: 'Salario');
      expect(await revision(), 3);
      await management.edit(
        root.node.id,
        name: 'Entradas',
        parentId: null,
        isIncome: false,
      );
      expect(await revision(), 4);
      final state = await db.readState();
      await store.close();
      db = await store.open();
      management = createCategoryManagement(database: db);
      final saved = await management.get(child.node.id);
      expect(saved.path, 'Entradas / Salario');
      expect(saved.node.isIncome, isFalse);
      expect((await db.readState()).datasetId, state.datasetId);
      expect(await revision(), 4);
      expect((await management.list()).length, 2);
      expect(await revision(), 4);
    },
  );

  test(
    'Validación de campos y reglas del árbol rechazan sin escribir',
    () async {
      await expectLater(
        management.create(name: ' ', parentId: '', isIncome: true),
        throwsA(
          isA<CategoryFormFailure>().having(
            (e) => e.fields.keys,
            'campos',
            containsAll(['name', 'parentId', 'isIncome']),
          ),
        ),
      );
      expect(await revision(), 0);
      final root = await management.create(name: 'A');
      final child = await management.create(name: 'B', parentId: root.node.id);
      final leaf = await management.create(name: 'C', parentId: child.node.id);
      final before = await rows('categories');
      for (final action in <Future<Object?> Function()>[
        () => management.move(child.node.id, parentId: ' '),
        () => management.edit(
          root.node.id,
          name: 'A',
          parentId: null,
          isIncome: null,
        ),
        () => management.rename(child.node.id, name: ' '),
      ]) {
        await expectLater(action(), throwsA(isA<CategoryFormFailure>()));
        expect(await rows('categories'), before);
        expect(await revision(), 3);
      }
      for (final action in <Future<Object?> Function()>[
        () => management.create(name: 'D', parentId: leaf.node.id),
        () => management.move(root.node.id, parentId: child.node.id),
        () => management.move(child.node.id, parentId: 'inexistente'),
        () => management.get('inexistente'),
        () => management.rename('inexistente', name: 'D'),
        () => management.edit(
          'inexistente',
          name: 'D',
          parentId: null,
          isIncome: false,
        ),
        () => management.archive('inexistente'),
        () => management.reactivate('inexistente'),
      ]) {
        await expectLater(action(), throwsA(isA<CategoryFailure>()));
        expect(await rows('categories'), before);
        expect(await revision(), 3);
      }
    },
  );

  test(
    'Traslado devuelve ruta/tipo; historia conserva signos y promoción',
    () async {
      final income = await management.create(name: 'Ingresos', isIncome: true);
      final expense = await management.create(name: 'Gastos');
      final child = await management.create(
        name: 'Impuesto',
        parentId: income.node.id,
      );
      final data = await movement(child.node.id);
      final movements = SqliteMovementRepository(db);
      final budgets = SqliteBudgetRepository(db);
      final real = await movements.create(data);
      await budgets.create(
        BudgetInput(
          month: BudgetMonth(2026, 1),
          categoryId: child.node.id,
          amountCents: -15000,
        ),
      );
      final beforeReal = await rows('movements');
      final beforeBudget = await rows('budgets');
      final before = await revision();
      final result = await management.move(
        child.node.id,
        parentId: expense.node.id,
      );
      expect(result.path, 'Gastos / Impuesto');
      expect(result.node.isIncome, isFalse);
      expect(result.node.id, child.node.id);
      expect(await revision(), before + 1);
      expect(await rows('movements'), beforeReal);
      expect(await rows('budgets'), beforeBudget);
      expect((await movements.get(real.id))!.data.amountCents, -10025);
      expect(await budgets.readYear(2026, incomeOnly: true), isEmpty);
      final promoted = await management.move(child.node.id, parentId: null);
      expect(promoted.path, 'Impuesto');
      expect(promoted.node.isIncome, isFalse);
      expect(promoted.node.depth, 1);
      final promotedRevision = await revision();
      await expectLater(
        management.edit(
          child.node.id,
          name: 'Impuesto',
          parentId: null,
          isIncome: true,
        ),
        throwsA(isA<CategoryFailure>()),
      );
      expect(await revision(), promotedRevision);
      await store.close();
      db = await store.open();
      management = createCategoryManagement(database: db);
      expect((await management.get(child.node.id)).node.isIncome, isFalse);
      expect(await rows('movements'), beforeReal);
      expect(await rows('budgets'), beforeBudget);
    },
  );

  test(
    'Archivo/reactivación de rama; historia visible y asignaciones bloqueadas',
    () async {
      final root = await management.create(name: 'Ingresos', isIncome: true);
      final child = await management.create(
        name: 'Sueldo',
        parentId: root.node.id,
      );
      final leaf = await management.create(
        name: 'Impuestos',
        parentId: child.node.id,
      );
      final data = await movement(leaf.node.id);
      final movements = SqliteMovementRepository(db);
      final budgets = SqliteBudgetRepository(db);
      await movements.create(data);
      final budget = BudgetInput(
        month: BudgetMonth(2026, 1),
        categoryId: leaf.node.id,
        amountCents: -100,
      );
      await budgets.create(budget);
      final before = await revision();
      await management.archive(child.node.id);
      await management.archive(root.node.id);
      expect(await revision(), before + 2);
      expect((await management.list()).every((n) => n.node.archived), isTrue);
      expect(await management.assignmentOptions(), isEmpty);
      expect(
        (await movements.readYear(2026)).single.data.categoryId,
        leaf.node.id,
      );
      expect(
        (await budgets.readYear(
          2026,
          incomeOnly: true,
        )).single.data.amountCents,
        -100,
      );
      final archivedRevision = await revision();
      await store.close();
      db = await store.open();
      management = createCategoryManagement(database: db);
      expect(
        (await management.get(leaf.node.id)).path,
        'Ingresos / Sueldo / Impuestos',
      );
      expect((await management.list()).every((n) => n.node.archived), isTrue);
      expect(await management.assignmentOptions(), isEmpty);
      expect(await revision(), archivedRevision);
      final reopenedMovements = SqliteMovementRepository(db);
      final reopenedBudgets = SqliteBudgetRepository(db);
      await management.archive(root.node.id);
      for (final action in <Future<Object?> Function()>[
        () => management.reactivate(child.node.id),
        () => management.create(name: 'Nueva', parentId: root.node.id),
        () => reopenedMovements.create(data),
        () => reopenedBudgets.create(budget),
      ]) {
        await expectLater(
          action(),
          throwsA(
            anyOf(
              isA<CategoryFailure>(),
              isA<MovementFailure>(),
              isA<BudgetFailure>(),
            ),
          ),
        );
        expect(await revision(), archivedRevision);
      }
      await management.reactivate(root.node.id);
      expect((await management.assignmentOptions()).length, 3);
      expect(await revision(), archivedRevision + 1);
      await management.reactivate(root.node.id);
      expect(await revision(), archivedRevision + 1);
    },
  );

  test('Un fallo durante archivo/reactivación revierte rama y revisión', () async {
    final root = await management.create(name: 'Raíz');
    final child = await management.create(name: 'Hija', parentId: root.node.id);
    await management.create(name: 'Hoja', parentId: child.node.id);

    for (final archived in [true, false]) {
      final before = await rows('categories');
      final beforeRevision = await revision();
      // Trigger temporal de fallo sintético: no modifica el esquema publicado.
      await db.customStatement('''
CREATE TEMP TRIGGER synthetic_archive_failure BEFORE UPDATE OF archived ON categories
WHEN NEW.id='${child.node.id}' AND NEW.archived=${archived ? 1 : 0}
BEGIN SELECT RAISE(ABORT,'synthetic failure'); END
''');
      try {
        await expectLater(
          archived
              ? management.archive(root.node.id)
              : management.reactivate(root.node.id),
          throwsA(
            isA<CategoryFailure>().having(
              (e) => e.message,
              'mensaje controlado',
              'No se pudo completar la operación de categorías. Inténtalo de nuevo.',
            ),
          ),
        );
        expect(await rows('categories'), before);
        expect(await revision(), beforeRevision);
      } finally {
        await db.customStatement('DROP TRIGGER synthetic_archive_failure');
      }
      if (archived) await management.archive(root.node.id);
    }
    await management.reactivate(root.node.id);
    expect((await management.assignmentOptions()).length, 3);
  });

  test(
    'Solapamiento conserva detalle en español y revierte árbol y revisión',
    () async {
      final root = await management.create(name: 'Raíz');
      final other = await management.create(name: 'Otra');
      final child = await management.create(
        name: 'Hija',
        parentId: other.node.id,
      );
      final budgets = SqliteBudgetRepository(db);
      for (final id in [root.node.id, child.node.id]) {
        await budgets.create(
          BudgetInput(
            month: BudgetMonth(2025, 2),
            categoryId: id,
            amountCents: 0,
          ),
        );
      }
      final before = await rows('categories');
      final beforeBudget = await rows('budgets');
      final beforeRevision = await revision();
      await expectLater(
        management.edit(
          child.node.id,
          name: 'Renombrada',
          parentId: root.node.id,
          isIncome: null,
        ),
        throwsA(
          isA<CategoryFailure>()
              .having(
                (e) => e.message,
                'mensaje',
                contains('solapa presupuestos'),
              )
              .having(
                (e) => e.budgetConflicts.single.month,
                'mes',
                '2025-02-01',
              )
              .having(
                (e) => e.budgetConflicts.single.ancestorId,
                'raíz',
                root.node.id,
              )
              .having(
                (e) => e.budgetConflicts.single.descendantId,
                'descendiente',
                child.node.id,
              )
              .having(
                (e) => e.budgetConflicts.single.descendantPath,
                'ruta propuesta',
                'Raíz / Renombrada',
              ),
        ),
      );
      expect(await rows('categories'), before);
      expect(await rows('budgets'), beforeBudget);
      expect(await revision(), beforeRevision);
    },
  );

  test('Traduce bloqueo técnico a español sin SQL ni rutas privadas', () async {
    await db.blockWritesForRestore();
    await expectLater(
      management.create(name: 'Nueva'),
      throwsA(
        isA<CategoryFailure>().having(
          (e) => e.message,
          'mensaje',
          const DatabaseFailure(DatabaseFailureCode.restoring).message,
        ),
      ),
    );
    db.resumeWritesAfterRestore();
    expect(await revision(), 0);
    await db.close();
    await expectLater(
      management.list(),
      throwsA(
        isA<CategoryFailure>().having(
          (e) => e.message,
          'mensaje controlado',
          'No se pudo completar la operación de categorías. Inténtalo de nuevo.',
        ),
      ),
    );
  });
}
