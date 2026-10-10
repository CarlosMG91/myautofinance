import 'movement_list_factory.dart';
import 'pending_movement_factory.dart';
import '../features/movements/presentation/pending_movement_controller.dart';
import 'import_factory.dart';
import '../features/importing/presentation/import_controller.dart';
import 'budget_factory.dart';
import 'monthly_status_query_factory.dart';
import '../features/monthly_status/monthly_status.dart';
import '../features/budget/presentation/budget_source.dart';
import '../features/movements/presentation/movement_list_controller.dart';
import '../features/synchronization/presentation/local_backup_controller.dart';
import 'data/sqlite/database_failure.dart';
import 'data/sqlite/local_database_store.dart';
import 'local_backup_factory.dart';
import 'drive_ui_factory.dart';
import '../features/synchronization/presentation/drive_controller.dart';
import '../features/movements/movements.dart';
import 'category_management_factory.dart';
import '../features/wealth/wealth.dart';
import 'wealth_management_factory.dart';

/// Una sola conexión y los servicios locales de la instalación, sin OAuth.
class LocalBackupSession {
  LocalBackupSession({SupportDirectory? supportDirectory})
    : store = LocalDatabaseStore(supportDirectory: supportDirectory) {
    controller = LocalBackupController(
      catalog: createLocalBackupCatalog(supportDirectory: supportDirectory),
      creator: createLocalBackupCreator(
        store: store,
        supportDirectory: supportDirectory,
      ),
      restorer: createLocalRestorer(
        store: store,
        supportDirectory: supportDirectory,
      ),
      activeAvailable: false,
      retryStartup: open,
    );
    // La recuperación puede reemplazar el catálogo sin pasar por gestión.
    controller.addListener(categoryInvalidation.invalidate);
  }

  final LocalDatabaseStore store;
  late final DriveController drive = createDriveUi(
    store: store,
    onRecoveryRequired: controller.retryOpen,
  );
  late final LocalBackupController controller;
  final categoryInvalidation = CategoryReadInvalidation();

  // Resolver por visita: una restauración puede sustituir la conexión activa.
  Future<BudgetSource> budgets() async =>
      createBudgetSource(await store.open(), categoryInvalidation);

  Future<MonthlyStatusQuery> monthlyStatus() async => createMonthlyStatusQuery(
    database: await store.open(),
    invalidation: categoryInvalidation,
  );

  Future<ImportServices> imports() async => createImportServices(
    await store.open(),
    onConfirmed: categoryInvalidation.invalidate,
  );

  Future<MovementListSource> movements() async =>
      createMovementListSource(await store.open(), categoryInvalidation);

  Future<PendingMovementSource> pendingMovements() async =>
      createPendingMovementSource(await store.open(), categoryInvalidation);

  Future<WealthManagement> wealth() async =>
      createWealthManagement(database: await store.open());

  Future<CategoryManagement> categories() async => createCategoryManagement(
    database: await store.open(),
    invalidation: categoryInvalidation,
  );

  Future<bool> open() async {
    try {
      // El store resuelve cualquier diario ANTES de abrir o crear SQLite.
      await store.open();
      controller.activeAvailable = true;
      controller.startupMessage = null;
      controller.recoveryBlocked = false;
      return true;
    } on DatabaseFailure catch (failure) {
      controller.activeAvailable = false;
      controller.startupMessage = failure.message;
      controller.recoveryBlocked =
          failure.code == DatabaseFailureCode.restoring ||
          failure.code == DatabaseFailureCode.futureVersion;
      return false;
    } catch (_) {
      controller.activeAvailable = false;
      controller.startupMessage = 'No se pudo abrir la base local. Se conservan los archivos originales.';
      return false;
    }
  }
}
