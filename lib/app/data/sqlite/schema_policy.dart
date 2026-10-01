import 'package:sqlite3/common.dart';

import 'database_failure.dart';

const localSchemaVersion = 2;
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
    "SELECT type, name, sql FROM sqlite_master WHERE name NOT GLOB 'sqlite_*'",
  );
  if (id != localApplicationId ||
      version < 0 ||
      objects.length != (version < 2 ? 1 : 5)) {
    throw const DatabaseFailure(DatabaseFailureCode.incompatible);
  }
  final object = objects.singleWhere(
    (o) => o['name'] == 'database_state',
    orElse: () => throw const DatabaseFailure(DatabaseFailureCode.incompatible),
  );
  if (version == 2) {
    for (final sql in categorySchemaObjects) {
      if (!objects.any(
        (o) => normalizeSchema(o['sql'] as String) == normalizeSchema(sql),
      )) {
        throw const DatabaseFailure(DatabaseFailureCode.incompatible);
      }
    }
  }
  final expected = version == 0 ? syntheticPreviousSchema : initialStateSchema;
  if (object['type'] != 'table' ||
      object['name'] != 'database_state' ||
      normalizeSchema(object['sql'] as String) != normalizeSchema(expected)) {
    throw const DatabaseFailure(DatabaseFailureCode.incompatible);
  }
  validateIntegrity(db);
  if (version == 2) {
    final valid = db.select('''
WITH RECURSIVE tree(id,depth) AS (
 SELECT id,1 FROM categories WHERE parent_id IS NULL
 UNION ALL SELECT c.id,t.depth+1 FROM categories c JOIN tree t
 ON c.parent_id=t.id WHERE t.depth<3
) SELECT (SELECT count(*) FROM tree) = (SELECT count(*) FROM categories) AS valid
''').single['valid'];
    if (valid != 1) {
      throw const DatabaseFailure(DatabaseFailureCode.incompatible);
    }
  }
  final states = db.select('SELECT * FROM database_state');
  if (states.length != 1 ||
      states.single['singleton'] != 1 ||
      states.single['dataset_id'] is! String ||
      !RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          .hasMatch(states.single['dataset_id'] as String) ||
      (version >= 1 &&
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
    "SELECT name FROM sqlite_master WHERE name NOT GLOB 'sqlite_*'",
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

const categorySchemaObjects = <String>[
  '''CREATE TABLE "categories" ("id" TEXT NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length("replace"(id, '-', '')) = 32 AND "replace"(id, '-', '') NOT GLOB '*[^0-9a-f]*'), "parent_id" TEXT REFERENCES categories(id)ON UPDATE RESTRICT ON DELETE RESTRICT, "name" TEXT NOT NULL CHECK (length(trim(name)) > 0), "is_income" INTEGER CHECK (is_income IN (0, 1)), "archived" INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)), "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, CHECK((parent_id IS NULL AND is_income IS NOT NULL)OR(parent_id IS NOT NULL AND is_income IS NULL)));''',
  '''CREATE INDEX categories_parent ON categories (parent_id)''',
  '''CREATE TRIGGER categories_insert BEFORE INSERT ON categories BEGIN SELECT RAISE (ABORT, 'category_cycle') WHERE NEW.parent_id = NEW.id OR EXISTS (WITH RECURSIVE ancestors (id, parent_id) AS (SELECT id, parent_id FROM categories WHERE id = NEW.parent_id UNION SELECT c.id, c.parent_id FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id) SELECT 1 FROM ancestors WHERE id = NEW.id);SELECT RAISE (ABORT, 'category_depth') WHERE (WITH RECURSIVE ancestors (id, parent_id) AS (SELECT id, parent_id FROM categories WHERE id = NEW.parent_id UNION ALL SELECT c.id, c.parent_id FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id) SELECT count(*) FROM ancestors) + (WITH RECURSIVE descendants (id, depth) AS (SELECT NEW.id, 1 UNION ALL SELECT c.id, d.depth + 1 FROM categories AS c JOIN descendants AS d ON c.parent_id = d.id) SELECT max(depth) FROM descendants) > 3;END''',
  '''CREATE TRIGGER categories_update BEFORE UPDATE OF parent_id ON categories BEGIN SELECT RAISE (ABORT, 'category_cycle') WHERE NEW.parent_id = NEW.id OR EXISTS (WITH RECURSIVE ancestors (id, parent_id) AS (SELECT id, parent_id FROM categories WHERE id = NEW.parent_id UNION SELECT c.id, c.parent_id FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id) SELECT 1 FROM ancestors WHERE id = NEW.id);SELECT RAISE (ABORT, 'category_depth') WHERE (WITH RECURSIVE ancestors (id, parent_id) AS (SELECT id, parent_id FROM categories WHERE id = NEW.parent_id UNION ALL SELECT c.id, c.parent_id FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id) SELECT count(*) FROM ancestors) + (WITH RECURSIVE descendants (id, depth) AS (SELECT NEW.id, 1 UNION ALL SELECT c.id, d.depth + 1 FROM categories AS c JOIN descendants AS d ON c.parent_id = d.id) SELECT max(depth) FROM descendants) > 3;END''',
];
