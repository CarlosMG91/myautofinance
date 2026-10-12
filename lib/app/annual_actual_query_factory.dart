import '../features/actual_spending/actual_spending.dart';
import '../features/movements/movements.dart';
import 'category_management_factory.dart';
import 'data/sqlite/local_database.dart';
import 'data/sqlite/sqlite_movement_repository.dart';
import 'data/sqlite/sqlite_read_unit_of_work.dart';

/// App recompone con la conexión nueva y la invalidación común al restaurar.
AnnualActualQuery createAnnualActualQuery({
  required LocalDatabase database,
  required CategoryReadInvalidation invalidation,
}) => AnnualActualQuery(
  movements: SqliteMovementRepository(database),
  categories: createCategoryManagement(
    database: database,
    invalidation: invalidation,
  ),
  unitOfWork: SqliteReadUnitOfWork(database),
);
