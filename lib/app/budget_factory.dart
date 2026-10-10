import '../features/budget/budget.dart';
import '../features/budget/presentation/budget_source.dart';
import '../features/movements/movements.dart';
import 'category_management_factory.dart';
import 'budget_proposal_factory.dart';
import 'monthly_budget_query_factory.dart';
import 'data/sqlite/local_database.dart';
import 'data/sqlite/sqlite_budget_repository.dart';
import 'data/sqlite/sqlite_read_unit_of_work.dart';

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
  entries: BudgetListReader(
    budgets: SqliteBudgetRepository(database),
    categories: createCategoryManagement(
      database: database,
      invalidation: invalidation,
    ),
    unitOfWork: SqliteReadUnitOfWork(database),
  ),
  proposalCalculator: createBudgetProposalCalculator(
    database: database,
    invalidation: invalidation,
  ),
  proposalSaver: createBudgetProposalSaver(
    database: database,
    invalidation: invalidation,
  ),
);
