import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/persistence/unit_of_work.dart';
import '../features/synchronization/synchronization.dart';
import '../features/synchronization/data/local_backup_service.dart';
import '../features/synchronization/data/local_backup_catalog_service.dart';
import '../features/synchronization/data/native_backup_persistence.dart';
import 'data/sqlite/local_database_store.dart';
import 'data/sqlite/schema_policy.dart';

LocalBackupCreator createLocalBackupCreator({
  required LocalDatabaseStore store,
  SupportDirectory? supportDirectory,
  NativeBackupPersistence? persistence,
}) => LocalBackupService(
  source: store,
  validator: const SqliteLocalBackupValidator(),
  supportDirectory: supportDirectory ?? getApplicationSupportDirectory,
  persistence: persistence,
);

/// Disponible antes de abrir el store, incluso con una activa dañada.
LocalBackupCatalog createLocalBackupCatalog({
  SupportDirectory? supportDirectory,
  NativeBackupPersistence? persistence,
}) => LocalBackupCatalogService(
  validator: const SqliteLocalBackupValidator(),
  supportDirectory: supportDirectory ?? getApplicationSupportDirectory,
  persistence: persistence,
);

/// Reutiliza la validación integral publicada; nunca migra ni escribe la imagen.
final class SqliteLocalBackupValidator implements LocalBackupImageValidator {
  const SqliteLocalBackupValidator();
  @override
  Future<LocalBackupImage> validate(String path) async {
    try {
      final parent = Directory(p.dirname(path));
      await for (final file in parent.list(followLinks: false)) {
        if (file.path == '$path-wal' ||
            file.path == '$path-shm' ||
            file.path == '$path-journal') {
          throw const LocalBackupFailure(
            LocalBackupFailureCode.invalidSnapshot,
          );
        }
      }
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        validateExistingDatabase(db);
        if (readSchemaVersion(db) != localSchemaVersion) {
          throw const LocalBackupFailure(
            LocalBackupFailureCode.invalidSnapshot,
          );
        }
        final state = db
            .select(
              'SELECT dataset_id,revision FROM database_state WHERE singleton=1',
            )
            .single;
        return LocalBackupImage(
          state: DatasetState(
            datasetId: state['dataset_id'] as String,
            revision: state['revision'] as int,
          ),
          schemaVersion: readSchemaVersion(db),
          applicationId: localApplicationId,
        );
      } finally {
        db.close();
      }
    } catch (_) {
      throw const LocalBackupFailure(LocalBackupFailureCode.invalidSnapshot);
    }
  }
}
