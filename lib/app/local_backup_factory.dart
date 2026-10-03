import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/persistence/unit_of_work.dart';
import '../features/synchronization/synchronization.dart';
import '../features/synchronization/data/local_backup_service.dart';
import '../features/synchronization/data/local_backup_catalog_service.dart';
import '../features/synchronization/data/local_restore_candidate_service.dart';
import '../features/synchronization/data/local_restore_service.dart';
import '../features/synchronization/data/native_backup_persistence.dart';
import '../features/synchronization/data/local_sync_contrast_reader.dart';
import 'data/sqlite/local_database_store.dart';
import 'data/sqlite/schema_policy.dart';
import 'data/sqlite/sqlite_restore_image_policy.dart';

LocalSyncContrastReader createLocalSyncContrastReader({
  SupportDirectory? supportDirectory,
}) => StoredLocalSyncContrastReader(
  supportDirectory: supportDirectory ?? getApplicationSupportDirectory,
);

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

/// No requiere abrir la activa, ni siquiera para migrar una copia antigua.
LocalRestoreCandidatePreparer createLocalRestoreCandidatePreparer({
  SupportDirectory? supportDirectory,
  NativeBackupPersistence? persistence,
}) => LocalRestoreCandidateService(
  policy: const SqliteRestoreImagePolicy(),
  supportDirectory: supportDirectory ?? getApplicationSupportDirectory,
  persistence: persistence,
);

LocalRestorer createLocalRestorer({
  required LocalDatabaseStore store,
  SupportDirectory? supportDirectory,
  NativeBackupPersistence? persistence,
}) {
  final directory = supportDirectory ?? getApplicationSupportDirectory;
  final durable = persistence ?? NativeBackupPersistence();
  return LocalRestoreService(
    active: store,
    creator: LocalBackupService(
      source: store,
      validator: const SqliteLocalBackupValidator(),
      supportDirectory: directory,
      persistence: durable,
    ),
    preparer: LocalRestoreCandidateService(
      policy: const SqliteRestoreImagePolicy(),
      supportDirectory: directory,
      persistence: durable,
    ),
    catalog: createLocalBackupCatalog(
      supportDirectory: directory,
      persistence: durable,
    ),
    supportDirectory: directory,
    persistence: durable,
  );
}

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
        // El catálogo conserva copias publicadas anteriores sin migrarlas.
        // validateExistingDatabase ya rechaza versiones futuras o alteradas.
        if (readSchemaVersion(db) < 1) {
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
