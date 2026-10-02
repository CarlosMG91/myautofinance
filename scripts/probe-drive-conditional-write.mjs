// Ensayo opt-in: nunca recibe el ID de una copia existente ni modifica la app.
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const fields = 'id,version,modifiedTime,headRevisionId,md5Checksum';
const root = 'https://www.googleapis.com';
const md5 = bytes => createHash('md5').update(bytes).digest('hex');

export function sqlitePayload(writer) {
  const dir = mkdtempSync(join(tmpdir(), 'autofinance-probe-'));
  try {
    const path = join(dir, 'probe.sqlite');
    const db = new DatabaseSync(path);
    try {
      db.exec('CREATE TABLE synthetic_probe(writer TEXT NOT NULL)');
      db.prepare('INSERT INTO synthetic_probe VALUES (?)').run(writer);
      if (db.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok') {
        throw new Error('invalid_fixture');
      }
    } finally { db.close(); }
    return readFileSync(path);
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

// Un 412 solo cuenta si A tuvo éxito y el contenido sigue siendo el de A.
export function classify(a, b, finalHash, hashA, hashB, hasValidator) {
  if (a !== 200) return 'inconclusive';
  if (hasValidator && b === 412 && finalHash === hashA) return 'condition_observed';
  if (b === 200 && finalHash === hashB) {
    return hasValidator ? 'stale_condition_not_enforced' : 'unconditional_last_writer';
  }
  return 'inconclusive';
}

export async function runProbe({ tokenA, tokenB, folderId, request = fetch, log = console.log }) {
  if (!tokenA || !tokenB || tokenA === tokenB || !folderId) throw new Error('missing_two_sessions');
  const payload = { base: sqlitePayload('base'), A: sqlitePayload('A'), B: sqlitePayload('B') };
  const aliases = new Map();
  const alias = (value, prefix) => {
    if (!value) return null;
    if (!aliases.has(value)) aliases.set(value, `${prefix}${aliases.size + 1}`);
    return aliases.get(value);
  };
  async function http(writer, phase, path, { method = 'GET', body, headers = {} } = {}) {
    const response = await request(`${root}${path}`, {
      method, body, redirect: 'error', signal: AbortSignal.timeout(30000),
      headers: { Authorization: `Bearer ${writer === 'B' ? tokenB : tokenA}`, ...headers },
    });
    const bytes = Buffer.from(await response.arrayBuffer());
    let data = {};
    if (response.headers.get('content-type')?.includes('json')) {
      try { data = JSON.parse(bytes.toString()); } catch { /* inconclusive response */ }
    }
    const etag = response.headers.get('etag');
    // Ningún ID, Location, Bearer, cuerpo externo ni mensaje Google en el informe.
    log(JSON.stringify({ writer, phase, method, status: response.status,
      ifMatch: alias(headers['If-Match'], 'E'), etag: alias(etag, 'E'),
      version: /^\d+$/.test(data.version) ? data.version : null,
      revision: alias(data.headRevisionId, 'R'),
      syntheticMd5: /^[a-f0-9]{32}$/.test(data.md5Checksum) ? data.md5Checksum : null }));
    return { status: response.status, data, etag, bytes, location: response.headers.get('location') };
  }
  const report = [];
  for (const mode of ['media', 'multipart', 'resumable', 'resumable-shared-sessions']) {
    const uploadType = mode.startsWith('resumable') ? 'resumable' : mode;
    const boundary = `probe_${randomUUID()}`;
    const multipart = (metadata, bytes) => Buffer.concat([
      Buffer.from(`--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}\r\n--${boundary}\r\nContent-Type: application/vnd.sqlite3\r\n\r\n`),
      bytes, Buffer.from(`\r\n--${boundary}--\r\n`),
    ]);
    const created = await http('A', `${mode}:create-scratch`,
      `/upload/drive/v3/files?uploadType=multipart&fields=${fields}`, {
        method: 'POST', body: multipart({ name: `autofinance-probe-${mode}-${randomUUID()}.sqlite`,
          parents: [folderId], appProperties: { autofinanceRole: 'conditionalWriteProbeV1' } }, payload.base),
        headers: { 'Content-Type': `multipart/related; boundary=${boundary}` },
      });
    if (created.status !== 200 || !created.data.id) throw new Error('scratch_creation_failed');
    const id = encodeURIComponent(created.data.id);
    const metaPath = `/drive/v3/files/${id}?fields=${fields}`;
    const uploadPath = `/upload/drive/v3/files/${id}?uploadType=${uploadType}&fields=${fields}`;
    // Dos lectores terminan ANTES de A. B conserva la versión/ETag anterior.
    const beforeA = await http('A', `${mode}:read-base`, metaPath);
    const beforeB = await http('B', `${mode}:read-base`, metaPath);
    if (beforeA.status !== 200 || beforeB.status !== 200 ||
        !beforeA.data.version || beforeA.data.version !== beforeB.data.version ||
        beforeA.data.md5Checksum !== md5(payload.base) || beforeB.data.md5Checksum !== md5(payload.base) ||
        beforeA.etag !== beforeB.etag) throw new Error('base_not_shared');
    async function init(writer, etag) {
      return http(writer, `${mode}:init`, uploadPath, {
        method: 'PATCH', body: '{}', headers: { ...(etag ? { 'If-Match': etag } : {}),
          'Content-Type': 'application/json', 'X-Upload-Content-Type': 'application/vnd.sqlite3',
          'X-Upload-Content-Length': String(payload[writer].length) },
      });
    }
    async function upload(writer, etag, preparedSession) {
      const conditional = etag ? { 'If-Match': etag } : {};
      if (uploadType !== 'resumable') return http(writer, `${mode}:write`, uploadPath, {
        method: 'PATCH', body: mode === 'media' ? payload[writer] : multipart({}, payload[writer]),
        headers: { ...conditional, 'Content-Type': mode === 'media' ? 'application/vnd.sqlite3' : `multipart/related; boundary=${boundary}` },
      });
      const session = preparedSession ?? await init(writer, etag);
      if (session.status !== 200 || !session.location) return session;
      const url = new URL(session.location);
      if (url.origin !== root || !url.pathname.startsWith('/upload/drive/v3/files/')) throw new Error('invalid_session_origin');
      return http(writer, `${mode}:commit`, url.pathname + url.search, {
        method: 'PUT', body: payload[writer], headers: { ...conditional,
          'Content-Type': 'application/vnd.sqlite3',
          'Content-Range': `bytes 0-${payload[writer].length - 1}/${payload[writer].length}` },
      });
    }
    // Detecta servidores que verifican solo el inicio de sesión, no el commit.
    const sessionA = mode === 'resumable-shared-sessions' ? await init('A', beforeA.etag) : undefined;
    const sessionB = mode === 'resumable-shared-sessions' ? await init('B', beforeB.etag) : undefined;
    const a = await upload('A', beforeA.etag, sessionA);
    const b = await upload('B', beforeB.etag, sessionB);
    const after = await http('B', `${mode}:read-final`, metaPath);
    const content = await http('B', `${mode}:verify-bytes`, `/drive/v3/files/${id}?alt=media`);
    const hash = content.status === 200 && after.status === 200 && md5(content.bytes) === after.data.md5Checksum
      ? md5(content.bytes) : null;
    const revisions = await http('A', `${mode}:revisions`,
      `/drive/v3/files/${id}/revisions?fields=nextPageToken,revisions(id,md5Checksum)&pageSize=1000`);
    const result = classify(a.status, b.status, hash, md5(payload.A), md5(payload.B), !!beforeA.etag);
    const row = { mode, result, validatorAvailable: !!beforeA.etag,
      // Informativo; no prueba retención futura ni exige historial completo.
      previousWriterInHistory: revisions.status === 200 && Array.isArray(revisions.data.revisions)
        ? revisions.data.revisions.some(r => r.md5Checksum === md5(payload.A)) : null };
    report.push(row);
    log(JSON.stringify(row));
  }
  return report;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.slice(2).join(' ') !== '--live') {
    console.error('Uso: node scripts/probe-drive-conditional-write.mjs --live');
    process.exitCode = 2;
  } else {
    try {
      const report = await runProbe({ tokenA: process.env.AUTOFINANCE_PROBE_TOKEN_A,
        tokenB: process.env.AUTOFINANCE_PROBE_TOKEN_B, folderId: process.env.AUTOFINANCE_PROBE_FOLDER_ID });
      if (report.some(r => r.result === 'inconclusive' || !r.validatorAvailable)) process.exitCode = 2;
    } catch {
      console.error('Ensayo bloqueado o indeterminado; revisar sesiones, carpeta y red en privado. No acredita capacidad de Drive.');
      process.exitCode = 2;
    }
  }
}
