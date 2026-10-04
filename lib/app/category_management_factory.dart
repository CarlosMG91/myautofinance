import '../features/movements/movements.dart';
import 'data/sqlite/database_failure.dart';
import 'data/sqlite/local_database.dart';
import 'data/sqlite/sqlite_category_repository.dart';

/// Componer con la conexión abierta de la sesión; no crea una segunda base.
CategoryManagement createCategoryManagement({
  required LocalDatabase database,
  CategoryReadInvalidation? invalidation,
}) => CategoryManagement(
  invalidation: invalidation,
  repository: SqliteCategoryRepository(database),
  unitOfWork: database,
  errorMessage: (error) => error is DatabaseFailure ? error.message : null,
);
