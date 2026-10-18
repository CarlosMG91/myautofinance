import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { inspectE2EPair } from '../check-windows-e2e-inputs.mjs';
import { inventory, sha256 } from '../windows-payload.mjs';

const pins = JSON.parse(readFileSync(new URL('../../packaging/windows/payload-toolchain.json', import.meta.url)));
const appId = '{82D31B27-9717-4DB7-AB32-D098BF3C2859}';
const parent = resolve('dist-private/windows');
mkdirSync(parent, { recursive: true });

// Deliberately fake bytes: passing this preflight is never E2E evidence.
function fixture(version, commit, alter = () => {}) {
  const directory = mkdtempSync(resolve(parent, 'synthetic-e2e-input-'));
  const windowsVersion = version.replace('+', '.');
  const file = path => ({ path, size: 9, sha256: 'a'.repeat(64) });
  const files = ['myautofinance.exe', ...pins.runtimeFiles, ...Array.from({ length: 6 }, (_, i) => `licenses/license-${i}.txt`)].map(file);
  const payload = { payloadManifestVersion: 1, installationContractVersion: 1, appId, architecture: 'x64',
    appEnvironment: 'production', sourceDirty: false, sourceCommit: commit, applicationVersion: version, windowsVersion,
    toolchain: { inno: pins.inno.version, msvc: pins.msvc, windowsSdk: pins.windowsSdk, toolchainSha256: 't', lockfileSha256: 'l' },
    runtime: { version: pins.runtimeFileVersion, source: pins.runtimeSource }, payload: files, licenses: files.slice(-6) };
  const installer = Buffer.from(`not executable: ${version}`);
  const build = { installerBuildVersion: 1, appId, applicationVersion: version, windowsVersion, sourceDirty: false, sourceCommit: commit,
    inputs: {}, installer: { path: `Autofinance-${version}-windows-x64-private.exe`, windowsVersion, signing: 'NotSigned', size: installer.length, sha256: sha256(installer) } };
  const quality = { status: 'passed', command: 'scripts/check-quality.ps1', sourceCommit: commit, toolchainSha256: 't', lockfileSha256: 'l' };
  const delivery = { deliveryManifestVersion: 1, distribution: 'privateLocalOnly', architecture: 'x64', appEnvironment: 'production',
    applicationVersion: version, windowsVersion, sourceCommit: commit, sourceDirty: false, toolchain: structuredClone(payload.toolchain),
    verification: { status: 'buildVerified', quality: 'passed', payload: 'passed', installer: 'passed', cleanWindowsE2E: 'pending T08' },
    signing: { status: 'unsigned', observedAuthenticode: 'NotSigned' } };
  alter({ payload, build, quality, delivery });
  const json = (name, value) => writeFileSync(resolve(directory, name), JSON.stringify(value));
  json('payload-manifest.json', payload);
  build.inputs.payloadManifestSha256 = sha256(readFileSync(resolve(directory, 'payload-manifest.json')));
  json('installer-build.json', build); json('quality.json', quality);
  writeFileSync(resolve(directory, `Autofinance-${version}-windows-x64-private.exe`), installer);
  delivery.files = inventory(directory); json('delivery-manifest.json', delivery);
  return directory;
}
const previous = fixture('0.1.0+9', 'a'.repeat(40));
const next = alter => fixture('0.1.0+10', 'b'.repeat(40), alter);

test('par coherente, comparacion numerica y resultado explicitamente sin E2E', () => {
  const result = inspectE2EPair(previous, next());
  assert.equal(result.status, 'inputsConsistent');
  assert.equal(result.e2e, 'notExecuted');
  assert.match(result.previous.installer.sha256, /^[0-9a-f]{64}$/);
  assert.equal(inspectE2EPair(previous, fixture('0.2.0+1', 'c'.repeat(40))).next.windowsVersion, '0.2.0.1');
});

test('igualdad, downgrade y mismo commit no demuestran actualizacion', () => {
  assert.throws(() => inspectE2EPair(previous, previous), /numericamente/);
  assert.throws(() => inspectE2EPair(next(), previous), /numericamente/);
  assert.throws(() => inspectE2EPair(previous, fixture('0.1.0+10', 'a'.repeat(40))), /commits/);
});

test('rechaza incoherencia entre manifiestos aun recalculando inventario externo', () => {
  const mutations = [
    f => { f.payload.appId = 'other'; }, f => { f.payload.appEnvironment = 'test'; },
    f => { f.payload.sourceCommit = 'c'.repeat(40); }, f => { f.payload.toolchain.msvc = 'latest'; },
    f => { f.delivery.toolchain.lockfileSha256 = 'changed'; }, f => { f.delivery.windowsVersion = '0.1.0.11'; },
    f => { f.build.appId = 'other'; }, f => { f.build.sourceDirty = true; },
    f => { f.build.installer.sha256 = '0'.repeat(64); }, f => { f.build.installer.windowsVersion = '0.1.0.11'; },
    f => { f.quality.status = 'failed'; }, f => { f.quality.sourceCommit = 'c'.repeat(40); },
    f => { f.quality.lockfileSha256 = 'changed'; }, f => { f.delivery.verification.payload = 'pending'; },
    f => { f.delivery.signing.observedAuthenticode = 'UnknownError'; },
  ];
  for (const mutation of mutations) assert.throws(() => inspectE2EPair(previous, next(mutation)), mutation.toString());
});

test('rechaza bytes alterados, extras o entrega ausente antes de cualquier ejecucion', () => {
  const changed = next();
  writeFileSync(resolve(changed, 'Autofinance-0.1.0+10-windows-x64-private.exe'), 'altered');
  assert.throws(() => inspectE2EPair(previous, changed));
  const extra = next(); writeFileSync(resolve(extra, 'unexpected.txt'), 'extra');
  assert.throws(() => inspectE2EPair(previous, extra));
  assert.throws(() => inspectE2EPair(previous, resolve(parent, 'absent-e2e-delivery')));
});
