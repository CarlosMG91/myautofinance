import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdirSync, writeFileSync, mkdtempSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { validateDelivery, finalizeDelivery, verifyDelivery } from '../windows-delivery.mjs';
import { ownershipManifest, bridgePath } from '../windows-installer.mjs';
import { sha256, inventory } from '../windows-payload.mjs';

const pins = JSON.parse(readFileSync(new URL('../../packaging/windows/payload-toolchain.json', import.meta.url)));
function fixture() {
  const entry = path => ({ path, size: 5, sha256: 'a'.repeat(64) });
  const actual = ['myautofinance.exe', ...pins.runtimeFiles, ...Array.from({ length: 6 }, (_, i) => `licenses/license-${i}.txt`)].map(entry);
  const commit = 'b'.repeat(40), bridge = entry(bridgePath), installer = Buffer.from('synthetic EXE bytes');
  const payload = { payloadManifestVersion: 1, installationContractVersion: 1, appId: '{82D31B27-9717-4DB7-AB32-D098BF3C2859}',
    architecture: 'x64', appEnvironment: 'production', sourceDirty: false, sourceCommit: commit,
    applicationVersion: '0.1.0+1', windowsVersion: '0.1.0.1', payload: actual,
    toolchain: { inno: pins.inno.version, msvc: pins.msvc, windowsSdk: pins.windowsSdk, toolchainSha256: 't', lockfileSha256: 'l', payloadToolchainSha256: 'p' },
    runtime: { version: pins.runtimeFileVersion, source: pins.runtimeSource }, licenses: actual.filter(file => file.path.startsWith('licenses/')) };
  const inputs = { installerInputsVersion: 1, applicationVersion: payload.applicationVersion, windowsVersion: payload.windowsVersion, payload: [...actual, bridge] };
  const ownership = Buffer.from(ownershipManifest(payload.windowsVersion, inputs.payload));
  const build = { installerBuildVersion: 1, sourceDirty: false, sourceCommit: commit, appId: payload.appId,
    applicationVersion: payload.applicationVersion, windowsVersion: payload.windowsVersion,
    installer: { path: 'Autofinance-0.1.0+1-windows-x64-private.exe', windowsVersion: payload.windowsVersion, signing: 'NotSigned', size: installer.length, sha256: sha256(installer) },
    bridge: { sha256: bridge.sha256, runtime: 'static' }, inputs: { payloadManifestSha256: 'm', ownershipManifestSha256: sha256(ownership) } };
  return { payload, actual, build, inputs, quality: { status: 'passed', command: 'scripts/check-quality.ps1', sourceCommit: commit, lockfileSha256: 'l', toolchainSha256: 't' },
    pubspec: 'version: 0.1.0+1\n', evidence: { commit, toolchainHash: 't', lockfileHash: 'l', payloadToolchainHash: 'p', payloadManifestHash: 'm' }, installer, ownership };
}

test('cierra solo calidad, payload e instalador coherentes de produccion', () => {
  assert.equal(validateDelivery(fixture()).windowsVersion, '0.1.0.1');
});

test('calidad fallida/ausente, fuentes sucias, test, versiones, firma y bytes alterados bloquean entrega', () => {
  const changes = [
    f => { f.quality.status = 'failed'; }, f => { f.quality.sourceCommit = 'c'.repeat(40); },
    f => { f.quality.command = 'skip'; }, f => { f.quality.lockfileSha256 = 'changed'; },
    f => { f.payload.appEnvironment = 'test'; }, f => { f.payload.sourceDirty = true; },
    f => { f.payload.toolchain.inno = 'latest'; }, f => { f.actual.pop(); },
    f => { f.build.windowsVersion = '0.1.0.2'; }, f => { f.build.sourceCommit = 'c'.repeat(40); },
    f => { f.build.installer.windowsVersion = '0.1.0.2'; }, f => { f.build.installer.signing = 'UnknownError'; },
    f => { f.installer = Buffer.from('altered'); }, f => { f.build.inputs.payloadManifestSha256 = 'changed'; },
    f => { f.ownership = Buffer.from('altered'); }, f => { f.build.bridge.sha256 = 'changed'; },
    f => { f.inputs.payload.push({ path: 'extra.exe', size: 5, sha256: 'a'.repeat(64) }); },
    f => { f.inputs.applicationVersion = '0.1.0+2'; }, f => { f.payload.licenses = []; },
  ];
  for (const change of changes) { const f = fixture(); change(f); assert.throws(() => validateDelivery(f), change.toString()); }
});

test('CI publica exclusivamente el informe sintetico y no permite produccion ni perfil personal', () => {
  const workflow = readFileSync(new URL('../../.github/workflows/windows-installer.yml', import.meta.url), 'utf8');
  assert.equal((workflow.match(/uses: actions\/upload-artifact/g) ?? []).length, 1);
  assert.match(workflow, /path: \.tools\/installer-ci-report\/report\.json/);
  assert.doesNotMatch(workflow, /contents: write|release|pages|build-private-windows-delivery|prepare-windows-payload/);
  const script = readFileSync(new URL('../check-windows-installer-ci.ps1', import.meta.url), 'utf8');
  assert.match(script, /RUNNER_ENVIRONMENT -cne 'github-hosted'/);
  assert.ok(script.indexOf('El perfil no esta vacio') < script.indexOf('RunInstaller $fixtures'));
});

test('copia entrega completa, detecta corrupcion/extras y nunca finaliza un candidato fallido', () => {
  const parent = resolve('dist-private/windows'); mkdirSync(parent, { recursive: true });
  const base = mkdtempSync(resolve(parent, 'synthetic-delivery-test-'));
  const payloadDirectory = resolve(base, 'payload'), output = resolve(base, 'installer');
  mkdirSync(output); mkdirSync(payloadDirectory);
  const put = (path, bytes) => { const full = resolve(payloadDirectory, path); mkdirSync(dirname(full), { recursive: true }); writeFileSync(full, bytes); };
  const pe = Buffer.alloc(4096);
  pe.writeUInt16LE(0x5a4d); pe.writeUInt32LE(128, 0x3c); pe.writeUInt32LE(0x4550, 128);
  pe.writeUInt16LE(0x8664, 132); pe.writeUInt16LE(1, 134); pe.writeUInt16LE(240, 148);
  pe.writeUInt16LE(0x20b, 152); pe.writeUInt32LE(16, 260);
  pe.writeUInt32LE(3584, 400); pe.writeUInt32LE(0x1000, 404); pe.writeUInt32LE(3584, 408); pe.writeUInt32LE(512, 412);
  const f = fixture();
  for (const path of ['myautofinance.exe', 'flutter_windows.dll', 'sqlite3.dll', ...pins.runtimeFiles]) put(path, pe);
  for (const path of ['data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin', 'data/flutter_assets/FontManifest.json', 'data/flutter_assets/NOTICES.Z',
    ...['regular', 'medium', 'bold'].map(w => `data/flutter_assets/assets/fonts/roboto-${w}.ttf`), ...f.payload.licenses.map(file => file.path)]) put(path, 'synthetic');
  const aot = Buffer.alloc(64); aot.set([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1]); aot.writeUInt16LE(62, 18); put('data/app.so', aot);
  f.actual = inventory(payloadDirectory); f.payload.payload = f.actual;
  f.payload.licenses = f.actual.filter(file => file.path.startsWith('licenses/'));
  const rootHash = path => sha256(readFileSync(resolve(path)));
  Object.assign(f.payload.toolchain, { toolchainSha256: rootHash('toolchain.json'), lockfileSha256: rootHash('pubspec.lock'), payloadToolchainSha256: rootHash('packaging/windows/payload-toolchain.json') });
  Object.assign(f.quality, { toolchainSha256: f.payload.toolchain.toolchainSha256, lockfileSha256: f.payload.toolchain.lockfileSha256 });
  f.inputs.payload = [...f.actual, f.inputs.payload.find(file => file.path === bridgePath)];
  f.ownership = Buffer.from(ownershipManifest(f.payload.windowsVersion, f.inputs.payload));
  const json = (path, value) => writeFileSync(path, JSON.stringify(value));
  const payloadManifest = resolve(base, 'payload-manifest.json'), qualityPath = resolve(output, 'quality.json');
  json(payloadManifest, f.payload); json(qualityPath, f.quality);
  f.build.inputs = { payloadManifestSha256: rootHash(payloadManifest), ownershipManifestSha256: sha256(f.ownership) };
  json(resolve(output, 'installer-build.json'), f.build); json(resolve(output, 'installer-inputs.json'), f.inputs);
  writeFileSync(resolve(output, '.autofinance-files'), f.ownership);
  const exe = resolve(output, f.build.installer.path); writeFileSync(exe, 'altered');
  assert.throws(() => finalizeDelivery(payloadDirectory, payloadManifest, output, qualityPath, f.evidence.commit));
  assert.equal(existsSync(resolve(output, 'delivery/delivery-manifest.json')), false);
  writeFileSync(exe, f.installer);
  const result = finalizeDelivery(payloadDirectory, payloadManifest, output, qualityPath, f.evidence.commit);
  assert.equal(result.verification.status, 'buildVerified'); assert.match(result.verification.cleanWindowsE2E, /pending/);
  const delivery = resolve(output, 'delivery');
  assert.doesNotThrow(() => verifyDelivery(delivery));
  assert.throws(() => finalizeDelivery(payloadDirectory, payloadManifest, output, qualityPath, f.evidence.commit), /ya existe/);
  writeFileSync(resolve(delivery, 'unexpected.txt'), 'extra');
  assert.throws(() => verifyDelivery(delivery), /Inventario/);
  // Synthetic files are retained under ignored dist-private for diagnosis.
});
