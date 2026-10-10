import '../../../core/persistence/unit_of_work.dart';
import 'local_database.dart';

/// Snapshot SQLite sin las escrituras de control de writeTransaction.
/// Componer exclusivamente con repositorios de lectura de esta conexión.
final class SqliteReadUnitOfWork implements UnitOfWork {
  const SqliteReadUnitOfWork(this.database);
  final LocalDatabase database;

  @override
  Future<T> run<T>(Future<T> Function() operation) =>
      database.transaction(operation);

  @override
  Future<DatasetState> readState() => database.readState();
}
