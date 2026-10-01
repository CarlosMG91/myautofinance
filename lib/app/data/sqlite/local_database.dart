import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database_failure.dart';
import 'schema_policy.dart';

part 'local_database.g.dart';

@DriftDatabase(include: {'schema.drift'})
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await transaction(() async {
        final legacy = await customSelect(
          "SELECT name FROM sqlite_master WHERE name = 'database_state'",
        ).get();
        if (legacy.isEmpty) {
          await migrator.createAll();
          await customStatement(
            'INSERT INTO database_state(singleton, dataset_id, revision) '
            'VALUES (1, ?, 0)',
            [const Uuid().v4()],
          );
        } else {
          // Único paso 0 → 1: conservar linaje, añadir revisión técnica cero.
          // Las versiones siguientes deberán añadir pasos consecutivos, con
          // SQL/modelos del paso y respaldo previo, nunca recrear datos.
          await customStatement(
            'ALTER TABLE database_state RENAME TO previous_database_state',
          );
          await migrator.createAll();
          await customStatement(
            'INSERT INTO database_state(singleton, dataset_id, revision) '
            'SELECT singleton, dataset_id, 0 FROM previous_database_state',
          );
          await customStatement('DROP TABLE previous_database_state');
        }
        await customStatement('PRAGMA application_id = $localApplicationId');
        await _checkIntegrity();
      });
    },
    onUpgrade: (_, from, to) async {
      // No hay versiones publicadas anteriores a v1. Nunca usar createAll
      // como sustituto de una migración desconocida.
      throw const DatabaseFailure(DatabaseFailureCode.incompatible);
    },
    beforeOpen: (_) async {
      final enabled = await customSelect('PRAGMA foreign_keys').getSingle();
      if (enabled.data.values.single != 1) {
        throw const DatabaseFailure(DatabaseFailureCode.open);
      }
      await _checkIntegrity();
    },
  );

  Future<void> _checkIntegrity() async {
    final integrity = await customSelect('PRAGMA integrity_check').get();
    final foreignKeys = await customSelect('PRAGMA foreign_key_check').get();
    if (integrity.length != 1 ||
        integrity.single.data.values.single != 'ok' ||
        foreignKeys.isNotEmpty) {
      throw const DatabaseFailure(DatabaseFailureCode.incompatible);
    }
  }
}
