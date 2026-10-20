import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verifyPair, verifyPreservation, pendingRuntimeChecks, kernelPageSize } from '../android-upgrade.mjs';

const manifest = versionCode => ({ appEnvironment: 'test', purpose: 'ci-ephemeral-fixture',
  buildMode: 'release', format: 'universal-apk', expectedCertificate: 'fixture-cert',
  apk: { applicationId: 'com.carlosmg91.myautofinance', debuggable: false,
    certificateSha256: 'fixture-cert', versionCode },
  checks: Object.fromEntries(['apksigner', 'aapt2', 'zipalign16KB', 'elf16KB', 'payload', 'sourceStable'].map(k => [k, true])) });
const snapshot = () => ({ ok: true, snapshot: {
  tables: { database_state: [{ dataset_id: 'synthetic-id', revision: 21 }],
    movements: [{ amount_cents: -243, discretion: 'Sintético', import_row_id: 'row-2' }] },
  files: { 'drive-sync/state.json': 'pending-operation',
    'sqlite/local-backups/backups/id/autofinance.sqlite': 'image-hash',
    'sqlite/local-backups/catalog-a.json': 'catalog-hash', 'journal-1.json': 'journal-hash' } },
  native: { package: 'com.carlosmg91.myautofinance', keyAlias: 'same-alias', keyCreated: 10,
    ciphertextSha256: 'original-encrypted-record', versionCode: 1 } });

test('T05 release pair requires same verified certificate and increasing installed version', () => {
  assert.doesNotThrow(() => verifyPair(manifest(1), manifest(2)));
  for (const change of [m => m.appEnvironment = 'production', m => m.buildMode = 'debug',
    m => m.apk.debuggable = true, m => m.apk.applicationId += '.other',
    m => m.expectedCertificate = 'other', m => m.apk.certificateSha256 = 'other',
    m => m.apk.versionCode = 1, m => m.checks = {}, m => m.checks.sourceStable = false]) {
    const next = manifest(2); change(next);
    assert.throws(() => verifyPair(manifest(1), next));
  }
});

test('preservation checks semantic content, provenance and support byte hashes', () => {
  const before = snapshot(), after = snapshot();
  after.native.versionCode = 2;
  assert.doesNotThrow(() => verifyPreservation(before, after));
  for (const change of [s => s.snapshot.tables.database_state[0].dataset_id = 'new-id',
    s => s.snapshot.tables.database_state[0].revision = 0,
    s => s.snapshot.tables.movements[0].discretion = null,
    s => s.snapshot.tables.movements[0].import_row_id = null,
    s => delete s.snapshot.files['drive-sync/state.json'],
    s => s.native.keyCreated++, s => s.native.ciphertextSha256 = 'rewritten', s => s.ok = false]) {
    const changed = snapshot(); change(changed);
    assert.throws(() => verifyPreservation(before, changed));
  }
});

test('legitimate recovery may append journals and change catalog, never lose images or sync state', () => {
  const before = snapshot(), after = snapshot();
  after.snapshot.files['sqlite/local-backups/catalog-a.json'] = 'next-generation';
  after.snapshot.files['journal-2.json'] = 'new-journal';
  assert.throws(() => verifyPreservation(before, after));
  assert.doesNotThrow(() => verifyPreservation(before, after, { recovery: true }));
  for (const path of ['journal-1.json', 'drive-sync/state.json']) {
    const changed = structuredClone(after); delete changed.snapshot.files[path];
    assert.throws(() => verifyPreservation(before, changed, { recovery: true }));
    changed.snapshot.files[path] = 'replaced';
    assert.throws(() => verifyPreservation(before, changed, { recovery: true }));
  }
  delete after.snapshot.files['sqlite/local-backups/backups/id/autofinance.sqlite'];
  assert.throws(() => verifyPreservation(before, after, { recovery: true }));
});

test('runtime gates use measured API and pages, never infer a phone from translated ABI', () => {
  const device = { api: 37, pageSize: 4096, supportedAbis: ['x86_64', 'arm64-v8a'] };
  assert.deepEqual(pendingRuntimeChecks(device),
    ['API24', 'API36', '16KB-runtime', 'ARM64-phone-T09', 'production-Google-Openbank-T09']);
  assert.deepEqual(pendingRuntimeChecks({ ...device, api: 36, pageSize: 16384 }),
    ['API24', 'ARM64-phone-T09', 'production-Google-Openbank-T09']);
  assert.ok(!pendingRuntimeChecks({ ...device, api: 24 }).includes('API24'));
  assert.throws(() => pendingRuntimeChecks(device, { expectedApi: '36' }));
  assert.throws(() => pendingRuntimeChecks(device, { expectedPages: '16384' }));
  assert.doesNotThrow(() => pendingRuntimeChecks(device, { expectedApi: '37', expectedPages: '4096' }));
  for (const missing of ['api', 'pageSize', 'supportedAbis']) {
    const incomplete = { ...device }; delete incomplete[missing];
    assert.throws(() => pendingRuntimeChecks(incomplete));
  }
});

test('API 24 page measurement uses real kernel mappings and rejects absent or ambiguous evidence', () => {
  assert.equal(kernelPageSize('KernelPageSize:        4 kB\nMMUPageSize: 4 kB\nKernelPageSize: 4 kB\n'), 4096);
  assert.equal(kernelPageSize('KernelPageSize:\t16 kB\r\n'), 16384);
  for (const text of ['', 'MMUPageSize: 4 kB', 'KernelPageSize: 0 kB',
    'KernelPageSize: 4 kB\nKernelPageSize: 16 kB']) {
    assert.throws(() => kernelPageSize(text));
  }
});
