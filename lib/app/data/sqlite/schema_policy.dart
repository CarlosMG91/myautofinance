import 'package:sqlite3/common.dart';

import 'database_failure.dart';
import 'concept_search_key.dart';
import 'movement_subtotal.dart';

const localSchemaVersion = 7;
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
      objects.length !=
          (version < 2
              ? 1
              : version == 2
              ? 5
              : 5 +
                    accountSchemaObjects.length +
                    (version >= 4 ? movementSchemaObjects.length : 0) +
                    (version >= 5 ? budgetSchemaObjects.length : 0) +
                    (version >= 6 ? wealthSchemaObjects.length : 0) +
                    (version >= 7
                        ? categoryReorganizationObjects.length - 1
                        : 0))) {
    throw const DatabaseFailure(DatabaseFailureCode.incompatible);
  }
  final object = objects.singleWhere(
    (o) => o['name'] == 'database_state',
    orElse: () => throw const DatabaseFailure(DatabaseFailureCode.incompatible),
  );
  if (version >= 2) {
    // Antes de las consultas recursivas de presupuestos: incluso una imagen
    // manipulada con ciclos debe rechazarse sin recursión ilimitada.
    if (db.select(categoryIntegrityErrors).isNotEmpty) {
      throw const DatabaseFailure(DatabaseFailureCode.incompatible);
    }
    for (final sql in categorySchemaObjects) {
      if (!objects.any(
        (o) => normalizeSchema(o['sql'] as String) == normalizeSchema(sql),
      )) {
        throw const DatabaseFailure(DatabaseFailureCode.incompatible);
      }
    }
  }
  if (version >= 3) {
    for (final sql in accountSchemaObjects) {
      if (!objects.any(
        (o) => normalizeSchema(o['sql'] as String) == normalizeSchema(sql),
      )) {
        throw const DatabaseFailure(DatabaseFailureCode.incompatible);
      }
    }
    if (db.select(accountCoverageErrors).isNotEmpty) {
      throw const DatabaseFailure(DatabaseFailureCode.incompatible);
    }
  }
  if (version >= 4) {
    for (final sql in movementSchemaObjects) {
      if (!objects.any(
        (o) => normalizeSchema(o['sql'] as String) == normalizeSchema(sql),
      )) {
        throw const DatabaseFailure(DatabaseFailureCode.incompatible);
      }
    }
    if (db.select(movementIntegrityErrors).isNotEmpty) {
      throw const DatabaseFailure(DatabaseFailureCode.incompatible);
    }
  }
  if (version >= 5) {
    for (final sql
        in version >= 7
            ? budgetSchemaObjects.where(
                (s) => !s.contains('categories_budget_history'),
              )
            : budgetSchemaObjects) {
      if (!objects.any(
        (o) => normalizeSchema(o['sql'] as String) == normalizeSchema(sql),
      )) {
        throw const DatabaseFailure(DatabaseFailureCode.incompatible);
      }
    }
    if (db.select(budgetIntegrityErrors).isNotEmpty) {
      throw const DatabaseFailure(DatabaseFailureCode.incompatible);
    }
  }
  if (version >= 7) {
    for (final sql in categoryReorganizationObjects) {
      if (!objects.any(
        (o) => normalizeSchema(o['sql'] as String) == normalizeSchema(sql),
      )) {
        throw const DatabaseFailure(DatabaseFailureCode.incompatible);
      }
    }
  }
  if (version >= 6) {
    for (final sql in wealthSchemaObjects) {
      if (!objects.any(
        (o) => normalizeSchema(o['sql'] as String) == normalizeSchema(sql),
      )) {
        throw const DatabaseFailure(DatabaseFailureCode.incompatible);
      }
    }
    if (db.select(wealthIntegrityErrors).isNotEmpty) {
      throw const DatabaseFailure(DatabaseFailureCode.incompatible);
    }
  }
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
  db.createFunction(
    functionName: 'movement_search_key',
    argumentCount: const AllowedArgumentCount(1),
    deterministic: true,
    function: (arguments) => conceptSearchKey(arguments[0] as String),
  );
  db.createAggregateFunction(
    functionName: 'movement_subtotal',
    argumentCount: const AllowedArgumentCount(1),
    function: const MovementSubtotal(),
  );
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

const categoryIntegrityErrors = '''
WITH RECURSIVE tree(id,depth) AS (
 SELECT id,1 FROM categories WHERE parent_id IS NULL
 UNION ALL SELECT c.id,t.depth+1 FROM categories c JOIN tree t
 ON c.parent_id=t.id WHERE t.depth<3
) SELECT id FROM categories WHERE id NOT IN (SELECT id FROM tree)
''';

const categorySchemaObjects = <String>[
  '''CREATE TABLE "categories" ("id" TEXT NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length("replace"(id, '-', '')) = 32 AND "replace"(id, '-', '') NOT GLOB '*[^0-9a-f]*'), "parent_id" TEXT REFERENCES categories(id)ON UPDATE RESTRICT ON DELETE RESTRICT, "name" TEXT NOT NULL CHECK (length(trim(name)) > 0), "is_income" INTEGER CHECK (is_income IN (0, 1)), "archived" INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)), "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, CHECK((parent_id IS NULL AND is_income IS NOT NULL)OR(parent_id IS NOT NULL AND is_income IS NULL)));''',
  '''CREATE INDEX categories_parent ON categories (parent_id)''',
  '''CREATE TRIGGER categories_insert BEFORE INSERT ON categories BEGIN SELECT RAISE (ABORT, 'category_cycle') WHERE NEW.parent_id = NEW.id OR EXISTS (WITH RECURSIVE ancestors (id, parent_id) AS (SELECT id, parent_id FROM categories WHERE id = NEW.parent_id UNION SELECT c.id, c.parent_id FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id) SELECT 1 FROM ancestors WHERE id = NEW.id);SELECT RAISE (ABORT, 'category_depth') WHERE (WITH RECURSIVE ancestors (id, parent_id) AS (SELECT id, parent_id FROM categories WHERE id = NEW.parent_id UNION ALL SELECT c.id, c.parent_id FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id) SELECT count(*) FROM ancestors) + (WITH RECURSIVE descendants (id, depth) AS (SELECT NEW.id, 1 UNION ALL SELECT c.id, d.depth + 1 FROM categories AS c JOIN descendants AS d ON c.parent_id = d.id) SELECT max(depth) FROM descendants) > 3;END''',
  '''CREATE TRIGGER categories_update BEFORE UPDATE OF parent_id ON categories BEGIN SELECT RAISE (ABORT, 'category_cycle') WHERE NEW.parent_id = NEW.id OR EXISTS (WITH RECURSIVE ancestors (id, parent_id) AS (SELECT id, parent_id FROM categories WHERE id = NEW.parent_id UNION SELECT c.id, c.parent_id FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id) SELECT 1 FROM ancestors WHERE id = NEW.id);SELECT RAISE (ABORT, 'category_depth') WHERE (WITH RECURSIVE ancestors (id, parent_id) AS (SELECT id, parent_id FROM categories WHERE id = NEW.parent_id UNION ALL SELECT c.id, c.parent_id FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id) SELECT count(*) FROM ancestors) + (WITH RECURSIVE descendants (id, depth) AS (SELECT NEW.id, 1 UNION ALL SELECT c.id, d.depth + 1 FROM categories AS c JOIN descendants AS d ON c.parent_id = d.id) SELECT max(depth) FROM descendants) > 3;END''',
];

const accountSchemaObjects = <String>[
  '''CREATE TABLE "accounts" ("id" TEXT NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length("replace"(id, '-', '')) = 32 AND "replace"(id, '-', '') NOT GLOB '*[^0-9a-f]*'), "name" TEXT NOT NULL CHECK (length(trim(name)) > 0), "kind" TEXT NOT NULL CHECK (kind IN ('account', 'portfolio', 'debt')), "active_from" TEXT NOT NULL CHECK (active_from GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-01' AND substr(active_from, 1, 4) BETWEEN '0001' AND '9999' AND substr(active_from, 6, 2) BETWEEN '01' AND '12'), "active_through" TEXT CHECK (active_through IS NULL OR(active_through GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-01' AND substr(active_through, 1, 4) BETWEEN '0001' AND '9999' AND substr(active_through, 6, 2) BETWEEN '01' AND '12')), "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, CHECK(active_through IS NULL OR active_through >= active_from));''',
  '''CREATE TABLE "account_liquidity_periods" ("id" TEXT NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length("replace"(id, '-', '')) = 32 AND "replace"(id, '-', '') NOT GLOB '*[^0-9a-f]*'), "account_id" TEXT NOT NULL REFERENCES accounts(id)ON UPDATE RESTRICT ON DELETE RESTRICT, "from_month" TEXT NOT NULL CHECK (from_month GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-01' AND substr(from_month, 1, 4) BETWEEN '0001' AND '9999' AND substr(from_month, 6, 2) BETWEEN '01' AND '12'), "until_month" TEXT CHECK (until_month IS NULL OR(until_month GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-01' AND substr(until_month, 1, 4) BETWEEN '0001' AND '9999' AND substr(until_month, 6, 2) BETWEEN '01' AND '12')), "liquidity" TEXT NOT NULL CHECK (liquidity IN ('liquid', 'medium', 'illiquid')), "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, CHECK(until_month IS NULL OR until_month > from_month), UNIQUE(account_id, from_month));''',
  '''CREATE TRIGGER liquidity_insert BEFORE INSERT ON account_liquidity_periods BEGIN SELECT RAISE (ABORT, 'liquidity_bounds') WHERE NOT EXISTS (SELECT 1 FROM accounts AS a WHERE a.id = NEW.account_id AND a.kind <> 'debt' AND NEW.from_month >= a.active_from AND(a.active_through IS NULL OR(NEW.from_month <= a.active_through AND(a.active_through = '9999-12-01' OR(NEW.until_month IS NOT NULL AND NEW.until_month <= date(a.active_through, '+1 month'))))));SELECT RAISE (ABORT, 'liquidity_overlap') WHERE EXISTS (SELECT 1 FROM account_liquidity_periods AS p WHERE p.account_id = NEW.account_id AND(NEW.until_month IS NULL OR p.from_month < NEW.until_month)AND(p.until_month IS NULL OR NEW.from_month < p.until_month));END''',
  '''CREATE TRIGGER liquidity_update BEFORE UPDATE ON account_liquidity_periods BEGIN SELECT RAISE (ABORT, 'liquidity_bounds') WHERE NOT EXISTS (SELECT 1 FROM accounts AS a WHERE a.id = NEW.account_id AND a.kind <> 'debt' AND NEW.from_month >= a.active_from AND(a.active_through IS NULL OR(NEW.from_month <= a.active_through AND(a.active_through = '9999-12-01' OR(NEW.until_month IS NOT NULL AND NEW.until_month <= date(a.active_through, '+1 month'))))));SELECT RAISE (ABORT, 'liquidity_overlap') WHERE EXISTS (SELECT 1 FROM account_liquidity_periods AS p WHERE p.account_id = NEW.account_id AND p.id <> OLD.id AND(NEW.until_month IS NULL OR p.from_month < NEW.until_month)AND(p.until_month IS NULL OR NEW.from_month < p.until_month));END''',
  '''CREATE TRIGGER account_kind_immutable BEFORE UPDATE OF kind ON accounts WHEN NEW.kind <> OLD.kind BEGIN SELECT RAISE (ABORT, 'account_kind_immutable');END''',
  '''CREATE TRIGGER account_period_bounds BEFORE UPDATE OF active_from, active_through ON accounts BEGIN SELECT RAISE (ABORT, 'liquidity_bounds') WHERE EXISTS (SELECT 1 FROM account_liquidity_periods AS p WHERE p.account_id = NEW.id AND(p.from_month < NEW.active_from OR(NEW.active_through IS NOT NULL AND(p.from_month > NEW.active_through OR(NEW.active_through <> '9999-12-01' AND(p.until_month IS NULL OR p.until_month > date(NEW.active_through, '+1 month')))))));END''',
];
const accountCoverageErrors = '''
SELECT a.id FROM accounts a WHERE
(a.kind='debt' AND EXISTS(SELECT 1 FROM account_liquidity_periods p WHERE p.account_id=a.id)) OR
(a.kind<>'debt' AND (
 NOT EXISTS(SELECT 1 FROM account_liquidity_periods p WHERE p.account_id=a.id AND p.from_month=a.active_from) OR
 EXISTS(SELECT 1 FROM account_liquidity_periods p WHERE p.account_id=a.id AND (
 p.from_month<a.active_from OR
 (p.until_month IS NOT NULL AND NOT EXISTS(SELECT 1 FROM account_liquidity_periods n WHERE n.account_id=a.id AND n.from_month=p.until_month) AND
 (a.active_through IS NULL OR a.active_through='9999-12-01' OR p.until_month<>date(a.active_through,'+1 month'))) OR
 (p.until_month IS NULL AND a.active_through IS NOT NULL AND a.active_through<>'9999-12-01') OR
 (a.active_through IS NOT NULL AND p.from_month>a.active_through) OR
 EXISTS(SELECT 1 FROM account_liquidity_periods n WHERE n.account_id=a.id AND n.id<>p.id AND
 (p.until_month IS NULL OR n.from_month<p.until_month) AND (n.until_month IS NULL OR p.from_month<n.until_month))
 )) OR NOT EXISTS(SELECT 1 FROM account_liquidity_periods p WHERE p.account_id=a.id AND
 ((a.active_through IS NULL OR a.active_through='9999-12-01') AND p.until_month IS NULL OR p.until_month=date(a.active_through,'+1 month')))
))
''';

const movementSchemaObjects = <String>[
  '''CREATE TABLE "import_batches" ("id" TEXT NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length("replace"(id, '-', '')) = 32 AND "replace"(id, '-', '') NOT GLOB '*[^0-9a-f]*'), "content_sha256" TEXT NOT NULL UNIQUE CHECK (length(content_sha256) = 64 AND content_sha256 NOT GLOB '*[^0-9a-f]*'), "source_kind" TEXT NOT NULL CHECK (source_kind IN ('historical_csv', 'bank_xls')), "original_name" TEXT NOT NULL CHECK (length(trim(original_name)) > 0), "contract_version" TEXT NOT NULL CHECK (length(trim(contract_version)) > 0), "imported_at" TEXT NOT NULL, "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);''',
  '''CREATE TABLE "import_rows" ("id" TEXT NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length("replace"(id, '-', '')) = 32 AND "replace"(id, '-', '') NOT GLOB '*[^0-9a-f]*'), "batch_id" TEXT NOT NULL REFERENCES import_batches(id)ON UPDATE RESTRICT ON DELETE RESTRICT, "source_ordinal" INTEGER NOT NULL CHECK (typeof(source_ordinal) = 'integer' AND source_ordinal >= 2), "record_kind" TEXT NOT NULL CHECK (record_kind IN ('movement', 'budget')), "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, UNIQUE(batch_id, source_ordinal));''',
  '''CREATE TABLE "movements" ("id" TEXT NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length("replace"(id, '-', '')) = 32 AND "replace"(id, '-', '') NOT GLOB '*[^0-9a-f]*'), "account_id" TEXT NOT NULL REFERENCES accounts(id)ON UPDATE RESTRICT ON DELETE RESTRICT, "value_date" TEXT NOT NULL CHECK (value_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND substr(value_date, 1, 4) BETWEEN '0001' AND '9999' AND date(value_date, '+0 days') IS NOT NULL AND date(value_date, '+0 days') = value_date), "concept" TEXT NOT NULL CHECK (length(trim(concept)) > 0), "amount_cents" INTEGER NOT NULL CHECK (typeof(amount_cents) = 'integer' AND amount_cents <> 0), "category_id" TEXT REFERENCES categories(id)ON UPDATE RESTRICT ON DELETE RESTRICT, "discretion" TEXT, "import_row_id" TEXT UNIQUE REFERENCES import_rows(id)ON UPDATE RESTRICT ON DELETE RESTRICT, "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);''',
  '''CREATE INDEX movements_date ON movements (value_date, id)''',
  '''CREATE INDEX movements_account_date ON movements (account_id, value_date, id)''',
  '''CREATE INDEX movements_category_date ON movements (category_id, value_date, id)''',
  '''CREATE TRIGGER movements_insert BEFORE INSERT ON movements BEGIN SELECT RAISE (ABORT, 'movement_account') WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE id = NEW.account_id AND kind = 'account' AND substr(NEW.value_date, 1, 7) || '-01' >= active_from AND(active_through IS NULL OR substr(NEW.value_date, 1, 7) || '-01' <= active_through));SELECT RAISE (ABORT, 'movement_origin') WHERE NEW.import_row_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM import_rows WHERE id = NEW.import_row_id AND record_kind = 'movement');END''',
  '''CREATE TRIGGER movements_update BEFORE UPDATE ON movements BEGIN SELECT RAISE (ABORT, 'movement_account') WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE id = NEW.account_id AND kind = 'account' AND substr(NEW.value_date, 1, 7) || '-01' >= active_from AND(active_through IS NULL OR substr(NEW.value_date, 1, 7) || '-01' <= active_through));SELECT RAISE (ABORT, 'movement_origin_immutable') WHERE NEW.import_row_id IS NOT OLD.import_row_id;END''',
  '''CREATE TRIGGER import_rows_immutable BEFORE UPDATE ON import_rows BEGIN SELECT RAISE (ABORT, 'import_origin_immutable');END''',
  '''CREATE TRIGGER import_rows_keep BEFORE DELETE ON import_rows BEGIN SELECT RAISE (ABORT, 'import_origin_keep');END''',
  '''CREATE TRIGGER import_batches_immutable BEFORE UPDATE ON import_batches BEGIN SELECT RAISE (ABORT, 'import_origin_immutable');END''',
  '''CREATE TRIGGER import_batches_keep BEFORE DELETE ON import_batches BEGIN SELECT RAISE (ABORT, 'import_origin_keep');END''',
  '''CREATE TRIGGER accounts_movement_bounds BEFORE UPDATE OF active_from, active_through ON accounts BEGIN SELECT RAISE (ABORT, 'movement_bounds') WHERE EXISTS (SELECT 1 FROM movements WHERE account_id = NEW.id AND(substr(value_date, 1, 7) || '-01' < NEW.active_from OR(NEW.active_through IS NOT NULL AND substr(value_date, 1, 7) || '-01' > NEW.active_through)));END''',
];

const movementIntegrityErrors = '''
SELECT m.id FROM movements m JOIN accounts a ON a.id=m.account_id
LEFT JOIN import_rows r ON r.id=m.import_row_id
WHERE a.kind<>'account' OR substr(m.value_date,1,7)||'-01'<a.active_from
OR (a.active_through IS NOT NULL AND substr(m.value_date,1,7)||'-01'>a.active_through)
OR (m.import_row_id IS NOT NULL AND (r.id IS NULL OR r.record_kind<>'movement'))
''';

const budgetSchemaObjects = <String>[
  '''CREATE TABLE "budgets" ("id" TEXT NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length("replace"(id, '-', '')) = 32 AND "replace"(id, '-', '') NOT GLOB '*[^0-9a-f]*'), "month" TEXT NOT NULL CHECK (month GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-01' AND substr(month, 1, 4) BETWEEN '0001' AND '9999' AND substr(month, 6, 2) BETWEEN '01' AND '12'), "category_id" TEXT NOT NULL REFERENCES categories(id)ON UPDATE RESTRICT ON DELETE RESTRICT, "amount_cents" INTEGER NOT NULL CHECK (typeof(amount_cents) = 'integer'), "concept" TEXT CHECK (concept IS NULL OR length(trim(concept)) > 0), "discretion" TEXT, "import_row_id" TEXT UNIQUE REFERENCES import_rows(id)ON UPDATE RESTRICT ON DELETE RESTRICT, "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, UNIQUE(month, category_id));''',
  '''CREATE INDEX budgets_category_month ON budgets (category_id, month)''',
  '''CREATE TRIGGER budgets_insert BEFORE INSERT ON budgets BEGIN SELECT RAISE (ABORT, 'budget_overlap') WHERE EXISTS (WITH RECURSIVE ancestors (id, parent_id) AS (SELECT id, parent_id FROM categories WHERE id = NEW.category_id UNION ALL SELECT c.id, c.parent_id FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id), descendants (id) AS (SELECT NEW.category_id UNION ALL SELECT c.id FROM categories AS c JOIN descendants AS d ON c.parent_id = d.id) SELECT 1 FROM budgets AS b WHERE b.month = NEW.month AND b.id <> NEW.id AND(b.category_id IN (SELECT id FROM ancestors) OR b.category_id IN (SELECT id FROM descendants)));SELECT RAISE (ABORT, 'budget_origin') WHERE NEW.import_row_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM import_rows WHERE id = NEW.import_row_id AND record_kind = 'budget');END''',
  '''CREATE TRIGGER budgets_update BEFORE UPDATE ON budgets BEGIN SELECT RAISE (ABORT, 'budget_overlap') WHERE EXISTS (WITH RECURSIVE ancestors (id, parent_id) AS (SELECT id, parent_id FROM categories WHERE id = NEW.category_id UNION ALL SELECT c.id, c.parent_id FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id), descendants (id) AS (SELECT NEW.category_id UNION ALL SELECT c.id FROM categories AS c JOIN descendants AS d ON c.parent_id = d.id) SELECT 1 FROM budgets AS b WHERE b.month = NEW.month AND b.id <> NEW.id AND(b.category_id IN (SELECT id FROM ancestors) OR b.category_id IN (SELECT id FROM descendants)));SELECT RAISE (ABORT, 'budget_origin_immutable') WHERE NEW.import_row_id IS NOT OLD.import_row_id;END''',
  '''CREATE TRIGGER categories_budget_history BEFORE UPDATE OF parent_id, is_income ON categories WHEN NEW.parent_id IS NOT OLD.parent_id OR NEW.is_income IS NOT OLD.is_income BEGIN SELECT RAISE (ABORT, 'budget_category_history') WHERE EXISTS (WITH RECURSIVE branch (id) AS (SELECT OLD.id UNION ALL SELECT c.id FROM categories AS c JOIN branch AS b ON c.parent_id = b.id) SELECT 1 FROM budgets WHERE category_id IN (SELECT id FROM branch));END''',
];
const budgetIntegrityErrors = '''
WITH RECURSIVE ancestry(id,ancestor) AS (
 SELECT id,parent_id FROM categories WHERE parent_id IS NOT NULL
 UNION ALL SELECT a.id,c.parent_id FROM ancestry a JOIN categories c ON c.id=a.ancestor WHERE c.parent_id IS NOT NULL
) SELECT b.id FROM budgets b LEFT JOIN import_rows r ON r.id=b.import_row_id
WHERE (b.import_row_id IS NOT NULL AND (r.id IS NULL OR r.record_kind<>'budget'))
OR EXISTS(SELECT 1 FROM budgets p JOIN ancestry a ON a.id=b.category_id AND a.ancestor=p.category_id WHERE p.month=b.month)
''';

const wealthIntegrityErrors = '''
SELECT v.id FROM wealth_values v JOIN wealth_snapshots s ON s.id=v.snapshot_id
JOIN accounts a ON a.id=v.account_id WHERE s.month<a.active_from OR
(a.active_through IS NOT NULL AND s.month>a.active_through)
''';
const wealthSchemaObjects = <String>[
  '''CREATE TABLE "wealth_snapshots" ("id" TEXT NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length("replace"(id, '-', '')) = 32 AND "replace"(id, '-', '') NOT GLOB '*[^0-9a-f]*'), "month" TEXT NOT NULL UNIQUE CHECK (month GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-01' AND substr(month, 1, 4) BETWEEN '0001' AND '9999' AND substr(month, 6, 2) BETWEEN '01' AND '12'), "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);''',
  '''CREATE TABLE "wealth_values" ("id" TEXT NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length("replace"(id, '-', '')) = 32 AND "replace"(id, '-', '') NOT GLOB '*[^0-9a-f]*'), "snapshot_id" TEXT NOT NULL REFERENCES wealth_snapshots(id)ON UPDATE RESTRICT ON DELETE RESTRICT, "account_id" TEXT NOT NULL REFERENCES accounts(id)ON UPDATE RESTRICT ON DELETE RESTRICT, "amount_cents" INTEGER NOT NULL CHECK (typeof(amount_cents) = 'integer' AND amount_cents >= 0), "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, UNIQUE(snapshot_id, account_id));''',
  '''CREATE INDEX wealth_values_account_snapshot ON wealth_values (account_id, snapshot_id)''',
  '''CREATE TRIGGER wealth_values_insert BEFORE INSERT ON wealth_values BEGIN SELECT RAISE (ABORT, 'wealth_bounds') WHERE NOT EXISTS (SELECT 1 FROM accounts AS a JOIN wealth_snapshots AS s ON s.id = NEW.snapshot_id WHERE a.id = NEW.account_id AND a.active_from <= s.month AND(a.active_through IS NULL OR a.active_through >= s.month));END''',
  '''CREATE TRIGGER wealth_values_update BEFORE UPDATE ON wealth_values BEGIN SELECT RAISE (ABORT, 'wealth_bounds') WHERE NOT EXISTS (SELECT 1 FROM accounts AS a JOIN wealth_snapshots AS s ON s.id = NEW.snapshot_id WHERE a.id = NEW.account_id AND a.active_from <= s.month AND(a.active_through IS NULL OR a.active_through >= s.month));END''',
  '''CREATE TRIGGER wealth_month_immutable BEFORE UPDATE OF month ON wealth_snapshots WHEN NEW.month <> OLD.month AND EXISTS (SELECT 1 FROM wealth_values WHERE snapshot_id = OLD.id) BEGIN SELECT RAISE (ABORT, 'wealth_month_immutable');END''',
  '''CREATE TRIGGER accounts_wealth_bounds BEFORE UPDATE OF active_from, active_through ON accounts BEGIN SELECT RAISE (ABORT, 'wealth_bounds') WHERE EXISTS (SELECT 1 FROM wealth_values AS v JOIN wealth_snapshots AS s ON s.id = v.snapshot_id WHERE v.account_id = NEW.id AND(s.month < NEW.active_from OR(NEW.active_through IS NOT NULL AND s.month > NEW.active_through)));END''',
];

// Objetos nuevos de v7; las definiciones v1-v6 permanecen publicadas.
const categoryReorganizationObjects = <String>[
  '''CREATE TRIGGER categories_root_history BEFORE UPDATE OF is_income ON categories WHEN OLD.parent_id IS NULL AND NEW.parent_id IS NULL AND NEW.is_income IS NOT OLD.is_income BEGIN SELECT RAISE (ABORT, 'category_root_history') WHERE EXISTS (WITH RECURSIVE branch (id) AS (SELECT OLD.id UNION SELECT c.id FROM categories AS c JOIN branch AS b ON c.parent_id = b.id) SELECT 1 FROM budgets WHERE category_id IN (SELECT id FROM branch) UNION ALL SELECT 1 FROM movements WHERE category_id IN (SELECT id FROM branch));END''',
  '''CREATE TRIGGER categories_promotion BEFORE UPDATE OF parent_id, is_income ON categories WHEN OLD.parent_id IS NOT NULL AND NEW.parent_id IS NULL BEGIN SELECT RAISE (ABORT, 'category_promotion_type') WHERE NEW.is_income IS NOT (WITH RECURSIVE ancestors (id, parent_id, is_income) AS (SELECT id, parent_id, is_income FROM categories WHERE id = OLD.parent_id UNION SELECT c.id, c.parent_id, c.is_income FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id) SELECT is_income FROM ancestors WHERE parent_id IS NULL);END''',
  '''CREATE TRIGGER categories_destination_insert BEFORE INSERT ON categories WHEN NEW.parent_id IS NOT NULL BEGIN SELECT RAISE (ABORT, 'category_destination') WHERE NOT EXISTS (SELECT 1 FROM categories WHERE id = NEW.parent_id AND archived = 0);END''',
  '''CREATE TRIGGER categories_destination_update BEFORE UPDATE OF parent_id ON categories WHEN NEW.parent_id IS NOT NULL AND NEW.parent_id IS NOT OLD.parent_id BEGIN SELECT RAISE (ABORT, 'category_destination') WHERE NOT EXISTS (SELECT 1 FROM categories WHERE id = NEW.parent_id AND archived = 0);END''',
  '''CREATE TRIGGER categories_budget_overlap AFTER UPDATE OF parent_id ON categories WHEN NEW.parent_id IS NOT OLD.parent_id BEGIN SELECT RAISE (ABORT, 'category_budget_overlap') WHERE EXISTS (WITH RECURSIVE ancestry (id, ancestor) AS (SELECT id, parent_id FROM categories WHERE parent_id IS NOT NULL UNION SELECT a.id, c.parent_id FROM ancestry AS a JOIN categories AS c ON c.id = a.ancestor WHERE c.parent_id IS NOT NULL) SELECT 1 FROM budgets AS b JOIN ancestry AS a ON a.id = b.category_id JOIN budgets AS p ON p.category_id = a.ancestor AND p.month = b.month);END''',
];
