import '../features/budget/budget.dart';
import '../features/movements/movements.dart';
import 'category_management_factory.dart';
import 'data/sqlite/local_database.dart';
import 'data/sqlite/sqlite_budget_repository.dart';
import 'data/sqlite/sqlite_read_unit_of_work.dart';

AnnualBudgetQuery createAnnualBudgetQuery({
  required LocalDatabase database,
  required CategoryReadInvalidation invalidation,
}) => AnnualBudgetQuery(
  budgets: SqliteBudgetRepository(database),
  categories: createCategoryManagement(
    database: database,
    invalidation: invalidation,
  ),
  unitOfWork: SqliteReadUnitOfWork(database),
);
