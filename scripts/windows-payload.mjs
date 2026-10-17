import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, lstatSync, realpathSync, writeFileSync } from 'node:fs';
import { resolve, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const requireValue = (value, message) => { if (!value) throw new Error(message); };

export function applicationVersion(pubspec) {
  const matches = [...pubspec.matchAll(/^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$/gm)];
  requireValue(matches.length === 1, 'Version de pubspec no admitida.');
  const parts = matches[0].slice(1).map(Number);
  requireValue(parts.every(n => n <= 65535) && parts[3] > 0, 'Version fuera de rango PE.');
  return { applicationVersion: `${parts[0]}.${parts[1]}.${parts[2]}+${parts[3]}`, windowsVersion: parts.join('.') };
}

export function safePath(path) {
  requireValue(typeof path === 'string' && path.length > 0 && !path.includes('\\')
    && !/[:\x00-\x1f]/.test(path) && path.split('/').every(p => p && p !== '.' && p !== '..'
      && !/[. ]$/.test(p) && !/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(p)), 'Ruta de paquete no valida.');
  return path;
}

export function inventory(directory) {
  const result = [];
  const names = new Set();
  function walk(folder, prefix = '') {
    for (const item of readdirSync(folder, { withFileTypes: true })) {
      const path = safePath(prefix + item.name);
      requireValue(!names.has(path.toLowerCase()), 'Colision de rutas Windows.');
      names.add(path.toLowerCase());
      const full = resolve(folder, item.name);
      requireValue(!lstatSync(full).isSymbolicLink() && realpathSync(full).toLowerCase() === full.toLowerCase(), 'Enlaces/reparse points no admitidos.');
      requireValue(!/(^|\/)(?:fixtures?|snapshots?|logs?|tokens?|certificates?|drive-sync|local-backups|sqlite|backups|diagnostics|copies|\.git|\.dart_tool|node_modules|\.pub-cache)(\/|\.)/i.test(path)
        && !/\.(?:sqlite(?:-(?:wal|shm|journal))?|db|csv|tsv|xlsx|bak|backup|log|pdb|ilk|exp|lib|key|pem|pfx|p12|jks|keystore|ps1|bat|cmd|iss)$/i.test(path)
        && !/(?:client_secret|credentials|oauth-session|token[s]?\.json|(?:^|\/)state\.json|catalog-[ab]\.json)/i.test(path), 'Archivo excluido de distribucion.');
      requireValue(!/^(?:msvcp\d+(?:_\d+)?d|vcruntime\d+(?:_\d+)?d|ucrtbased)\.dll$/i.test(item.name), 'Runtime Debug prohibido.');
      if (item.isDirectory()) walk(full, path + '/');
      else {
        requireValue(item.isFile(), 'Solo se admiten archivos regulares.');
        const bytes = readFileSync(full);
        result.push({ path, size: bytes.length, sha256: sha256(bytes) });
      }
    }
  }
  walk(resolve(directory));
  return result.sort((a, b) => a.path.localeCompare(b.path, 'en'));
}

// Read ordinary AND delay-load imports without loading DLLs or consulting System32.
export function peImports(bytes) {
  requireValue(bytes.length >= 64 && bytes.readUInt16LE(0) === 0x5a4d, 'PE: cabecera DOS ausente.');
  const pe = bytes.readUInt32LE(0x3c);
  requireValue(pe + 264 <= bytes.length && bytes.readUInt32LE(pe) === 0x4550, 'PE: cabecera no valida.');
  requireValue(bytes.readUInt16LE(pe + 4) === 0x8664 && bytes.readUInt16LE(pe + 24) === 0x20b, 'PE debe ser AMD64/PE32+.');
  const sectionCount = bytes.readUInt16LE(pe + 6);
  const optionalSize = bytes.readUInt16LE(pe + 20);
  const optional = pe + 24;
  const sections = optional + optionalSize;
  requireValue(optionalSize >= 240 && sections + sectionCount * 40 <= bytes.length, 'PE truncado.');
  function offset(rva) {
    for (let i = 0; i < sectionCount; i++) {
      const s = sections + i * 40;
      const virtualAddress = bytes.readUInt32LE(s + 12);
      const rawSize = bytes.readUInt32LE(s + 16);
      const delta = rva - virtualAddress;
      if (delta >= 0 && delta < rawSize) {
        const at = bytes.readUInt32LE(s + 20) + delta;
        requireValue(at < bytes.length, 'RVA fuera de archivo.');
        return at;
      }
    }
    throw new Error('RVA no resoluble.');
  }
  function name(rva) {
    const at = offset(rva);
    const end = bytes.indexOf(0, at);
    requireValue(end > at && end - at < 260, 'Nombre importado no valido.');
    const value = bytes.toString('ascii', at, end).toLowerCase();
    requireValue(/^[a-z0-9_.-]+\.dll$/.test(value), 'Importacion no localizable.');
    return value;
  }
  const imports = new Set();
  for (const [index, width, nameOffset] of [[1, 20, 12], [13, 32, 4]]) {
    requireValue(bytes.readUInt32LE(optional + 108) > index, 'PE sin directorios de importacion.');
    const rva = bytes.readUInt32LE(optional + 112 + index * 8);
    const size = bytes.readUInt32LE(optional + 116 + index * 8);
    if (!rva) continue;
    const start = offset(rva);
    let terminated = false;
    for (let entry = start; entry + width <= start + size && entry + width <= bytes.length; entry += width) {
      if (bytes.subarray(entry, entry + width).every(b => b === 0)) { terminated = true; break; }
      if (index === 13) requireValue(bytes.readUInt32LE(entry) === 1, 'Delay import debe usar RVA.');
      imports.add(name(bytes.readUInt32LE(entry + nameOffset)));
    }
    requireValue(terminated, 'Tabla de importacion truncada.');
  }
  return [...imports].sort();
}

// Explicit Windows 10/11 inbox dependencies. Unknown imports fail closed.
const systemDlls = new Set(('advapi32 avrt bcrypt cfgmgr32 comctl32 comdlg32 crypt32 cryptbase d2d1 d3d9 d3d11 d3d12 dcomp dbghelp dinput8 dnsapi dwmapi dwrite dxgi dxguid gdi32 hid imm32 iphlpapi kernel32 kernelbase mf mfplat mfreadwrite mfuuid mpr msimg32 msvcrt ncrypt netapi32 normaliz ntdll ole32 oleacc oleaut32 opengl32 powrprof propsys psapi rpcrt4 secur32 setupapi shell32 shcore shlwapi uiautomationcore user32 userenv usp10 uxtheme version winhttp wininet winmm winspool wintrust wldap32 ws2_32 wtsapi32 ucrtbase').split(' ').map(n => n + '.dll'));
export function dependencyClosure(directory, files) {
  const paths = new Set(files.map(f => f.path.toLowerCase()));
  return files.filter(f => /\.(dll|exe)$/i.test(f.path)).map(file => {
    const imports = peImports(readFileSync(resolve(directory, file.path)));
    for (const dll of imports) {
      requireValue(!/(?:msvcp|vcruntime|ucrtbase)\d*d\.dll$/.test(dll), 'Runtime Debug prohibido.');
      const folder = file.path.includes('/') ? file.path.slice(0, file.path.lastIndexOf('/') + 1).toLowerCase() : '';
      requireValue(paths.has(folder + dll) || paths.has(dll) || systemDlls.has(dll)
        || /^api-ms-win-[a-z0-9-]+\.dll$/.test(dll) || /^ext-ms-win-[a-z0-9-]+\.dll$/.test(dll), `Dependencia ausente: ${dll}.`);
    }
    return { path: file.path, imports };
  });
}

export function verifyPayload(directory, files = inventory(directory), { checkDependencies = true } = {}) {
  const paths = new Set(files.map(f => f.path));
  for (const path of ['myautofinance.exe', 'flutter_windows.dll', 'sqlite3.dll', 'data/app.so', 'data/icudtl.dat',
    'data/flutter_assets/AssetManifest.bin', 'data/flutter_assets/FontManifest.json', 'data/flutter_assets/NOTICES.Z',
    ...['regular', 'medium', 'bold'].map(w => `data/flutter_assets/assets/fonts/roboto-${w}.ttf`)]) {
    requireValue(paths.has(path) && files.find(f => f.path === path).size > 0, `Falta contenido obligatorio: ${path}.`);
  }
  // Flutter's Windows AOT snapshot is ELF, loaded by Dart rather than Win32.
  const aot = readFileSync(resolve(directory, 'data/app.so'));
  requireValue(aot.length >= 64 && aot.subarray(0, 4).equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46]))
    && aot[4] === 2 && aot[5] === 1 && aot.readUInt16LE(18) === 62, 'AOT debe ser ELF64 x86-64 little-endian.');
  // FFI native assets are checked as well as PE imports (SQLite is loaded dynamically).
  const native = files.filter(f => /(?:^|\/)(?:native_assets|NativeAssetsManifest)\.json$/.test(f.path));
  for (const file of native) {
    const manifest = JSON.parse(readFileSync(resolve(directory, file.path), 'utf8'));
    function inspect(value) {
      if (Array.isArray(value) && ['absolute', 'relative'].includes(value[0])) {
        // Flutter desktop encodes DLL basenames as ["absolute", "sqlite3.dll"].
        // The enum name does not mean a host-absolute path; reject drive/UNC paths.
        requireValue(value[0] === 'absolute' && typeof value[1] === 'string' && !value[1].includes('/'), 'Mapeo native asset distinto del formato desktop fijado.');
        const path = safePath(value[1]);
        requireValue(paths.has(path), 'Native asset ausente del payload.');
      } else if (value && typeof value === 'object') Object.values(value).forEach(inspect);
    }
    inspect(manifest);
  }
  return checkDependencies ? dependencyClosure(directory, files) : [];
}

export function compareInventory(expected, actual) {
  requireValue(JSON.stringify([...expected].sort((a,b) => a.path.localeCompare(b.path, 'en')))
    === JSON.stringify([...actual].sort((a,b) => a.path.localeCompare(b.path, 'en'))), 'Inventario cerrado alterado: faltan, sobran o cambiaron archivos.');
}

export function cmakeInventory(text, directory) {
  return text.split(/\r?\n/).filter(Boolean).map(line => {
    const path = relative(resolve(directory), resolve(line)).split(sep).join('/');
    return safePath(path);
  });
}

export function checkOfficialOutput(directory, installManifest) {
  const actual = inventory(directory);
  const expected = new Set(cmakeInventory(installManifest, directory));
  // Flutter builds the runner in-place; install(TARGETS) can omit it from install_manifest.
  expected.add('myautofinance.exe');
  requireValue(actual.length === expected.size && actual.every(f => expected.has(f.path)), 'Salida Flutter distinta de install_manifest: contenido obsoleto o no inventariado.');
  verifyPayload(directory, actual, { checkDependencies: false });
  return actual;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [command, directory, manifestPath] = process.argv.slice(2);
    requireValue(['inventory', 'verify', 'official'].includes(command) && directory && manifestPath, 'Uso: windows-payload.mjs inventory|verify|official directorio manifiesto');
    const files = inventory(directory);
    const imports = verifyPayload(directory, files);
    if (command === 'verify') {
      const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
      compareInventory(manifest.payload, files);
    } else if (command === 'official') {
      checkOfficialOutput(directory, readFileSync(manifestPath, 'utf8'));
    } else writeFileSync(manifestPath, JSON.stringify({ payload: files, imports }, null, 2) + '\n');
    console.log(`Payload x64: ${files.length} archivos comprobados; sin ejecutar la aplicacion.`);
  } catch (error) {
    console.error(error.code ? 'No se pudo leer/escribir el payload.' : error.message);
    process.exitCode = 1;
  }
}
