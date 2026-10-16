// Comprobador de referencias de MA-TSK-219. No es un exportador de la app.
// Node 22.20+; solo módulos estándar, SQLite real y datos sintéticos.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, mkdtempSync, unlinkSync, rmdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';

const base = dirname(fileURLToPath(import.meta.url));
const repo = resolve(base, '../..');
const read = p => readFileSync(join(base, p));
const json = p => JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(read(p)));
const dictionary = json('diccionario-v1.json');
const schema = json('manifest-v1.schema.json');
const source = json('ejemplos/origen-sintetico.json');
const manifest = json('ejemplos/datos/manifest.json');
const max = 9223372036854775807n;
const min = -9223372036854775808n;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const canonicalCounter = (v, positive = false) => {
  assert.equal(typeof v, 'string');
  assert.match(v, /^(0|[1-9][0-9]*)$/);
  assert.ok(BigInt(v) <= max && BigInt(v) >= (positive ? 1n : 0n));
};

// Evalúa únicamente los keywords usados en el esquema adjunto; falla si se
// añade uno sin soporte. No sustituye un validador general JSON Schema.
const annotations = new Set(['$schema', 'title', 'description']);
function matches(s, value) {
  for (const [key, rule] of Object.entries(s)) {
    if (annotations.has(key)) continue;
    switch (key) {
      case 'type': {
        const type = value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value;
        if (rule === 'integer' ? !Number.isInteger(value) : type !== rule) return false;
        break;
      }
      case 'const': if (value !== rule) return false; break;
      case 'enum': if (!rule.includes(value)) return false; break;
      case 'pattern': if (typeof value === 'string' && !new RegExp(rule).test(value)) return false; break;
      case 'minimum': if (typeof value === 'number' && value < rule) return false; break;
      case 'required': if (value && typeof value === 'object' && !rule.every(k => Object.hasOwn(value, k))) return false; break;
      case 'additionalProperties':
        if (!rule && value && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).some(k => !Object.hasOwn(s.properties, k))) return false;
        break;
      case 'properties':
        if (value && typeof value === 'object' && Object.entries(rule).some(([k, child]) => Object.hasOwn(value, k) && !matches(child, value[k]))) return false;
        break;
      case 'items': if (Array.isArray(value) && value.some(v => !matches(rule, v))) return false; break;
      case 'minItems': if (Array.isArray(value) && value.length < rule) return false; break;
      case 'maxItems': if (Array.isArray(value) && value.length > rule) return false; break;
      case 'uniqueItems': if (Array.isArray(value) && rule && new Set(value.map(v => JSON.stringify(v))).size !== value.length) return false; break;
      case 'anyOf': if (!rule.some(child => matches(child, value))) return false; break;
      case 'oneOf': if (rule.filter(child => matches(child, value)).length !== 1) return false; break;
      default: throw new Error(`Keyword sin comprobar: ${key}`);
    }
  }
  return true;
}

// Lector de este dialecto: conserva comillas para distinguir NULL de "".
function parseCsv(bytes) {
  const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  assert.notEqual(bytes.subarray(0, 3).toString('hex'), 'efbbbf');
  const end = text.indexOf('\r\n');
  assert.ok(end > 0);
  const header = text.slice(0, end).split(';');
  assert.ok(header.every(c => /^[a-z_]+$/.test(c)));
  let at = end + 2;
  const rows = [];
  while (at < text.length) {
    const fields = [];
    while (true) {
      let value = null;
      if (text[at] === '"') {
        at++;
        value = '';
        let closed = false;
        while (at < text.length) {
          if (text[at] !== '"') { value += text[at++]; continue; }
          at++;
          if (text[at] === '"') { value += '"'; at++; } else { closed = true; break; }
        }
        assert.ok(closed, 'Comillas sin cerrar');
      }
      fields.push(value);
      if (text[at] === ';') { at++; continue; }
      assert.equal(text.slice(at, at + 2), '\r\n', 'Terminación o campo sin comillas inválido');
      at += 2;
      break;
    }
    assert.equal(fields.length, header.length);
    rows.push(Object.fromEntries(header.map((h, i) => [h, fields[i]])));
  }
  return { header, rows };
}

function cents(value) {
  assert.match(value, /^-?(0|[1-9][0-9]*)\.[0-9]{2}$/);
  assert.notEqual(value, '-0.00');
  const n = BigInt(value.replace('.', ''));
  assert.ok(n >= min && n <= max);
  return n;
}
assert.equal(cents('-92233720368547758.08'), min);
assert.equal(cents('92233720368547758.07'), max);
for (const v of ['-0.00', '1e2', '1,00', '+1.00', '01.00', '92233720368547758.08']) assert.throws(() => cents(v));
for (const v of [9007199254740993, '-1', '01', '9223372036854775808']) assert.throws(() => canonicalCounter(v));
canonicalCounter('9007199254740993');
canonicalCounter(String(max));
assert.throws(() => parseCsv(Buffer.from('a\r\n"sin cerrar')));
assert.throws(() => parseCsv(Buffer.from('a\r\n=1\r\n')));
assert.throws(() => parseCsv(Buffer.from([0x61, 13, 10, 0xff])));
assert.deepEqual(parseCsv(Buffer.from('a;b\r\n;""\r\n')).rows, [{ a: null, b: '' }]);

function validateManifest(m) {
  assert.ok(matches(schema, m), 'Esquema de manifiesto');
  canonicalCounter(m.revision);
  assert.equal(new Date(m.createdAtUtc).toISOString(), m.createdAtUtc);
  const names = m.files.map(f => f.path);
  assert.deepEqual(names, [...names].sort());
  assert.equal(new Set(names.map(n => n.toLowerCase())).size, names.length);
  const data = m.kind === 'autofinance.dataExport';
  assert.deepEqual(names, (data ? [...dictionary.files.map(f => f.path), 'diccionario.json', 'LEEME.md'] : ['autofinance.sqlite', 'LEEME.md']).sort());
  for (const f of m.files) {
    canonicalCounter(f.sizeBytes, true);
    const csv = f.path.endsWith('.csv');
    assert.equal(f.mediaType, csv ? 'text/csv' : f.path.endsWith('.sqlite') ? 'application/vnd.sqlite3' : f.path.endsWith('.json') ? 'application/json' : 'text/markdown');
    if (csv) canonicalCounter(f.rowCount); else assert.equal(f.rowCount, null);
  }
  if (data && m.filter.mode === 'months') {
    assert.ok(m.filter.fromMonth <= m.filter.throughMonth);
  }
  const tables = m.databaseTables.map(t => t.name);
  assert.deepEqual(tables, [...new Set(tables)].sort());
  for (const t of m.databaseTables) canonicalCounter(t.rowCount);
}
validateManifest(manifest);
const allHistory = structuredClone(manifest);
allHistory.filter = { mode: 'all', fromMonth: null, throughMonth: null };
validateManifest(allHistory);
for (const mutate of [
  m => { m.kind = 'autofinance.localBackup'; },
  m => { m.formatVersion = 2; },
  m => { m.revision = 9007199254740992; },
  m => { m.revision = '9223372036854775808'; },
  m => { m.creationOrder = '1'; },
  m => { m.filter.fromMonth = '2026-04-01'; },
  m => { m.filter.fromMonth = '2026-00-01'; },
  m => { m.files[0].path = '../autofinance.sqlite'; },
  m => { m.files[0].sizeBytes = '0'; },
  m => { m.files[0] = { ...m.files[1] }; },
]) {
  const copy = structuredClone(manifest); mutate(copy);
  assert.throws(() => validateManifest(copy));
}

const formatSource = readFileSync(join(repo, 'lib/core/persistence/local_database_format.dart'), 'utf8');
const currentVersion = Number(/localSchemaVersion = (\d+)/.exec(formatSource)[1]);
const applicationId = Number(/localApplicationId = (0x[0-9a-f]+)/.exec(formatSource)[1]);
assert.equal(source.schemaVersion, currentVersion, 'Revisar contrato al evolucionar el esquema');
assert.equal(manifest.schemaVersion, currentVersion);
assert.equal(manifest.applicationId, applicationId);
assert.deepEqual(json('ejemplos/datos/diccionario.json'), dictionary);
assert.deepEqual(read('ejemplos/datos/diccionario.json'), read('diccionario-v1.json'));
const temp = mkdtempSync(join(tmpdir(), 'autofinance-contract-219-'));
const dbPath = join(temp, 'autofinance.sqlite');
let db = new DatabaseSync(dbPath);
try {
  const sql = readFileSync(join(repo, 'lib/app/data/sqlite/schema.drift'), 'utf8');
  // Drift ordena las declaraciones. SQLite estándar necesita las tablas antes
  // de los triggers que las nombran como destino.
  const statements = sql.match(/CREATE TABLE[\s\S]*?;|CREATE INDEX[\s\S]*?;|CREATE TRIGGER[\s\S]*?END;/g);
  assert.equal(statements.length, (sql.match(/CREATE (TABLE|INDEX|TRIGGER) /g) ?? []).length);
  for (const statement of statements.filter(s => s.startsWith('CREATE TABLE'))) db.exec(statement);
  for (const statement of statements.filter(s => !s.startsWith('CREATE TABLE'))) db.exec(statement);
  db.exec(`PRAGMA application_id=${applicationId}; PRAGMA user_version=${currentVersion}; PRAGMA foreign_keys=ON`);
  // Orden explícito para satisfacer FK y triggers del esquema real.
  const order = ['database_state', 'accounts', 'categories', 'account_liquidity_periods', 'import_batches', 'import_rows', 'movements', 'budgets', 'wealth_snapshots', 'wealth_values', 'import_batch_metadata', 'import_row_originals'];
  for (const name of order) {
    const integerColumns = new Set(db.prepare(`PRAGMA table_info(${name})`).all().filter(c => c.type === 'INTEGER').map(c => c.name));
    for (const row of source.tables[name]) {
      const columns = Object.keys(row);
      db.prepare(`INSERT INTO ${name} (${columns.join(',')}) VALUES (${columns.map(() => '?').join(',')})`).run(...columns.map(k => row[k] !== null && integerColumns.has(k) ? BigInt(row[k]) : row[k]));
    }
  }
  db.close();
  // Apertura independiente solo lectura: sin Drift, Autofinance o funciones UDF.
  db = new DatabaseSync(dbPath, { readOnly: true });
  const query = (sql, ...args) => { const q = db.prepare(sql); q.setReadBigInts(true); return q.all(...args); };
  assert.deepEqual(query('PRAGMA integrity_check').map(r => r.integrity_check), ['ok']);
  assert.equal(query('PRAGMA foreign_key_check').length, 0);
  assert.equal(query('PRAGMA user_version')[0].user_version, BigInt(currentVersion));
  assert.equal(query('PRAGMA application_id')[0].application_id, BigInt(applicationId));
  const state = query('SELECT dataset_id,revision FROM database_state')[0];
  assert.equal(state.dataset_id, manifest.datasetId);
  assert.equal(String(state.revision), manifest.revision);
  const dataRows = new Map();
  for (const f of dictionary.files) {
    const { header, rows } = parseCsv(read('ejemplos/datos/' + f.path));
    dataRows.set(f.path, rows);
    assert.deepEqual(header, f.columns.map(c => c.name));
    assert.equal(new Set(header).size, header.length);
    const columns = new Set(query(`PRAGMA table_info(${f.sourceTable})`).map(c => c.name));
    for (const c of f.columns) {
      assert.ok(Object.hasOwn(dictionary.types, c.type));
      if (c.source !== 'derived' && !c.source.includes('.')) assert.ok(columns.has(c.source), `${f.sourceTable}.${c.source}`);
    }
    const conditions = f.sourceTable === 'movements' ? "WHERE substr(value_date,1,7) BETWEEN '2026-01' AND '2026-03'" : ['budgets', 'wealth_snapshots'].includes(f.sourceTable) ? "WHERE month BETWEEN '2026-01-01' AND '2026-03-01'" : f.sourceTable === 'wealth_values' ? "WHERE snapshot_id IN (SELECT id FROM wealth_snapshots WHERE month BETWEEN '2026-01-01' AND '2026-03-01')" : '';
    const expected = query(`SELECT * FROM ${f.sourceTable} ${conditions}`);
    assert.equal(rows.length, expected.length, f.path);
    const sorted = [...rows].sort((a, b) => { for (const k of f.orderBy) { if (a[k] < b[k]) return -1; if (a[k] > b[k]) return 1; } return 0; });
    assert.deepEqual(rows, sorted, `Orden ${f.path}`);
    assert.equal(new Set(rows.map(r => r.id)).size, rows.length);
    for (const row of rows) {
      const original = expected.find(r => r.id === row.id);
      assert.ok(original, row.id);
      for (const c of f.columns) {
        const v = row[c.name];
        if (!c.nullable) assert.notEqual(v, null, c.name);
        if (v === null) continue;
        if (c.type.startsWith('eur')) { const n = cents(v); if (c.type === 'eurNonNegative') assert.ok(n >= 0n); }
        if (c.type === 'counter') { canonicalCounter(v); if (c.name === 'ordinal_origen') assert.ok(BigInt(v) >= 2n); }
        if (Array.isArray(dictionary.types[c.type])) assert.ok(dictionary.types[c.type].includes(v));
        if (c.type === 'uuid') assert.match(v, /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/);
        if (c.type === 'boolean') assert.match(v, /^[01]$/);
        if (c.type === 'depth') assert.match(v, /^[123]$/);
        if (c.type === 'utc') assert.equal(new Date(v).toISOString(), v);
        if (c.type === 'date' || c.type === 'month') { assert.equal(new Date(v).toISOString().slice(0, 10), v); if (c.type === 'month') assert.ok(v.endsWith('-01')); }
      }
      // Comparación contra SQLite, incluida diferencia NULL / cadena vacía.
      for (const c of f.columns.filter(c => c.source !== 'derived')) {
        let value;
        if (c.source.includes('.')) {
          const origin = query('SELECT r.batch_id,r.source_ordinal,b.source_kind FROM import_rows r JOIN import_batches b ON b.id=r.batch_id WHERE r.id=?', original.import_row_id)[0];
          value = origin?.[c.source.split('.')[1]] ?? null;
        } else value = original[c.source];
        assert.equal(c.type.startsWith('eur') ? cents(row[c.name]) : row[c.name], value === null ? null : typeof value === 'bigint' && !c.type.startsWith('eur') ? String(value) : value, `${f.path}.${c.name}`);
      }
      if (f.sourceTable === 'movements') assert.equal(row.clasificacion, original.category_id === null ? 'sin_categoria' : 'categorizado');
      if (f.sourceTable === 'categories') {
        const chain = query('WITH RECURSIVE a AS (SELECT *,1 n FROM categories WHERE id=? UNION ALL SELECT c.*,a.n+1 FROM categories c JOIN a ON c.id=a.parent_id) SELECT * FROM a ORDER BY n DESC', row.id);
        assert.deepEqual(JSON.parse(row.ruta_ids), chain.map(c => c.id));
        assert.deepEqual(JSON.parse(row.ruta_nombres), chain.map(c => c.name));
        assert.equal(row.raiz_id, chain[0].id);
        assert.equal(row.ingreso_efectivo, String(chain[0].is_income));
        assert.equal(row.nivel, String(chain.length));
      }
      if (f.sourceTable === 'wealth_snapshots') {
        const [stats] = query('SELECT (SELECT count(*) FROM accounts WHERE active_from<=? AND (active_through IS NULL OR active_through>=?)) expected,(SELECT count(*) FROM wealth_values WHERE snapshot_id=?) valued', original.month, original.month, original.id);
        assert.equal(row.cuentas_esperadas, String(stats.expected));
        assert.equal(row.valores_registrados, String(stats.valued));
        assert.equal(row.cuentas_pendientes, String(stats.expected - stats.valued));
        assert.equal(row.estado, stats.valued === 0n ? 'absent' : stats.expected > stats.valued ? 'incomplete' : 'complete');
      }
    }
  }
  for (const f of manifest.files) {
    const bytes = read('ejemplos/datos/' + f.path);
    assert.equal(String(bytes.length), f.sizeBytes);
    assert.equal(hash(bytes), f.sha256);
    if (f.path.endsWith('.csv')) assert.equal(String(dataRows.get(f.path).length), f.rowCount);
    const corrupted = Buffer.from(bytes); corrupted[0] ^= 1;
    assert.notEqual(hash(corrupted), f.sha256);
  }
  assert.deepEqual(dataRows.get('fotos.csv').map(r => r.estado), ['complete', 'absent', 'incomplete']);
  assert.ok(!dataRows.get('fotos.csv').some(r => r.mes === '2026-04-01'));
  assert.equal(dataRows.get('presupuestos.csv')[0].importe_eur, '0.00');
  assert.equal(dataRows.get('valores_fotos.csv')[0].importe_eur, '0.00');
  assert.equal(dataRows.get('presupuestos.csv')[1].importe_eur, '-600.00');
  assert.equal(dataRows.get('presupuestos.csv')[1].ordinal_origen, '7');
  assert.equal(dataRows.get('movimientos.csv')[0].importe_eur, '-92233720368547758.08');
  assert.equal(dataRows.get('movimientos.csv')[2].ordinal_origen, '9007199254740993');
  assert.equal(dataRows.get('movimientos.csv')[1].discrecionalidad, '');
  assert.equal(dataRows.get('movimientos.csv')[2].discrecionalidad, null);
  // Todo histórico, rango vacío, un único mes y límite superior del calendario.
  assert.equal(query('SELECT * FROM movements').length, 5);
  assert.equal(query("SELECT * FROM movements WHERE substr(value_date,1,7) BETWEEN '2026-01' AND '2026-01'").length, 2);
  assert.equal(query("SELECT * FROM movements WHERE substr(value_date,1,7) BETWEEN '9999-12' AND '9999-12'").length, 0);
  assert.equal(parseCsv(Buffer.from('id\r\n')).rows.length, 0);
  assert.equal(dataRows.get('cuentas.csv').length, 4); // Incluye baja anterior.
  assert.equal(dataRows.get('categorias.csv').length, 5); // Ancestros y archivado.
  assert.equal(dataRows.get('liquidez_cuentas.csv')[0].desde_mes, '2025-01-01');
  // Ejemplo completo de metadatos portables derivado de la SQLite sintética.
  const portable = { ...manifest, kind: 'autofinance.portableBackup', filter: null, dictionary: null, files: [manifest.files.find(f => f.path === 'LEEME.md'), { path: 'autofinance.sqlite', mediaType: 'application/vnd.sqlite3', rowCount: null, sizeBytes: String(readFileSync(dbPath).length), sha256: hash(readFileSync(dbPath)) }], databaseTables: query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT GLOB 'sqlite_*' ORDER BY name").map(t => ({ name: t.name, rowCount: String(query(`SELECT count(*) n FROM ${t.name}`)[0].n) })) };
  validateManifest(portable);
  assert.equal(portable.databaseTables.length, order.length);
  assert.equal(portable.databaseTables.find(t => t.name === 'import_row_originals').rowCount, '1');
  assert.equal(portable.databaseTables.find(t => t.name === 'movements').rowCount, '5'); // Sin rango CSV.
  const invalidPortable = structuredClone(portable); invalidPortable.filter = manifest.filter;
  assert.throws(() => validateManifest(invalidPortable));
  console.log(`OK MA-TSK-219: 7 CSV, ${manifest.files.length} archivos con hash, ${order.length} tablas SQLite; filtros, contexto, ausencia, texto e int64 exactos. Sin UI/exportador de producto.`);
} finally {
  db.close();
  // Solo el archivo sintético y el directorio temporal exclusivo creados arriba.
  unlinkSync(dbPath);
  rmdirSync(temp);
}
