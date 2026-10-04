import '../features/movements/movements.dart';
import 'data/sqlite/database_failure.dart';
import 'data/sqlite/local_database.dart';
import 'data/sqlite/sqlite_movement_repository.dart';

/// Reutiliza la conexión de la sesión, sin abrir otra base ni añadir pantallas.
MovementManagement createMovementManagement({
  required LocalDatabase database,
}) => MovementManagement(
  repository: SqliteMovementRepository(database),
  unitOfWork: database,
  errorMessage: (error) => error is DatabaseFailure ? error.message : null,
);
