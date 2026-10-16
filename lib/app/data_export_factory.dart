import 'dart:io';

import '../features/synchronization/synchronization.dart';
import '../features/synchronization/data/csv_data_exporter.dart';
import 'data/sqlite/local_database_store.dart';
import 'data/sqlite/sqlite_data_export_source.dart';

/// Composición para T06; no exporta en arranque ni accede a Drive.
DataExporter createDataExporter({
  required LocalDatabaseStore store,
  Future<Directory> Function()? temporaryDirectory,
}) => CsvDataExporter(
  source: SqliteDataExportSource(store),
  temporaryDirectory: temporaryDirectory,
);
