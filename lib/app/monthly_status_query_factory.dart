import '../features/monthly_status/monthly_status.dart';
import '../features/movements/movements.dart';
import 'category_management_factory.dart';
import 'data/sqlite/local_database.dart';
import 'data/sqlite/sqlite_budget_repository.dart';
import 'data/sqlite/sqlite_movement_repository.dart';
import 'data/sqlite/sqlite_read_unit_of_work.dart';

/// Recibe la conexión abierta de la sesión. Recompone tras restaurar la base.
MonthlyStatusQuery createMonthlyStatusQuery({
  required LocalDatabase database,
  required CategoryReadInvalidation invalidation,
}) => MonthlyStatusQuery(
  movements: SqliteMovementRepository(database),
  budgets: SqliteBudgetRepository(database),
  categories: createCategoryManagement(
    database: database,
    invalidation: invalidation,
  ),
  unitOfWork: SqliteReadUnitOfWork(database),
);
