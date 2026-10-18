import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { installerPath, privateOutputPath, verifyBridge, validateCandidate, ownershipManifest, writePackage } from '../windows-installer.mjs';
import { sha256 } from '../windows-payload.mjs';
const pins = JSON.parse(readFileSync(new URL('../../packaging/windows/payload-toolchain.json', import.meta.url)));
const appId = '{82D31B27-9717-4DB7-AB32-D098BF3C2859}';
function pe32(regular = [], delay = []) {
  const b = Buffer.alloc(4096);
  b.writeUInt16LE(0x5a4d); b.writeUInt32LE(128, 0x3c); b.writeUInt32LE(0x4550, 128);
  b.writeUInt16LE(0x14c, 132); b.writeUInt16LE(1, 134); b.writeUInt16LE(224, 148);
  b.writeUInt16LE(0x10b, 152); b.writeUInt32LE(16, 244);
  b.writeUInt32LE(0x1000, 388); b.writeUInt32LE(3584, 392); b.writeUInt32LE(512, 396);
  let nameAt = 2048;
  for (const [names, index, at, width, nameOffset] of [[regular, 1, 512, 20, 12], [delay, 13, 1024, 32, 4]]) {
    if (!names.length) continue;
    b.writeUInt32LE(at - 512 + 0x1000, 152 + 96 + index * 8);
    b.writeUInt32LE((names.length + 1) * width, 152 + 100 + index * 8);
    names.forEach((name, i) => {
      if (index === 13) b.writeUInt32LE(1, at + i * width);
      b.writeUInt32LE(nameAt - 512 + 0x1000, at + i * width + nameOffset);
      b.write(name, nameAt); nameAt += name.length + 1;
    });
  }
  return b;
}
function candidate() {
  const files = ['myautofinance.exe', ...pins.runtimeFiles, ...Array.from({ length: 6 }, (_, i) => `licenses/license-${i}.txt`)].map(path => ({ path, size: 5, sha256: 'a'.repeat(64) }));
  return {
    payloadManifestVersion: 1, installationContractVersion: 1, appId,
    architecture: 'x64', appEnvironment: 'production', sourceDirty: false, sourceCommit: 'b'.repeat(40),
    applicationVersion: '0.1.0+1', windowsVersion: '0.1.0.1', payload: files,
    toolchain: { inno: pins.inno.version, msvc: pins.msvc, windowsSdk: pins.windowsSdk },
    runtime: { version: pins.runtimeFileVersion, source: pins.runtimeSource },
    licenses: files.filter(file => file.path.startsWith('licenses/')),
  };
}
test('adaptador Win32 solo importa Windows, sin CRT global ni delay CRT', () => {
  assert.deepEqual(verifyBridge(pe32(['KERNEL32.dll', 'bcrypt.dll'], ['advapi32.dll'])), ['advapi32.dll', 'bcrypt.dll', 'kernel32.dll']);
  assert.throws(() => verifyBridge(pe32(['vcruntime140.dll'])));
  assert.throws(() => verifyBridge(pe32([], ['msvcp140.dll'])));
  assert.throws(() => verifyBridge(Buffer.alloc(10)));
  const x64 = pe32(); x64.writeUInt16LE(0x8664, 132); assert.throws(() => verifyBridge(x64));
});
test('version de pubspec, identidad, entorno y commit deben coincidir', () => {
  const m = candidate();
  assert.equal(validateCandidate(m, m.payload, 'version: 0.1.0+1\n').windowsVersion, '0.1.0.1');
  for (const patch of [{ applicationVersion: '0.1.0+2' }, { windowsVersion: '0.1.0.2' }, { sourceDirty: true }, { appId: 'other' }, { architecture: 'arm64' }, { appEnvironment: 'test' }])
    assert.throws(() => validateCandidate({ ...m, ...patch }, m.payload, 'version: 0.1.0+1\n'));
  assert.throws(() => validateCandidate(m, m.payload, 'version: 0.1.0+1\n', { commit: 'c'.repeat(40) }));
});
test('inventario alterado, CRT/licencias ausentes y toolchain divergente se rechazan', () => {
  const m = candidate();
  assert.throws(() => validateCandidate(m, m.payload.slice(1), 'version: 0.1.0+1'));
  assert.throws(() => validateCandidate({ ...m, runtime: {} }, m.payload, 'version: 0.1.0+1'));
  assert.throws(() => validateCandidate({ ...m, licenses: [] }, m.payload, 'version: 0.1.0+1'));
  assert.throws(() => validateCandidate({ ...m, toolchain: { ...m.toolchain, inno: 'latest' } }, m.payload, 'version: 0.1.0+1'));
  assert.throws(() => validateCandidate(m, m.payload, 'version: 0.1.0+1', { lockfileHash: 'changed' }));
});
test('rutas reservadas, finanzas e inyeccion Inno nunca entran en el inventario', () => {
  for (const path of ['../x', 'a\\b', 'x:ads', 'x/{app}', 'x;evil', 'x"evil', 'sqlite/a.sqlite', 'drive-sync/state.json', '.autofinance-files', 'unins000.exe', 'installer/autofinance_setup_bridge.dll'])
    assert.throws(() => installerPath(path));
  assert.equal(installerPath('sqlite3.dll'), 'sqlite3.dll');
  assert.equal(installerPath('data/flutter_assets/FontManifest.json'), 'data/flutter_assets/FontManifest.json');
});
test('manifiesto de propiedad es cerrado, sin datos y con hash/tamano', () => {
  const file = { path: 'myautofinance.exe', size: 42, sha256: 'a'.repeat(64) };
  assert.equal(ownershipManifest('0.1.0.1', [file]), `AutofinanceFilesV1\t${appId}\t0.1.0.1\n${file.sha256}\t42\tmyautofinance.exe\n`);
  assert.throws(() => ownershipManifest('0.1.0+1', [file]));
  assert.throws(() => ownershipManifest('0.1.0.1', [{ ...file, sha256: 'no' }]));
});
test('produccion solo sale bajo dist-private/windows, ni raiz ni otra unidad', () => {
  assert.match(privateOutputPath('dist-private/windows/synthetic-path-check'), /synthetic-path-check$/);
  for (const output of ['dist-private/windows', 'dist-private/windows/../public', '.tools/elsewhere', 'Z:\\elsewhere'])
    assert.throws(() => privateOutputPath(output));
});
test('incluye cada archivo explicitamente y conserva constantes literales en origen', () => {
  // Private temporary compiler inputs only. Retained for diagnosis, no recursive delete.
  const base = mkdtempSync(join(tmpdir(), 'af-installer-'));
  const payload = join(base, 'payload {literal}'); mkdirSync(payload);
  const bridge = join(base, 'autofinance_setup_bridge.dll'); writeFileSync(bridge, pe32(['kernel32.dll']));
  writeFileSync(join(payload, 'myautofinance.exe'), 'synthetic');
  const file = { path: 'myautofinance.exe', size: 9, sha256: sha256(Buffer.from('synthetic')) };
  const options = { payload, files: [file], bridge, output: join(base, 'output'), version: { applicationVersion: '0.1.0+1', windowsVersion: '0.1.0.1' } };
  const owned = writePackage(options);
  assert.equal(owned.length, 2);
  const include = readFileSync(join(base, 'output/package.iss.inc'), 'utf8');
  const metadata = JSON.parse(readFileSync(join(base, 'output/installer-inputs.json'))).installationMetadata;
  assert.equal(metadata.sha256, sha256(readFileSync(join(base, 'output/.autofinance-files'))));
  assert.equal(metadata.size, readFileSync(join(base, 'output/.autofinance-files')).length);
  assert.match(include, /payload \{\{literal\}/);
  assert.match(include, /Flags: dontcopy/);
  assert.match(include, /DestDir: "\{app\}\\installer"/);
  assert.match(include.trim().split('\n').at(-1), /myautofinance\.exe"; DestDir: "\{app\}"; Flags: ignoreversion/);
  assert.doesNotMatch(include, /recursesubdirs|restartreplace|uninsdeletekey|sharedfile/);
  assert.throws(() => writePackage(options), /ya existe/);
});
