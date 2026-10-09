import 'package:myautofinance/app/budget_factory.dart';

import 'dart:io';

import 'package:drift/native.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/movement_list_factory.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/budget/presentation/budget_source.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_controller.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

/// Dataset desechable de MA-TSK-146. Solo repositorios reales, sin importación.
final class HistoricalNavigationFixture {
  HistoricalNavigationFixture({File? file})
    : database = LocalDatabase(
        file == null
            ? NativeDatabase.memory(setup: configureConnection)
            : NativeDatabase(file, setup: configureConnection),
      ) {
    categories = createCategoryManagement(
      database: database,
      invalidation: invalidation,
    );
    wealth = createWealthManagement(database: database);
    budget = createBudgetSource(database, invalidation);
    movements = createMovementListSource(database, invalidation);
  }

  final LocalDatabase database;
  final invalidation = CategoryReadInvalidation();
  late final CategoryManagement categories;
  late final WealthManagement wealth;
  late final BudgetSource budget;
  late final MovementListSource movements;
  late String accountId,
      debtId,
      categoryId,
      archivedId,
      movementId,
      focusCategoryId;

  Future<void> seed() async {
    accountId = (await wealth.accounts.create(
      name: 'Cuenta histórica sintética',
      kind: AccountKind.account,
      activeFrom: Month(2025, 12),
      activeThrough: Month(2026, 2),
      liquidity: Liquidity.liquid,
    )).id;
    debtId = (await wealth.accounts.create(
      name: 'Deuda sintética',
      kind: AccountKind.debt,
      activeFrom: Month(2025, 12),
      activeThrough: Month(2026, 2),
    )).id;
    await wealth.photos.setValue(Month(2025, 12), accountId, 90000);
    await wealth.photos.setValue(Month(2025, 12), debtId, 10000);
    await wealth.photos.setValue(Month(2026, 1), accountId, 70000);
    await wealth.photos.setValue(Month(2026, 2), accountId, 0);
    await wealth.photos.setValue(Month(2026, 2), debtId, 0);
    categoryId = (await categories.create(
      name: 'Hogar sintético',
      isIncome: false,
    )).node.id;
    archivedId = (await categories.create(
      name: 'Rama archivada sintética',
      isIncome: false,
    )).node.id;
    await budget.management.create(
      month: BudgetMonth(2025, 12),
      categoryId: archivedId,
      amountCents: -20000,
    );
    await budget.management.create(
      month: BudgetMonth(2026, 1),
      categoryId: categoryId,
      amountCents: 0,
    );
    await budget.management.create(
      month: BudgetMonth(2026, 2),
      categoryId: categoryId,
      amountCents: -12300,
    );
    final repository = SqliteMovementRepository(database);
    await repository.create(
      MovementInput(
        accountId: accountId,
        valueDate: ValueDate(2025, 12, 31),
        concept: 'Cierre sintético',
        amountCents: -1000,
        categoryId: archivedId,
      ),
    );
    movementId = (await repository.create(
      MovementInput(
        accountId: accountId,
        valueDate: ValueDate(2026, 1, 1),
        concept: 'Enero sintético',
        amountCents: 30000,
        categoryId: categoryId,
      ),
    )).id;
    await repository.create(
      MovementInput(
        accountId: accountId,
        valueDate: ValueDate(2026, 1, 15),
        concept: 'Sin categoría sintético',
        amountCents: -5000,
      ),
    );
    await categories.archive(archivedId);
    for (var i = 0; i < 18; i++) {
      focusCategoryId = (await categories.create(
        name: 'Z rama sintética ${i.toString().padLeft(2, '0')}',
        isIncome: false,
      )).node.id;
    }
  }

  Future<void> close() async {
    await invalidation.close();
    await database.close();
  }
}
