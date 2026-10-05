import '../features/budget/budget.dart';
import '../features/budget/presentation/budget_source.dart';
import '../features/movements/movements.dart';
import 'category_management_factory.dart';
import 'monthly_budget_query_factory.dart';
import 'data/sqlite/local_database.dart';
import 'data/sqlite/sqlite_budget_repository.dart';

BudgetSource createBudgetSource(
  LocalDatabase database,
  CategoryReadInvalidation invalidation,
) => BudgetSource(
  query: createMonthlyBudgetQuery(
    database: database,
    invalidation: invalidation,
  ),
  management: BudgetManagement(
    repository: SqliteBudgetRepository(database),
    unitOfWork: database,
  ),
  categories: createCategoryManagement(
    database: database,
    invalidation: invalidation,
  ).list,
  identity: database,
);
