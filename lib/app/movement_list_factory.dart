import '../features/movements/presentation/movement_list_controller.dart';
import '../features/movements/movements.dart';
import '../features/wealth/wealth.dart';
import 'data/sqlite/local_database.dart';
import 'data/sqlite/sqlite_movement_repository.dart';
import 'data/sqlite/sqlite_category_repository.dart';
import 'data/sqlite/sqlite_account_repository.dart';

MovementListSource createMovementListSource(
  LocalDatabase database,
  CategoryReadInvalidation invalidation,
) => MovementListSource(
  movements: SqliteMovementRepository(database),
  categories: SqliteCategoryRepository(database),
  accounts: () async => {
    for (final account in await SqliteAccountRepository(database).list())
      if (account.kind == AccountKind.account) account.id: account.name,
  },
  invalidation: invalidation,
);
