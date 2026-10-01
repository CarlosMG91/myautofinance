import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database_failure.dart';
import 'schema_policy.dart';

part 'local_database.g.dart';

@DriftDatabase(include: {'schema.drift'})
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase(super.executor);

  @override
  int get schemaVersion => localSchemaVersion;

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
          // Paso sintético 0 → 1, seguido del paso físico 1 → 2.
          await customStatement(
            'ALTER TABLE database_state RENAME TO previous_database_state',
          );
          await customStatement(initialStateSchema);
          await customStatement(
            'INSERT INTO database_state(singleton, dataset_id, revision) '
            'SELECT singleton, dataset_id, 0 FROM previous_database_state',
          );
          await customStatement('DROP TABLE previous_database_state');
          for (final sql in categorySchemaObjects) {
            await customStatement(sql);
          }
        }
        if (legacy.isNotEmpty) {
          for (final sql in accountSchemaObjects) {
            await customStatement(sql);
          }
        }
        await customStatement('PRAGMA application_id = $localApplicationId');
        if (legacy.isNotEmpty) {
          for (final sql in movementSchemaObjects) {
            await customStatement(sql);
          }
        }
        for (final sql
            in legacy.isNotEmpty ? budgetSchemaObjects : <String>[]) {
          await customStatement(sql);
        }
        await _checkIntegrity();
      });
    },
    onUpgrade: (_, from, to) async {
      if (from < 1 || from > 4 || to != 5) {
        throw const DatabaseFailure(DatabaseFailureCode.incompatible);
      }
      await transaction(() async {
        if (from == 1) {
          for (final sql in categorySchemaObjects) {
            await customStatement(sql);
          }
        }
        for (final sql in from < 3 ? accountSchemaObjects : <String>[]) {
          await customStatement(sql);
        }
        for (final sql in from < 4 ? movementSchemaObjects : <String>[]) {
          await customStatement(sql);
        }
        for (final sql in budgetSchemaObjects) {
          await customStatement(sql);
        }
        await _checkIntegrity();
      });
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
        foreignKeys.isNotEmpty ||
        (await customSelect(budgetIntegrityErrors).get()).isNotEmpty ||
        (await customSelect(movementIntegrityErrors).get()).isNotEmpty ||
        (await customSelect(accountCoverageErrors).get()).isNotEmpty) {
      throw const DatabaseFailure(DatabaseFailureCode.incompatible);
    }
  }
}
