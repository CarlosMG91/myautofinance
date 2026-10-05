import '../features/movements/presentation/movement_list_controller.dart';
import '../features/movements/movements.dart';
import '../features/wealth/wealth.dart';
import 'data/sqlite/local_database.dart';
import 'data/sqlite/sqlite_movement_repository.dart';
import 'data/sqlite/sqlite_category_repository.dart';
import 'data/sqlite/sqlite_account_repository.dart';
import '../features/movements/presentation/movement_editor_source.dart';
import 'movement_management_factory.dart';
import 'category_management_factory.dart';

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
  editor: () async => MovementEditorSource(
    management: createMovementManagement(database: database),
    accounts: () async => [
      for (final a in await SqliteAccountRepository(database).list())
        if (a.kind == AccountKind.account)
          MovementAccountOption(
            a.id,
            a.name,
            a.activeFrom.value,
            a.activeThrough?.value,
          ),
    ],
    categories: createCategoryManagement(
      database: database,
      invalidation: invalidation,
    ).list,
  ),
);
