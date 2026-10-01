import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'database_failure.dart';
import 'local_database.dart';
import 'schema_policy.dart';

typedef SupportDirectory = Future<Directory> Function();

/// Propietario de una conexión por instalación. app inyectará la misma base
/// en los futuros repositorios. Crear este objeto no abre ni escribe archivos.
final class LocalDatabaseStore {
  LocalDatabaseStore({SupportDirectory? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final SupportDirectory _supportDirectory;
  LocalDatabase? _database;
  Future<LocalDatabase>? _opening;
  Future<void>? _closing;

  String? get databasePath => _databasePath;
  String? _databasePath;
  String? get migrationBackupPath => _migrationBackupPath;
  String? _migrationBackupPath;

  Future<LocalDatabase> open() async {
    if (_closing case final closing?) await closing;
    if (_database case final database?) return database;
    return await (_opening ??= _open()).whenComplete(() => _opening = null);
  }

  Future<LocalDatabase> _open() async {
    LocalDatabase? candidate;
    try {
      final support = await _supportDirectory();
      final directory = Directory(p.join(support.path, 'sqlite'));
      final file = File(p.join(directory.path, 'autofinance.sqlite'));
      _databasePath = file.path;
      _migrationBackupPath = null;
      if (await file.exists()) {
        // Leer la versión antes de que Drift pueda modificar user_version.
        // Una base vacía preexistente es incompatible, no una nueva base.
        final source = sqlite3.open(file.path, mode: OpenMode.readOnly);
        try {
          try {
            validateExistingDatabase(source);
          } on DatabaseFailure {
            rethrow;
          } catch (_) {
            throw const DatabaseFailure(DatabaseFailureCode.incompatible);
          }
          if (readSchemaVersion(source) < localSchemaVersion) {
            final backup = '${file.path}.pre-v1-${const Uuid().v4()}.sqlite';
            // VACUUM INTO captura una imagen consistente, incluido el WAL.
            // El nombre es nuevo y la copia queda conservada si falla el paso.
            source.execute('VACUUM INTO ?', [backup]);
            final check = sqlite3.open(backup, mode: OpenMode.readOnly);
            try {
              validateExistingDatabase(check);
            } finally {
              check.close();
            }
            _migrationBackupPath = backup;
          }
        } finally {
          source.close();
        }
      } else {
        await directory.create(recursive: true);
      }
      candidate = LocalDatabase(
        driftDatabase(
          name: 'autofinance',
          native: DriftNativeOptions(
            databasePath: () async => file.path,
            tempDirectoryPath: () async => directory.path,
            setup: configureConnection,
          ),
        ),
      );
      // Fuerza apertura ahora: errores controlados, no diferidos al primer CRUD.
      await candidate.customSelect('SELECT 1').getSingle();
      _database = candidate;
      return candidate;
    } catch (error) {
      try {
        await candidate?.close();
      } catch (_) {
        // Conservar el error de apertura; nunca borrar/resetear la base.
      }
      if (error is DatabaseFailure) rethrow;
      if (error is SqliteException &&
          (error.resultCode == 11 || error.resultCode == 26)) {
        throw const DatabaseFailure(DatabaseFailureCode.incompatible);
      }
      throw const DatabaseFailure(DatabaseFailureCode.open);
    }
  }

  Future<void> close() =>
      _closing ??= _close().whenComplete(() => _closing = null);

  Future<void> _close() async {
    try {
      if (_opening case final opening?) {
        try {
          await opening;
        } catch (_) {
          return;
        }
      }
      await _database?.close();
      _database = null;
    } catch (_) {
      throw const DatabaseFailure(DatabaseFailureCode.close);
    }
  }
}
