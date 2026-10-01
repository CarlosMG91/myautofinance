import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:drift/native.dart';
// API necesaria para comprobar la causa SQLite del ejecutor en isolate.
// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/database_failure.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const dataset = '11111111-2222-4333-8444-555555555555';

void createPrevious(File file) {
  file.parent.createSync(recursive: true);
  final db = sqlite3.open(file.path);
  try {
    db.execute(syntheticPreviousSchema);
    db.execute('PRAGMA application_id = $localApplicationId');
    db.execute(
      'INSERT INTO database_state(singleton, dataset_id) VALUES (1, ?)',
      [dataset],
    );
  } finally {
    db.close();
  }
}

Future<void> checkForeignKeys(LocalDatabase db) async {
  expect(
    (await db.customSelect('PRAGMA foreign_keys').getSingle())
        .data
        .values
        .single,
    1,
  );
  await db.customStatement(
    'CREATE TEMP TABLE fk_parent(id INTEGER PRIMARY KEY)',
  );
  await db.customStatement(
    'CREATE TEMP TABLE fk_child(parent_id INTEGER REFERENCES fk_parent(id))',
  );
  await expectLater(
    db.customStatement('INSERT INTO fk_child VALUES (99)'),
    throwsA(
      isA<DriftRemoteException>().having(
        (error) => error.remoteCause,
        'causa SQLite',
        isA<SqliteException>().having(
          (error) => error.extendedResultCode,
          'FK',
          787,
        ),
      ),
    ),
  );
  await db.customStatement('INSERT INTO fk_parent VALUES (99)');
  await db.customStatement('INSERT INTO fk_child VALUES (99)');
  await expectLater(
    db.customStatement('DELETE FROM fk_parent WHERE id=99'),
    throwsA(
      isA<DriftRemoteException>().having(
        (error) => error.remoteCause,
        'causa SQLite',
        isA<SqliteException>().having(
          (error) => error.extendedResultCode,
          'FK',
          787,
        ),
      ),
    ),
  );
}

class FailingMigrationDatabase extends LocalDatabase {
  FailingMigrationDatabase(super.executor);

  @override
  MigrationStrategy get migration {
    final strategy = super.migration;
    return MigrationStrategy(
      onCreate: (m) => transaction(() async {
        await strategy.onCreate(m);
        throw StateError('Fallo sintético después de transformar los datos');
      }),
      beforeOpen: strategy.beforeOpen,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late File file;
  late LocalDatabaseStore store;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('autofinance-synthetic-');
    file = File(p.join(support.path, 'sqlite', 'autofinance.sqlite'));
    store = LocalDatabaseStore(supportDirectory: () async => support);
  });
  tearDown(() async {
    await store.close();
    await support.delete(recursive: true);
  });

  test(
    'Crea en soporte explícito; cierre, reapertura y FK por conexión',
    () async {
      final db = await store.open();
      expect(store.databasePath, file.path);
      expect(file.existsSync(), isTrue);
      final initial = await db.select(db.databaseState).getSingle();
      expect(initial.singleton, 1);
      expect(initial.revision, 0);
      expect(
        initial.datasetId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      await checkForeignKeys(db);
      await db.customStatement('UPDATE database_state SET revision = 7');
      await store.close();
      await store.close();
      final reopened = await store.open();
      expect(reopened, isNot(same(db)));
      final state = await reopened.select(reopened.databaseState).getSingle();
      expect(state.datasetId, initial.datasetId);
      expect(state.revision, 7);
      await checkForeignKeys(reopened);
      expect(
        (await reopened.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        1,
      );
    },
  );

  test(
    'Aperturas concurrentes comparten instancia; cierre durante apertura',
    () async {
      final connections = await Future.wait([store.open(), store.open()]);
      expect(connections[0], same(connections[1]));
      await store.close();
      final opening = store.open();
      await store.close();
      await opening;
      final db = await store.open();
      expect((await db.select(db.databaseState).get()).length, 1);
    },
  );

  test('Snapshot Drift v1 coincide con creación limpia y política', () async {
    final snapshot = jsonDecode(
      File('drift_schemas/autofinance/drift_schema_v1.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final sql = snapshot['fixed_sql'][0]['sql'][0]['sql'] as String;
    final expected = sqlite3.openInMemory();
    try {
      expected.execute(sql);
      final expectedSql =
          expected
                  .select(
                    "SELECT sql FROM sqlite_master WHERE name='database_state'",
                  )
                  .single['sql']
              as String;
      expect(normalizeSchema(expectedSql), normalizeSchema(initialStateSchema));
      final db = await store.open();
      final actualSql =
          (await db
                  .customSelect(
                    "SELECT sql FROM sqlite_master WHERE name='database_state'",
                  )
                  .getSingle())
              .read<String>('sql');
      expect(normalizeSchema(actualSql), normalizeSchema(expectedSql));
      final raw = sqlite3.open(file.path, mode: OpenMode.readOnly);
      try {
        validateExistingDatabase(raw);
      } finally {
        raw.close();
      }
    } finally {
      expected.close();
    }
  });

  test('Migra v0 sintética preservando UUID y respaldo recuperable', () async {
    createPrevious(file);
    final db = await store.open();
    final state = await db.select(db.databaseState).getSingle();
    expect(state.datasetId, dataset);
    expect(state.revision, 0);
    expect(store.migrationBackupPath, isNotNull);
    final backup = sqlite3.open(
      store.migrationBackupPath!,
      mode: OpenMode.readOnly,
    );
    try {
      validateExistingDatabase(backup);
      expect(readSchemaVersion(backup), 0);
      expect(
        backup
            .select('SELECT dataset_id FROM database_state')
            .single
            .values
            .single,
        dataset,
      );
    } finally {
      backup.close();
    }
    await store.close();
    await store.open();
    expect(store.migrationBackupPath, isNull);
  });

  test('Respaldo de migración incluye datos aún en WAL', () async {
    createPrevious(file);
    final writer = sqlite3.open(file.path);
    try {
      writer.execute('PRAGMA journal_mode=WAL');
      writer.execute('PRAGMA wal_autocheckpoint=0');
      const updated = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
      writer.execute('UPDATE database_state SET dataset_id=?', [updated]);
      expect(File('${file.path}-wal').lengthSync(), greaterThan(0));
      final db = await store.open();
      expect(
        (await db.select(db.databaseState).getSingle()).datasetId,
        updated,
      );
      final backup = sqlite3.open(store.migrationBackupPath!);
      try {
        expect(
          backup
              .select('SELECT dataset_id FROM database_state')
              .single
              .values
              .single,
          updated,
        );
        expect(readSchemaVersion(backup), 0);
      } finally {
        backup.close();
      }
    } finally {
      writer.close();
    }
  });

  test('Fallo intermedio revierte datos, esquema y versión', () async {
    createPrevious(file);
    final db = FailingMigrationDatabase(
      NativeDatabase(file, setup: configureConnection),
    );
    try {
      await expectLater(db.customSelect('SELECT 1').get(), throwsStateError);
    } finally {
      await db.close();
    }
    final original = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      validateExistingDatabase(original);
      expect(readSchemaVersion(original), 0);
      expect(
        original
            .select('SELECT dataset_id FROM database_state')
            .single
            .values
            .single,
        dataset,
      );
    } finally {
      original.close();
    }
    await store.open();
  });

  test('CHECK rechaza revisión negativa, REAL y UUID no canónico', () async {
    final db = await store.open();
    for (final sql in [
      'UPDATE database_state SET revision=-1',
      'UPDATE database_state SET revision=1.5',
      "UPDATE database_state SET dataset_id='INVALID'",
      'INSERT INTO database_state SELECT 2,dataset_id,0 FROM database_state',
    ]) {
      await expectLater(
        db.customStatement(sql),
        throwsA(
          isA<DriftRemoteException>().having(
            (error) => error.remoteCause,
            'causa SQLite',
            isA<SqliteException>().having(
              (error) => error.extendedResultCode,
              'CHECK',
              275,
            ),
          ),
        ),
      );
    }
    expect((await db.select(db.databaseState).getSingle()).revision, 0);
  });

  for (final variant in [
    'future',
    'foreign',
    'empty',
    'corrupt',
    'bad-schema',
    'bad-data',
  ]) {
    test('Rechaza $variant sin cambiar bytes y permite recuperar apertura', () async {
      file.parent.createSync(recursive: true);
      if (variant == 'corrupt') {
        file.writeAsStringSync('archivo sintético que no es SQLite');
      } else if (variant == 'empty') {
        file.writeAsBytesSync([]);
      } else {
        final raw = sqlite3.open(file.path);
        try {
          if (variant == 'future') {
            raw.execute('CREATE TABLE future_data(secret TEXT)');
            raw.execute("INSERT INTO future_data VALUES ('synthetic')");
            raw.execute('PRAGMA user_version=99');
          } else if (variant == 'foreign') {
            raw.execute('CREATE TABLE foreign_data(id INTEGER)');
          } else {
            raw.execute(
              variant == 'bad-schema'
                  ? 'CREATE TABLE database_state(singleton INTEGER, dataset_id TEXT, revision INTEGER)'
                  : initialStateSchema,
            );
            raw.execute('PRAGMA application_id=$localApplicationId');
            raw.execute('PRAGMA user_version=1');
            if (variant == 'bad-data') {
              raw.execute('PRAGMA ignore_check_constraints=ON');
              raw.execute(
                "INSERT INTO database_state VALUES (1, 'invalid', -1)",
              );
            }
          }
        } finally {
          raw.close();
        }
      }
      final bytes = file.readAsBytesSync();
      await expectLater(
        store.open(),
        throwsA(
          isA<DatabaseFailure>().having(
            (error) => error.code,
            'código controlado',
            variant == 'future'
                ? DatabaseFailureCode.futureVersion
                : DatabaseFailureCode.incompatible,
          ),
        ),
      );
      expect(file.readAsBytesSync(), bytes);
      expect(store.migrationBackupPath, isNull);
      await store.close();
      // Solo la prueba elimina su archivo sintético; el servicio nunca lo hace.
      file.deleteSync();
      await store.open();
    });
  }

  test('Error de almacenamiento controlado y reintentable', () async {
    final inaccessible = File(p.join(support.path, 'not-a-directory'))
      ..writeAsStringSync('synthetic');
    var fail = true;
    store = LocalDatabaseStore(
      supportDirectory: () async =>
          fail ? Directory(inaccessible.path) : support,
    );
    await expectLater(
      store.open(),
      throwsA(
        isA<DatabaseFailure>().having(
          (error) => error.code,
          'código',
          DatabaseFailureCode.open,
        ),
      ),
    );
    fail = false;
    await store.open();
  });
}
