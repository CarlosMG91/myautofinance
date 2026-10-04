import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement service;
  late CategoryManagement other;
  setUp(() {
    db = LocalDatabase(
      NativeDatabase.memory(
        setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    invalidation = CategoryReadInvalidation();
    service = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    other = createCategoryManagement(database: db, invalidation: invalidation);
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
  });

  test(
    'Commit invalida entre servicios; no-op y rollback no notifican',
    () async {
      final events = <int>[];
      final subscription = other.invalidation.changes.listen(events.add);
      final root = await service.create(name: 'Ingreso', isIncome: true);
      expect(events, [1]);
      await other.rename(root.node.id, name: 'Ingreso');
      expect(events, [1]);
      await service.rename(root.node.id, name: 'Ingresos');
      expect(events, [1, 2]);
      await expectLater(
        service.move(root.node.id, parentId: root.node.id),
        throwsA(isA<CategoryFailure>()),
      );
      expect(events, [1, 2]);
      expect((await other.get(root.node.id)).path, 'Ingresos');
      await subscription.cancel();
    },
  );

  test('Lecturas históricas siguen el traslado y herencia sin duplicar ni invertir signos', () async {
    final income = await service.create(name: 'Ingresos', isIncome: true);
    final expense = await service.create(name: 'Salida', isIncome: false);
    final branch = await service.create(name: 'Rama', parentId: income.node.id);
    final leaf = await service.create(name: 'Hoja', parentId: branch.node.id);
    final account = await SqliteAccountRepository(db).create(
      name: 'Sintética',
      kind: AccountKind.account,
      activeFrom: Month(2025, 1),
      liquidity: Liquidity.liquid,
    );
    final movements = SqliteMovementRepository(db);
    final budgets = SqliteBudgetRepository(db);
    for (final entry in {
      branch.node.id: 300000,
      leaf.node.id: -60000,
    }.entries) {
      await movements.create(
        MovementInput(
          accountId: account.id,
          valueDate: ValueDate(2025, 1, 1),
          concept: 'Sintético',
          amountCents: entry.value,
          categoryId: entry.key,
        ),
      );
    }
    for (var month = 1; month <= 12; month++) {
      await budgets.create(
        BudgetInput(
          month: BudgetMonth(2025, month),
          categoryId: leaf.node.id,
          amountCents: -60000,
        ),
      );
    }
    final beforeMovements = await movements.readYear(2025);
    final beforeBudgets = await budgets.readYear(2025);
    expect((await budgets.readYear(2025, incomeOnly: true)).length, 12);
    await other.move(branch.node.id, parentId: expense.node.id);
    await other.rename(expense.node.id, name: 'Gastos');
    final tree = CategoryGrouping(await service.list());
    expect(tree.categories[leaf.node.id]!.path, 'Gastos / Rama / Hoja');
    expect(tree.categories[leaf.node.id]!.node.isIncome, isFalse);
    final after = await movements.readYear(2025, categoryId: expense.node.id);
    expect(after.map((row) => row.id), beforeMovements.map((row) => row.id));
    expect(
      after.map((row) => row.data.amountCents),
      beforeMovements.map((row) => row.data.amountCents),
    );
    expect(
      await movements.readMonth(2025, 1, categoryId: income.node.id),
      isEmpty,
    );
    expect(
      (await movements.readMonth(2025, 1, categoryId: expense.node.id)).length,
      2,
    );
    expect(await budgets.readYear(2025, incomeOnly: true), isEmpty);
    expect(
      (await budgets.readYear(2025)).map((row) => row.id),
      beforeBudgets.map((row) => row.id),
    );
    final direct = <String, int>{};
    for (final row in after) {
      direct.update(
        row.data.categoryId!,
        (value) => value + row.data.amountCents,
        ifAbsent: () => row.data.amountCents,
      );
    }
    final totals = tree.aggregate(direct);
    expect(totals[expense.node.id], 240000);
    expect(totals[branch.node.id], 240000);
    expect(totals[leaf.node.id], -60000);
    expect(totals[income.node.id], 0);
    expect(tree.aggregate({leaf.node.id: -720000})[expense.node.id], -720000);
    await service.archive(branch.node.id);
    expect(
      (await service.assignmentOptions()).map((item) => item.node.id),
      isNot(contains(leaf.node.id)),
    );
    expect((await service.get(leaf.node.id)).path, 'Gastos / Rama / Hoja');
    expect(
      (await budgets.list(BudgetMonth(2025, 1))).single.data.amountCents,
      -60000,
    );
    await service.move(branch.node.id, parentId: income.node.id);
    expect((await budgets.readYear(2025, incomeOnly: true)).length, 12);
    expect((await service.get(leaf.node.id)).node.isIncome, isTrue);
    await service.move(branch.node.id, parentId: null);
    expect((await service.get(leaf.node.id)).node.isIncome, isTrue);
    expect((await budgets.readYear(2025, incomeOnly: true)).length, 12);
  });

  test(
    'Conflicto presupuestario no invalida ni publica un árbol parcial',
    () async {
      final root = await service.create(name: 'Origen', isIncome: true);
      final target = await service.create(name: 'Destino', isIncome: false);
      final leaf = await service.create(name: 'Hoja', parentId: root.node.id);
      final budgets = SqliteBudgetRepository(db);
      for (final id in [leaf.node.id, target.node.id]) {
        await budgets.create(
          BudgetInput(
            month: BudgetMonth(2025, 1),
            categoryId: id,
            amountCents: 0,
          ),
        );
      }
      final generation = invalidation.generation;
      final state = await db.readState();
      await expectLater(
        other.move(leaf.node.id, parentId: target.node.id),
        throwsA(isA<CategoryFailure>()),
      );
      expect(invalidation.generation, generation);
      expect((await db.readState()).revision, state.revision);
      expect((await service.get(leaf.node.id)).path, 'Origen / Hoja');
      expect((await budgets.readYear(2025, incomeOnly: true)).length, 1);
    },
  );
}
