import 'dart:io';
import 'dart:async';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'database_failure.dart';
import 'local_database.dart';
import 'schema_policy.dart';
import '../../../core/persistence/unit_of_work.dart';
import '../../../features/synchronization/synchronization.dart';

typedef SupportDirectory = Future<Directory> Function();

/// Propietario de una conexión por instalación. app inyectará la misma base
/// en los futuros repositorios. Crear este objeto no abre ni escribe archivos.
final class LocalDatabaseStore
    implements LocalBackupSource, LocalRestoreActiveDatabase {
  LocalDatabaseStore({SupportDirectory? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final SupportDirectory _supportDirectory;
  LocalDatabase? _database;
  Future<LocalDatabase>? _opening;
  Future<void>? _closing;
  final Object _restoreKey = Object();
  bool _restoring = false;
  bool _recoveryRequired = false;

  @override
  void requireRecovery() => _recoveryRequired = true;

  @override
  Future<T> exclusivelyForRestore<T>(Future<T> Function() action) async {
    if (_restoring || _recoveryRequired || (_database?.inUnitOfWork ?? false)) {
      throw const DatabaseFailure(DatabaseFailureCode.restoring);
    }
    _restoring = true;
    try {
      if (_opening case final opening?) {
        try {
          await opening;
        } catch (_) {
          /* classify via canOpenExisting */
        }
      }
      await _database?.blockWritesForRestore();
      return await runZoned(action, zoneValues: {_restoreKey: true});
    } finally {
      _restoring = false;
      if (!_recoveryRequired) _database?.resumeWritesAfterRestore();
    }
  }

  @override
  Future<bool> canOpenExisting() async {
    final support = await _supportDirectory();
    final file = File(p.join(support.path, 'sqlite', 'autofinance.sqlite'));
    if (!await file.exists()) return false;
    try {
      await reopenAndValidate();
      return true;
    } on DatabaseFailure catch (e) {
      if (e.code == DatabaseFailureCode.incompatible) return false;
      rethrow; // I/O y versiones futuras no autorizan aislar una activa.
    } on SqliteException catch (e) {
      if (e.resultCode == 11 || e.resultCode == 26) return false;
      rethrow;
    }
  }

  @override
  Future<LocalBackupImage> reopenAndValidate() async {
    final db = await open();
    await db.blockWritesForRestore();
    final check = sqlite3.open(_databasePath!, mode: OpenMode.readOnly);
    try {
      validateExistingDatabase(check);
      return LocalBackupImage(
        state: await db.readState(),
        schemaVersion: readSchemaVersion(check),
        applicationId: localApplicationId,
      );
    } finally {
      check.close();
    }
  }

  String? get databasePath => _databasePath;
  String? _databasePath;
  String? get migrationBackupPath => _migrationBackupPath;
  String? _migrationBackupPath;

  @override
  Future<LocalBackup> createConsistentBackup() async {
    final database = await open();
    if (database.inUnitOfWork) {
      throw const DatabaseFailure(DatabaseFailureCode.backup);
    }
    // Private new directory: never overwrite the active base or a prior copy.
    Directory? staging;
    try {
      final directory = await Directory(
        p.join(p.dirname(_databasePath!), 'copies'),
      ).create(recursive: true);
      staging = await directory.createTemp('snapshot-');
      final file = File(p.join(staging.path, 'autofinance.sqlite'));
      await database.customStatement('VACUUM INTO ?', [file.path]);
      final copy = sqlite3.open(file.path, mode: OpenMode.readOnly);
      try {
        validateExistingDatabase(copy);
        final row = copy
            .select(
              'SELECT dataset_id,revision FROM database_state WHERE singleton=1',
            )
            .single;
        return LocalBackup(
          path: file.path,
          state: DatasetState(
            datasetId: row['dataset_id'] as String,
            revision: row['revision'] as int,
          ),
        );
      } finally {
        copy.close();
      }
    } catch (_) {
      try {
        await staging?.delete(recursive: true);
      } catch (_) {
        /* Only our incomplete copy. */
      }
      throw const DatabaseFailure(DatabaseFailureCode.backup);
    }
  }

  Future<LocalDatabase> open() async {
    if (_recoveryRequired || _restoring && Zone.current[_restoreKey] != true) {
      throw const DatabaseFailure(DatabaseFailureCode.restoring);
    }
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
      // MA-TSK-056 resolverá el diario antes de permitir una apertura normal.
      // Hasta entonces nunca crear una base vacía en medio de un intercambio.
      if (Zone.current[_restoreKey] != true) {
        final restore = Directory(
          p.join(directory.path, 'local-backups', 'restore'),
        );
        if (await restore.exists()) {
          await for (final item in restore.list(
            recursive: true,
            followLinks: false,
          )) {
            if (p.basename(item.path).startsWith('journal-')) {
              throw const DatabaseFailure(DatabaseFailureCode.restoring);
            }
          }
        }
      }
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
            final backup =
                '${file.path}.pre-v$localSchemaVersion-${const Uuid().v4()}.sqlite';
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

  @override
  Future<void> close() {
    if (_restoring && Zone.current[_restoreKey] != true) {
      return Future.error(const DatabaseFailure(DatabaseFailureCode.restoring));
    }
    return _closing ??= _close().whenComplete(() => _closing = null);
  }

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
