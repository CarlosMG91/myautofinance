import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { applicationVersion, safePath, inventory, compareInventory, peImports, verifyPayload, checkOfficialOutput, dependencyClosure } from '../windows-payload.mjs';

// Synthetic PE32+ with one section and regular/delay import descriptors.
function pe(regular = [], delay = []) {
  const b = Buffer.alloc(4096);
  b.writeUInt16LE(0x5a4d); b.writeUInt32LE(128, 0x3c);
  b.writeUInt32LE(0x4550, 128); b.writeUInt16LE(0x8664, 132);
  b.writeUInt16LE(1, 134); b.writeUInt16LE(240, 148);
  b.writeUInt16LE(0x20b, 152); b.writeUInt32LE(16, 260);
  b.writeUInt32LE(3584, 400); b.writeUInt32LE(0x1000, 404);
  b.writeUInt32LE(3584, 408); b.writeUInt32LE(512, 412);
  let stringOffset = 2048;
  for (const [names, index, at, width, nameOffset] of [[regular, 1, 512, 20, 12], [delay, 13, 1024, 32, 4]]) {
    if (!names.length) continue;
    b.writeUInt32LE(at - 512 + 0x1000, 152 + 112 + index * 8);
    b.writeUInt32LE((names.length + 1) * width, 152 + 116 + index * 8);
    names.forEach((name, i) => {
      if (index === 13) b.writeUInt32LE(1, at + i * width);
      b.writeUInt32LE(stringOffset - 512 + 0x1000, at + i * width + nameOffset);
      b.write(name, stringOffset, 'ascii'); stringOffset += name.length + 1;
    });
  }
  return b;
}
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'af-payload-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const put = (path, content = 'synthetic') => {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), content);
  };
  for (const path of ['data/app.so', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin',
    'data/flutter_assets/FontManifest.json', 'data/flutter_assets/NOTICES.Z',
    ...['regular', 'medium', 'bold'].map(w => `data/flutter_assets/assets/fonts/roboto-${w}.ttf`)]) put(path);
  for (const path of ['myautofinance.exe', 'flutter_windows.dll', 'sqlite3.dll']) put(path, pe(['kernel32.dll']));
  const aot = Buffer.alloc(64); aot.set([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1]); aot.writeUInt16LE(62, 18);
  put('data/app.so', aot);
  put('data/flutter_assets/NativeAssetsManifest.json', JSON.stringify({ 'native-assets': { windows_x64: { sqlite: ['absolute', 'sqlite3.dll'] } } }));
  return { root, put };
}

test('version unica, numerica, con build y limites PE', () => {
  assert.deepEqual(applicationVersion('version: 0.1.0+1\n'), { applicationVersion: '0.1.0+1', windowsVersion: '0.1.0.1' });
  for (const invalid of ['1.0.0', '1.0.0+0', '65536.0.0+1', '1.0.0-rc+1', '1.0.0+999999']) assert.throws(() => applicationVersion(`version: ${invalid}`));
});
test('rutas Windows sin traversal, ADS, UNC o nombres reservados', () => {
  for (const path of ['../x', '/x', 'x/../y', 'C:/x', '\\\\host\\x', 'x\\y', 'x:token', 'x//y', 'nul.txt', 'x./y', 'x /y']) assert.throws(() => safePath(path));
  assert.equal(safePath('data/á espacio.ttf'), 'data/á espacio.ttf');
});
test('PE x64 lee imports normales y delay-load; rechaza truncados/x86', () => {
  assert.deepEqual(peImports(pe(['kernel32.dll'], ['vcruntime140.dll'])), ['kernel32.dll', 'vcruntime140.dll']);
  assert.throws(() => peImports(Buffer.alloc(16)));
  const x86 = pe(); x86.writeUInt16LE(0x14c, 132); assert.throws(() => peImports(x86));
  const badRva = pe(['missing.dll']); badRva.writeUInt32LE(0xffffffff, 524); assert.throws(() => peImports(badRva));
});
test('inventario completo conserva plugins, SQLite, fuentes y data; detecta alteracion y extras', t => {
  const { root, put } = fixture(t);
  put('plugin_real.dll', pe()); put('licenses/flutter.txt', 'synthetic notice');
  const files = inventory(root);
  assert.equal(verifyPayload(root, files).length, 4);
  put('sqlite3.dll', pe(['kernel32.dll', 'bcrypt.dll']));
  assert.throws(() => compareInventory(files, inventory(root)));
  put('extra.dat'); assert.throws(() => compareInventory(files, inventory(root)));
});
test('dependencias transitivas/dinamicas y runtime Debug ausente fallan', t => {
  const { root, put } = fixture(t);
  put('myautofinance.exe', pe(['vcruntime140.dll']));
  assert.throws(() => verifyPayload(root), /Dependencia ausente/);
  put('vcruntime140.dll', pe(['another.dll']));
  assert.throws(() => verifyPayload(root), /another.dll/);
  put('another.dll', pe(['ucrtbase.dll'])); assert.doesNotThrow(() => verifyPayload(root));
  put('another.dll', pe([], ['vcruntime140d.dll'])); assert.throws(() => verifyPayload(root), /Debug/);
});
test('SQLite se exige aunque ninguna tabla PE la importe', t => {
  const { root } = fixture(t); rmSync(join(root, 'sqlite3.dll'));
  assert.throws(() => verifyPayload(root), /sqlite3.dll/);
});
test('AOT Windows debe ser snapshot ELF64 x64; rechaza otra arquitectura o Debug sin AOT', t => {
  const { root, put } = fixture(t);
  put('data/app.so', Buffer.alloc(64)); assert.throws(() => verifyPayload(root), /AOT/);
  rmSync(join(root, 'data/app.so')); assert.throws(() => verifyPayload(root), /app.so/);
});
test('manifest native assets admite nombre local Flutter y rechaza ruta del host o DLL ausente', t => {
  const { root, put } = fixture(t);
  for (const path of ['C:/host/sqlite3.dll', '../sqlite3.dll', 'missing.dll']) {
    put('native_assets.json', JSON.stringify({ asset: ['absolute', path] }));
    assert.throws(() => verifyPayload(root));
  }
  put('native_assets.json', JSON.stringify({ asset: ['absolute', 'sqlite3.dll'] }));
  assert.doesNotThrow(() => verifyPayload(root));
});
test('datos financieros, secretos, Debug auxiliares y fixtures no son distribuibles', t => {
  for (const path of ['autofinance.sqlite', 'autofinance.sqlite-wal', 'state.db', 'tokens.json', 'client_secret.json',
    'cert.pfx', 'debug.pdb', 'vcruntime140d.dll', 'personal.log', 'history.csv', 'state.json', 'catalog-a.json',
    'drive-sync/private.json', 'copies/file.json', 'fixtures/synthetic.csv', 'logs/data.txt', 'snapshots/photo.json']) {
    const { root, put } = fixture(t); put(path); assert.throws(() => inventory(root), path);
  }
});
test('inventario oficial CMake cierra todos los archivos; no permite salida ajena/obsoleta', t => {
  const { root, put } = fixture(t);
  const manifest = inventory(root).filter(f => f.path !== 'myautofinance.exe').map(f => join(root, f.path)).join('\n');
  assert.doesNotThrow(() => checkOfficialOutput(root, manifest));
  put('obsolete.dll', pe()); assert.throws(() => checkOfficialOutput(root, manifest));
  assert.throws(() => checkOfficialOutput(root, manifest + '\n' + join(root, '..', 'elsewhere.dll')));
});
test('rechaza enlaces y colisiones de mayusculas', t => {
  const { root, put } = fixture(t); put('target.dat');
  // Junction creation is available without the symlink privilege on Windows.
  mkdirSync(join(root, 'target-dir'));
  symlinkSync(join(root, 'target-dir'), join(root, 'linked'), process.platform === 'win32' ? 'junction' : 'dir');
  assert.throws(() => inventory(root), /enlaces|reparse/i);
});
test('ninguna dependencia desconocida se toma de System32', t => {
  const { root, put } = fixture(t); put('plugin.dll', pe(['custom-global.dll']));
  assert.throws(() => dependencyClosure(root, inventory(root)), /custom-global/);
});
