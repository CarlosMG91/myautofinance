import '../features/budget/budget.dart';
import '../features/movements/movements.dart';
import 'category_management_factory.dart';
import 'data/sqlite/local_database.dart';
import 'data/sqlite/sqlite_budget_repository.dart';
import 'data/sqlite/sqlite_movement_repository.dart';

BudgetProposalCalculator createBudgetProposalCalculator({
  required LocalDatabase database,
  required CategoryReadInvalidation invalidation,
}) => BudgetProposalCalculator(
  movements: SqliteMovementRepository(database),
  categories: createCategoryManagement(
    database: database,
    invalidation: invalidation,
  ),
  budgets: SqliteBudgetRepository(database),
  unitOfWork: database,
);
