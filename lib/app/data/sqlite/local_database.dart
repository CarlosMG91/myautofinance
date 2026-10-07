import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database_failure.dart';
import 'schema_policy.dart';
import '../../../core/persistence/unit_of_work.dart';

part 'local_database.g.dart';

@DriftDatabase(include: {'schema.drift'})
class LocalDatabase extends _$LocalDatabase implements UnitOfWork {
  LocalDatabase(super.executor);

  final Object _workKey = Object();
  bool get inUnitOfWork => Zone.current[_workKey] == true;
  bool _writesBlocked = false;
  int _pendingWrites = 0;
  Completer<void>? _writesDrained;

  /// Cierra la admisión antes de esperar a las transacciones ya admitidas.
  Future<void> blockWritesForRestore() async {
    _writesBlocked = true;
    if (_pendingWrites > 0) {
      await (_writesDrained ??= Completer<void>()).future;
    }
  }

  void resumeWritesAfterRestore() => _writesBlocked = false;

  @override
  Future<DatasetState> readState() async {
    final row = await customSelect(
      'SELECT dataset_id,revision FROM database_state WHERE singleton=1',
    ).getSingle();
    return DatasetState(
      datasetId: row.read<String>('dataset_id'),
      revision: row.read<int>('revision'),
    );
  }

  @override
  Future<T> run<T>(Future<T> Function() operation) =>
      writeTransaction(operation);

  Future<T> writeTransaction<T>(Future<T> Function() operation) {
    if (inUnitOfWork) return transaction(operation, requireNew: true);
    if (_writesBlocked) {
      return Future.error(const DatabaseFailure(DatabaseFailureCode.restoring));
    }
    _pendingWrites++;
    return transaction(
      () => runZoned(() async {
        await customStatement('UPDATE local_mutation SET dirty=0');
        final result = await operation();
        await _checkIntegrity();
        await customStatement(
          'UPDATE database_state SET revision=revision+1 WHERE singleton=1 AND (SELECT dirty FROM local_mutation)=1',
        );
        final tracked = await customSelect(
          'SELECT changes() AS changed, (SELECT dirty FROM local_mutation) AS dirty',
        ).getSingle();
        if (tracked.read<int>('dirty') == 1 &&
            tracked.read<int>('changed') != 1) {
          throw StateError('No se pudo registrar la revisión local.');
        }
        return result;
      }, zoneValues: {_workKey: true}),
    ).whenComplete(() {
      if (--_pendingWrites == 0) {
        _writesDrained?.complete();
        _writesDrained = null;
      }
    });
  }

  // TEMP objects stay on this connection, are rolled back with savepoints and
  // never become part of the shared schema or its copies.
  Future<void> _installMutationTracking() async {
    await customStatement(
      'CREATE TEMP TABLE local_mutation(dirty INTEGER NOT NULL)',
    );
    await customStatement('INSERT INTO local_mutation VALUES(0)');
    for (final table in [
      'categories',
      'accounts',
      'account_liquidity_periods',
      'movements',
      'import_batches',
      'import_rows',
      'import_batch_metadata',
      'import_row_originals',
      'budgets',
      'wealth_snapshots',
      'wealth_values',
    ]) {
      final columns = await customSelect('PRAGMA table_info($table)').get();
      final changed = columns
          .where(
            (c) =>
                !['created_at', 'updated_at'].contains(c.read<String>('name')),
          )
          .map(
            (c) =>
                'NEW.${c.read<String>('name')} IS NOT OLD.${c.read<String>('name')}',
          )
          .join(' OR ');
      for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
        await customStatement(
          'CREATE TEMP TRIGGER track_${table}_${event.toLowerCase()} AFTER $event ON main.$table ${event == 'UPDATE' ? 'WHEN $changed' : ''} BEGIN UPDATE local_mutation SET dirty=1; END',
        );
      }
    }
  }

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
        for (final sql
            in legacy.isNotEmpty ? wealthSchemaObjects : <String>[]) {
          await customStatement(sql);
        }
        if (legacy.isNotEmpty) await _migrateCategoryReorganization();
        for (final sql
            in legacy.isNotEmpty ? importOriginalSchemaObjects : <String>[]) {
          await customStatement(sql);
        }
        await _checkIntegrity();
      });
    },
    onUpgrade: (_, from, to) async {
      if (from < 1 || from > 7 || to != 8) {
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
        for (final sql in from < 5 ? budgetSchemaObjects : <String>[]) {
          await customStatement(sql);
        }
        for (final sql in from < 6 ? wealthSchemaObjects : <String>[]) {
          await customStatement(sql);
        }
        if (from < 7) await _migrateCategoryReorganization();
        for (final sql in importOriginalSchemaObjects) {
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
      await _installMutationTracking();
    },
  );

  Future<void> _migrateCategoryReorganization() async {
    await customStatement('DROP TRIGGER categories_budget_history');
    for (final sql in categoryReorganizationObjects) {
      await customStatement(sql);
    }
  }

  Future<void> _checkIntegrity() async {
    final integrity = await customSelect('PRAGMA integrity_check').get();
    final foreignKeys = await customSelect('PRAGMA foreign_key_check').get();
    if (integrity.length != 1 ||
        integrity.single.data.values.single != 'ok' ||
        foreignKeys.isNotEmpty ||
        (await customSelect(categoryIntegrityErrors).get()).isNotEmpty ||
        (await customSelect(wealthIntegrityErrors).get()).isNotEmpty ||
        (await customSelect(budgetIntegrityErrors).get()).isNotEmpty ||
        (await customSelect(movementIntegrityErrors).get()).isNotEmpty ||
        (await customSelect(accountCoverageErrors).get()).isNotEmpty) {
      throw const DatabaseFailure(DatabaseFailureCode.incompatible);
    }
  }
}
