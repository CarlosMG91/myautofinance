import 'dart:io';

import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/persistence/unit_of_work.dart';
import '../../../features/synchronization/synchronization.dart';
import 'database_failure.dart';
import 'local_database.dart';
import 'schema_policy.dart';

/// Política de EP-004 aplicada exclusivamente a imágenes privadas de trabajo.
final class SqliteRestoreImagePolicy implements LocalRestoreImagePolicy {
  const SqliteRestoreImagePolicy();
  Never _reject(LocalRestoreCandidateIssue issue) =>
      throw LocalRestoreCandidateFailure(issue);

  @override
  Future<LocalBackupImage> inspect(String path) async {
    try {
      for (final suffix in ['-wal', '-shm', '-journal']) {
        if (await FileSystemEntity.type('$path$suffix', followLinks: false) !=
            FileSystemEntityType.notFound) {
          _reject(LocalRestoreCandidateIssue.incompleteFile);
        }
      }
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        if (db.select('PRAGMA application_id').single.values.single !=
            localApplicationId) {
          _reject(LocalRestoreCandidateIssue.foreignFormat);
        }
        final version = readSchemaVersion(db);
        if (version > localSchemaVersion) {
          _reject(LocalRestoreCandidateIssue.futureSchema);
        }
        if (version < 1) _reject(LocalRestoreCandidateIssue.unsupportedSchema);
        final integrity = db.select('PRAGMA integrity_check');
        if (integrity.length != 1 || integrity.single.values.single != 'ok') {
          _reject(LocalRestoreCandidateIssue.integrityFailure);
        }
        if (db.select('PRAGMA foreign_key_check').isNotEmpty) {
          _reject(LocalRestoreCandidateIssue.foreignKeyFailure);
        }
        final expected = [
          initialStateSchema,
          if (version >= 2) ...categorySchemaObjects,
          if (version >= 3) ...accountSchemaObjects,
          if (version >= 4) ...movementSchemaObjects,
          if (version >= 5)
            ...budgetSchemaObjects.where(
              (sql) =>
                  version < 7 || !sql.contains('categories_budget_history'),
            ),
          if (version >= 6) ...wealthSchemaObjects,
          if (version >= 7) ...categoryReorganizationObjects,
          if (version >= 8) ...importOriginalSchemaObjects,
        ];
        final objects = db.select(
          "SELECT sql FROM sqlite_master WHERE name NOT GLOB 'sqlite_*'",
        );
        if (objects.length != expected.length ||
            expected.any(
              (sql) => !objects.any(
                (o) =>
                    o['sql'] is String &&
                    normalizeSchema(o['sql'] as String) == normalizeSchema(sql),
              ),
            )) {
          _reject(LocalRestoreCandidateIssue.schemaMismatch);
        }
        final states = db.select('SELECT * FROM database_state');
        if (states.length != 1 ||
            states.single['singleton'] != 1 ||
            states.single['dataset_id'] is! String ||
            !RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            ).hasMatch(states.single['dataset_id'] as String) ||
            states.single['revision'] is! int ||
            (states.single['revision'] as int) < 0) {
          _reject(LocalRestoreCandidateIssue.invalidMetadata);
        }
        // No nueva política financiera: valida las consultas y restricciones publicadas.
        try {
          validateExistingDatabase(db);
        } on DatabaseFailure {
          _reject(LocalRestoreCandidateIssue.financialRuleFailure);
        }
        return LocalBackupImage(
          state: DatasetState(
            datasetId: states.single['dataset_id'] as String,
            revision: states.single['revision'] as int,
          ),
          schemaVersion: version,
          applicationId: localApplicationId,
        );
      } finally {
        db.close();
      }
    } on SqliteException catch (e) {
      _reject(
        e.resultCode == 11 || e.resultCode == 26
            ? LocalRestoreCandidateIssue.integrityFailure
            : LocalRestoreCandidateIssue.storageFailure,
      );
    }
  }

  @override
  Future<void> migrate(String stagingPath) async {
    final before = await inspect(stagingPath);
    if (before.schemaVersion == localSchemaVersion) return;
    // Mismo onUpgrade transaccional que la apertura de EP-004; no usa el store
    // activo ni crea respaldos fuera de staging ni reimplementa pasos SQL.
    final db = LocalDatabase(
      NativeDatabase(File(stagingPath), setup: configureConnection),
    );
    try {
      await db.customSelect('SELECT 1').getSingle();
    } catch (_) {
      _reject(LocalRestoreCandidateIssue.migrationFailure);
    } finally {
      await db.close();
    }
    final after = await inspect(stagingPath);
    if (after.schemaVersion != localSchemaVersion ||
        after.state.datasetId != before.state.datasetId ||
        after.state.revision != before.state.revision) {
      _reject(LocalRestoreCandidateIssue.migrationFailure);
    }
  }
}
