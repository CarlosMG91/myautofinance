import '../features/wealth/wealth.dart';
import 'data/sqlite/local_database.dart';
import 'data/sqlite/sqlite_account_repository.dart';
import 'data/sqlite/sqlite_wealth_repository.dart';

/// Una sola conexión abierta para fichas, fotos y consultas transaccionales.
WealthManagement createWealthManagement({required LocalDatabase database}) =>
    WealthManagement(
      accounts: SqliteAccountRepository(database),
      photos: SqliteWealthRepository(database),
      unitOfWork: database,
    );
