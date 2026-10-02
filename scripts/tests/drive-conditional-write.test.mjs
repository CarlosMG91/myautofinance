import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { classify, runProbe, sqlitePayload } from '../probe-drive-conditional-write.mjs';

test('solo rechazo con contenido conservado acredita condición observada', () => {
  assert.equal(classify(200, 412, 'A', 'A', 'B', true), 'condition_observed');
  assert.equal(classify(200, 412, 'B', 'A', 'B', true), 'inconclusive');
  assert.equal(classify(401, 412, 'A', 'A', 'B', true), 'inconclusive');
  assert.equal(classify(200, 403, 'A', 'A', 'B', true), 'inconclusive');
  assert.equal(classify(200, 200, 'B', 'A', 'B', true), 'stale_condition_not_enforced');
  assert.equal(classify(200, 200, 'B', 'A', 'B', false), 'unconditional_last_writer');
  assert.equal(classify(200, 412, 'A', 'A', 'B', false), 'inconclusive');
});

test('fixtures SQLite diferentes con cabecera binaria real', () => {
  const a = sqlitePayload('A'), b = sqlitePayload('B');
  assert.equal(a.subarray(0, 16).toString(), 'SQLite format 3\0');
  assert.notDeepEqual(a, b);
});

for (const behavior of ['enforced', 'ignored', 'init-only', 'no-etag']) {
  test(`orquestación completa con servidor falso ${behavior} (no evidencia Google)`, async () => {
    let version = 1, current, history = [], serial = 0;
    const logs = [];
    const hash = bytes => createHash('md5').update(bytes).digest('hex');
    function extract(body) {
      const bytes = Buffer.from(body);
      const start = bytes.indexOf(Buffer.from('SQLite format 3\0'));
      return bytes.subarray(start, bytes.lastIndexOf(Buffer.from('\r\n--')));
    }
    const request = async (url, options) => {
      assert.equal(new URL(url).origin, 'https://www.googleapis.com');
      assert.equal(options.redirect, 'error');
      const headers = { 'Content-Type': 'application/json' };
      if (behavior !== 'no-etag') headers.ETag = `"private-etag-${version}"`;
      const meta = () => ({ id: 'private-file-id', version: String(version),
        md5Checksum: hash(current), headRevisionId: `private-revision-${version}` });
      if (options.method === 'POST') {
        current = extract(options.body); version = 1; history = [hash(current)];
        return new Response(JSON.stringify(meta()), { headers });
      }
      if (options.method === 'GET') {
        if (url.includes('alt=media')) return new Response(current);
        if (url.includes('/revisions?')) return new Response(JSON.stringify({
          revisions: history.map(md5Checksum => ({ md5Checksum })) }), { headers });
        return new Response(JSON.stringify(meta()), { headers });
      }
      const stale = options.headers['If-Match'] && options.headers['If-Match'] !== `"private-etag-${version}"`;
      const init = options.method === 'PATCH' && url.includes('uploadType=resumable');
      if (stale && (behavior === 'enforced' || (behavior === 'init-only' && init))) {
        return new Response('{}', { status: 412, headers });
      }
      if (init) return new Response('{}', { headers: { ...headers,
        Location: `https://www.googleapis.com/upload/drive/v3/files/private-file-id?upload_id=private-session-${serial++}` } });
      current = options.headers['Content-Type'].startsWith('multipart') ? extract(options.body) : Buffer.from(options.body);
      version++; history.push(hash(current));
      return new Response(JSON.stringify(meta()), { headers });
    };
    const rows = await runProbe({ tokenA: 'secret-token-A', tokenB: 'secret-token-B',
      folderId: 'private-folder', request, log: line => logs.push(line) });
    assert.equal(rows.length, 4);
    for (const row of rows) {
      const expected = behavior === 'enforced' ? 'condition_observed'
        : behavior === 'no-etag' ? 'unconditional_last_writer'
        : behavior === 'init-only' && row.mode === 'resumable' ? 'condition_observed'
        : 'stale_condition_not_enforced';
      assert.equal(row.result, expected);
      assert.equal(row.previousWriterInHistory, true);
    }
    assert.doesNotMatch(logs.join('\n'), /secret-token|private-|upload_id|Authorization/);
    const phases = logs.map(line => JSON.parse(line).phase).filter(Boolean);
    assert.ok(phases.indexOf('media:read-base') < phases.indexOf('media:write'));
  });
}

test('sesiones ausentes/iguales no hacen ninguna petición', async () => {
  for (const config of [{}, { tokenA: 'same', tokenB: 'same', folderId: 'F' }]) {
    await assert.rejects(runProbe({ ...config, request: () => assert.fail('red no permitida') }), /missing_two_sessions/);
  }
});
