import '../features/movements/movements.dart';
import '../features/movements/presentation/pending_movement_controller.dart';
import '../features/wealth/wealth.dart';
import 'data/sqlite/local_database.dart';
import 'data/sqlite/sqlite_account_repository.dart';
import 'movement_management_factory.dart';

PendingMovementSource createPendingMovementSource(
  LocalDatabase database,
  CategoryReadInvalidation invalidation,
) => PendingMovementSource(
  management: createPendingMovementManagement(database: database),
  accounts: () async => {
    for (final account in await SqliteAccountRepository(database).list())
      if (account.kind == AccountKind.account) account.id: account.name,
  },
  // Etiquetas EP-004, independientes del importador y sus lectores.
  batches: () async => {
    for (final row
        in await database
            .customSelect(
              'SELECT id, original_name, imported_at FROM import_batches ORDER BY imported_at DESC, id ASC',
            )
            .get())
      row.read<String>(
        'id',
      ): '${row.read<String>('original_name')} · ${row.read<String>('imported_at')}',
  },
  invalidation: invalidation,
  identity: database,
);
