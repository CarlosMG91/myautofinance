import 'package:sqlite3/common.dart';

import 'database_failure.dart';

const localSchemaVersion = 1;
// ASCII AFNC: identifica este formato, independientemente del dataset_id.
const localApplicationId = 0x41464e43;

/// v0 es exclusivamente un predecesor sintético para ensayar migraciones.
/// No se acepta una base genérica con user_version=0.
const syntheticPreviousSchema = '''
CREATE TABLE database_state (
  singleton INTEGER NOT NULL PRIMARY KEY CHECK (singleton = 1),
  dataset_id TEXT NOT NULL CHECK (
    length(dataset_id) = 36 AND
    substr(dataset_id, 9, 1) = '-' AND substr(dataset_id, 14, 1) = '-' AND
    substr(dataset_id, 19, 1) = '-' AND substr(dataset_id, 24, 1) = '-' AND
    length(replace(dataset_id, '-', '')) = 32 AND
    replace(dataset_id, '-', '') NOT GLOB '*[^0-9a-f]*'
  )
)
''';

// Debe coincidir con schema.drift; la prueba compara el snapshot exportado.
const initialStateSchema = '''
CREATE TABLE database_state (
  singleton INTEGER NOT NULL PRIMARY KEY CHECK (singleton = 1),
  dataset_id TEXT NOT NULL CHECK (
    length(dataset_id) = 36 AND
    substr(dataset_id, 9, 1) = '-' AND substr(dataset_id, 14, 1) = '-' AND
    substr(dataset_id, 19, 1) = '-' AND substr(dataset_id, 24, 1) = '-' AND
    length(replace(dataset_id, '-', '')) = 32 AND
    replace(dataset_id, '-', '') NOT GLOB '*[^0-9a-f]*'
  ),
  revision INTEGER NOT NULL CHECK (typeof(revision) = 'integer' AND revision >= 0)
)
''';

String normalizeSchema(String sql) =>
    sql.replaceAll(RegExp('["`;\\s]'), '').toLowerCase();

int readSchemaVersion(CommonDatabase db) =>
    db.select('PRAGMA user_version').single.values.single as int;

/// Solo lecturas. Se ejecuta antes de cualquier PRAGMA que pueda escribir.
void validateExistingDatabase(CommonDatabase db) {
  final version = readSchemaVersion(db);
  if (version > localSchemaVersion) {
    throw const DatabaseFailure(DatabaseFailureCode.futureVersion);
  }
  final id = db.select('PRAGMA application_id').single.values.single;
  final objects = db.select(
    "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
  );
  if (id != localApplicationId || version < 0 || objects.length != 1) {
    throw const DatabaseFailure(DatabaseFailureCode.incompatible);
  }
  final object = objects.single;
  final expected = version == 0 ? syntheticPreviousSchema : initialStateSchema;
  if (object['type'] != 'table' ||
      object['name'] != 'database_state' ||
      normalizeSchema(object['sql'] as String) != normalizeSchema(expected)) {
    throw const DatabaseFailure(DatabaseFailureCode.incompatible);
  }
  validateIntegrity(db);
  final states = db.select('SELECT * FROM database_state');
  if (states.length != 1 ||
      states.single['singleton'] != 1 ||
      states.single['dataset_id'] is! String ||
      !RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          .hasMatch(states.single['dataset_id'] as String) ||
      (version == 1 &&
          (states.single['revision'] is! int ||
              (states.single['revision'] as int) < 0))) {
    throw const DatabaseFailure(DatabaseFailureCode.incompatible);
  }
}

void validateIntegrity(CommonDatabase db) {
  final integrity = db.select('PRAGMA integrity_check');
  if (integrity.length != 1 ||
      integrity.single.values.single != 'ok' ||
      db.select('PRAGMA foreign_key_check').isNotEmpty) {
    throw const DatabaseFailure(DatabaseFailureCode.incompatible);
  }
}

/// Drift llama setup en cada conexión SQLite, antes de crear/migrar.
void configureConnection(CommonDatabase db) {
  final objects = db.select(
    "SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
  );
  // Una nueva conexión vacía tiene versión/id cero. Lo demás debe reconocerse.
  if (objects.isNotEmpty ||
      readSchemaVersion(db) != 0 ||
      db.select('PRAGMA application_id').single.values.single != 0) {
    validateExistingDatabase(db);
  }
  db.execute('PRAGMA foreign_keys = ON');
  if (db.select('PRAGMA foreign_keys').single.values.single != 1) {
    throw const DatabaseFailure(DatabaseFailureCode.open);
  }
}
