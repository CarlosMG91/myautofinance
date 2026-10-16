import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../../../features/synchronization/synchronization.dart';
import '../../../core/persistence/unit_of_work.dart';
import 'schema_policy.dart';

/// Misma política integral EP-004/006, sin migraciones ni funciones de la app.
final class SqlitePortableBackupInspector
    implements PortableBackupImageInspector {
  const SqlitePortableBackupInspector();

  @override
  Future<PortableBackupImage> inspect(String path) async {
    try {
      for (final suffix in ['-wal', '-shm', '-journal']) {
        if (await FileSystemEntity.type('$path$suffix', followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw const DataExportFailure(DataExportFailureCode.invalidSnapshot);
        }
      }
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        validateExistingDatabase(db);
        final version = readSchemaVersion(db);
        if (version != localSchemaVersion) {
          throw const DataExportFailure(DataExportFailureCode.invalidSnapshot);
        }
        final state = db
            .select(
              'SELECT dataset_id,revision FROM database_state WHERE singleton=1',
            )
            .single;
        final tables = <String, int>{};
        for (final row in db.select(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT GLOB 'sqlite_*' ORDER BY name COLLATE BINARY",
        )) {
          final name = row['name'] as String;
          // El esquema validado solo admite los nombres normativos actuales.
          if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
            throw const DataExportFailure(
              DataExportFailureCode.invalidSnapshot,
            );
          }
          tables[name] =
              db.select('SELECT count(*) FROM "$name"').single.values.single
                  as int;
        }
        return PortableBackupImage(
          database: LocalBackupImage(
            state: DatasetState(
              datasetId: state['dataset_id'] as String,
              revision: state['revision'] as int,
            ),
            applicationId:
                db.select('PRAGMA application_id').single.values.single as int,
            schemaVersion: version,
          ),
          tables: tables,
        );
      } finally {
        db.close();
      }
    } catch (_) {
      throw const DataExportFailure(DataExportFailureCode.invalidSnapshot);
    }
  }
}
