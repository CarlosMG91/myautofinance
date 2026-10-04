import '../features/synchronization/presentation/local_backup_controller.dart';
import 'data/sqlite/database_failure.dart';
import 'data/sqlite/local_database_store.dart';
import 'local_backup_factory.dart';
import 'drive_ui_factory.dart';
import '../features/synchronization/presentation/drive_controller.dart';
import '../features/movements/movements.dart';
import 'category_management_factory.dart';

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
