import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/monthly_budget_query_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';

void main() {
  late LocalDatabase db;
  late CategoryManagement categories;
  late CategoryReadInvalidation invalidation;
  late MonthlyBudgetQuery query;
  late BudgetManagement management;
  final jan = BudgetMonth(2026, 1);

  setUp(() {
    db = LocalDatabase(
      NativeDatabase.memory(
        setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    query = createMonthlyBudgetQuery(database: db, invalidation: invalidation);
    management = BudgetManagement(
      repository: SqliteBudgetRepository(db),
      unitOfWork: db,
    );
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
  });

  test(
    'Árbol completo en preorden, tres niveles, UUID duplicados y cero propio',
    () async {
      final root = await categories.create(name: 'Ingresos', isIncome: true);
      final child = await categories.create(
        name: 'Salario',
        parentId: root.node.id,
      );
      final first = await categories.create(
        name: 'Impuestos',
        parentId: child.node.id,
      );
      final second = await categories.create(
        name: 'Impuestos',
        parentId: child.node.id,
      );
      final expense = await categories.create(name: 'Salida', isIncome: false);
      final zero = await management.create(
        month: jan,
        categoryId: first.node.id,
        amountCents: 0,
      );
      await management.create(
        month: jan,
        categoryId: second.node.id,
        amountCents: -60000,
      );
      await management.create(
        month: jan,
        categoryId: expense.node.id,
        amountCents: 123,
      );
      final result = await query.read(jan);
      final rows = {for (final row in result.activeTree) row.categoryId: row};
      expect(rows.length, 5);
      expect(result.activeTree.take(2).map((r) => r.categoryId), [
        root.node.id,
        child.node.id,
      ]);
      expect(rows[root.node.id]!.ownAmountCents, isNull);
      expect(rows[child.node.id]!.budget, isNull);
      expect(rows[first.node.id]!.ownAmountCents, 0);
      expect(rows[first.node.id]!.budget!.id, zero.id);
      expect(rows[second.node.id]!.ownAmountCents, -60000);
      for (final id in [first.node.id, second.node.id]) {
        expect(rows[id]!.category.path, 'Ingresos / Salario / Impuestos');
        expect(rows[id]!.category.node.depth, 3);
        expect(rows[id]!.category.node.parentId, child.node.id);
        expect(rows[id]!.category.node.isIncome, isTrue);
      }
      expect(rows[expense.node.id]!.category.node.isIncome, isFalse);
      expect(result.archivedBudgets, isEmpty);
      expect(() => result.activeTree.clear(), throwsUnsupportedError);
    },
  );

  test(
    'Mes vacío y límites civiles no inventan partidas ni modifican revisión',
    () async {
      await categories.create(name: 'Activa', isIncome: false);
      final archived = await categories.create(
        name: 'Archivada',
        isIncome: false,
      );
      await categories.archive(archived.node.id);
      final before = await db.readState();
      for (final month in [BudgetMonth(1, 1), jan, BudgetMonth(9999, 12)]) {
        final result = await query.read(month);
        expect(result.month.value, month.value);
        expect(result.activeTree.single.budget, isNull);
        expect(result.activeTree.single.ownAmountCents, isNull);
        expect(result.archivedBudgets, isEmpty);
      }
      expect((await db.readState()).revision, before.revision);
      expect(await SqliteBudgetRepository(db).list(jan), isEmpty);
    },
  );

  test(
    'Partidas del padre no se reparten; otros meses no se mezclan',
    () async {
      final root = await categories.create(name: 'Raíz', isIncome: false);
      final child = await categories.create(
        name: 'Hija',
        parentId: root.node.id,
      );
      await management.create(
        month: jan,
        categoryId: root.node.id,
        amountCents: -100,
      );
      await management.create(
        month: BudgetMonth(2026, 2),
        categoryId: child.node.id,
        amountCents: 900,
      );
      final rows = (await query.read(jan)).activeTree;
      expect(rows.first.ownAmountCents, -100);
      expect(rows.last.ownAmountCents, isNull);
      expect(
        (await query.read(BudgetMonth(2026, 2))).activeTree.last.ownAmountCents,
        900,
      );
    },
  );

  test(
    'Histórico archivado conserva procedencia y admite corrección existente',
    () async {
      final root = await categories.create(name: 'Gastos', isIncome: false);
      final child = await categories.create(
        name: 'Histórico',
        parentId: root.node.id,
      );
      final batch = await SqliteImportBatchRepository(db).create(
        sha256: 'a' * 64,
        source: ImportSource.historicalCsv,
        originalName: 'sintetico.csv',
        contractVersion: '1',
        budgets: [
          ImportedBudget(
            2,
            BudgetInput.fromHistoricalCsv(
              month: jan,
              categoryId: child.node.id,
              csvAmountCents: 1500,
              concept: 'Texto histórico',
              discretion: 'Necesario',
            ),
          ),
        ],
      );
      await categories.archive(root.node.id);
      final before = (await query.read(jan)).archivedBudgets.single;
      expect((await query.read(jan)).activeTree, isEmpty);
      expect(before.category.path, 'Gastos / Histórico');
      expect(before.category.node.archived, isTrue);
      expect(before.ownAmountCents, -1500);
      expect(before.budget!.batchId, batch.id);
      expect(before.budget!.sourceOrdinal, 2);
      expect(before.budget!.importRowId, isNotNull);
      await management.edit(before.budget!.id, amountCents: 0);
      final after = (await query.read(jan)).archivedBudgets.single;
      expect(after.budget!.id, before.budget!.id);
      expect(after.budget!.importRowId, before.budget!.importRowId);
      expect(after.budget!.batchId, batch.id);
      expect(after.budget!.sourceOrdinal, 2);
      expect(after.budget!.data.concept, 'Texto histórico');
      expect(after.budget!.data.discretion, 'Necesario');
      expect(after.ownAmountCents, 0);
      await expectLater(
        management.create(
          month: BudgetMonth(2026, 2),
          categoryId: child.node.id,
          amountCents: 0,
        ),
        throwsA(isA<BudgetFailure>()),
      );
      await categories.reactivate(root.node.id);
      final restored = await query.read(jan);
      expect(restored.archivedBudgets, isEmpty);
      expect(restored.activeTree.last.budget!.id, before.budget!.id);
    },
  );

  test(
    'Invalidación compartida actualiza rutas, tipo y UUID sin alterar importes',
    () async {
      final income = await categories.create(name: 'Ingresos', isIncome: true);
      final expense = await categories.create(name: 'Gastos', isIncome: false);
      final child = await categories.create(
        name: 'Rama',
        parentId: income.node.id,
      );
      final leaf = await categories.create(
        name: 'Hoja',
        parentId: child.node.id,
      );
      final record = await management.create(
        month: jan,
        categoryId: leaf.node.id,
        amountCents: -60000,
      );
      final old = await query.read(jan);
      final events = <int>[];
      final subscription = query.invalidation.changes.listen(events.add);
      final other = createCategoryManagement(
        database: db,
        invalidation: invalidation,
      );
      await other.move(child.node.id, parentId: expense.node.id);
      await other.rename(expense.node.id, name: 'Salidas');
      expect(events.length, 2);
      final result = await query.read(jan);
      final row = result.activeTree.singleWhere(
        (row) => row.categoryId == leaf.node.id,
      );
      expect(row.category.path, 'Salidas / Rama / Hoja');
      expect(row.category.node.isIncome, isFalse);
      expect(row.budget!.id, record.id);
      expect(row.ownAmountCents, -60000);
      expect(result.categoryGeneration, old.categoryGeneration + 2);
      expect(
        old.activeTree
            .singleWhere((r) => r.categoryId == leaf.node.id)
            .category
            .path,
        'Ingresos / Rama / Hoja',
      );
      invalidation
          .invalidate(); // También tras reemplazar la base de la sesión.
      expect(events.length, 3);
      await subscription.cancel();
    },
  );

  test('Fallo técnico entrega mensaje español sin detalles SQLite', () async {
    await db.customStatement('DROP TABLE budgets');
    await expectLater(
      query.read(jan),
      throwsA(
        isA<BudgetFailure>()
            .having((e) => e.code, 'código', BudgetFailureCode.persistence)
            .having(
              (e) => e.message,
              'mensaje',
              'No se pudo consultar el presupuesto del mes. Inténtalo de nuevo.',
            ),
      ),
    );
  });
}
