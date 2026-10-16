import 'dart:io';

import '../features/synchronization/synchronization.dart';
import '../features/synchronization/data/portable_backup_exporter.dart';
import 'data/sqlite/local_database_store.dart';
import 'data/sqlite/sqlite_portable_backup_inspector.dart';

/// Composición para T06; no inicia exportaciones, retención ni acceso a Drive.
PortableBackupExporter createPortableBackupExporter({
  required LocalDatabaseStore store,
  Future<Directory> Function()? temporaryDirectory,
}) => PortableSqliteBackupExporter(
  source: store,
  inspector: const SqlitePortableBackupInspector(),
  temporaryDirectory: temporaryDirectory,
);
