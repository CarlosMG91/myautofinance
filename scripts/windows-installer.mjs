import { readFileSync, writeFileSync, mkdirSync, existsSync, lstatSync, realpathSync } from 'node:fs';
import { resolve, relative, isAbsolute, dirname, parse } from 'node:path';
import { fileURLToPath } from 'node:url';
import { applicationVersion, inventory, compareInventory, verifyPayload, safePath, sha256 } from './windows-payload.mjs';

const requireValue = (value, message) => { if (!value) throw new Error(message); };
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const contract = JSON.parse(readFileSync(resolve(root, 'packaging/windows/installation-contract.json'), 'utf8'));
const pins = JSON.parse(readFileSync(resolve(root, 'packaging/windows/payload-toolchain.json'), 'utf8'));
export const bridgePath = 'installer/autofinance_setup_bridge.dll';

export function privateOutputPath(output, privateRoot = resolve(root, contract.privateOutputDirectory)) {
  const absolute = resolve(output), rel = relative(privateRoot, absolute);
  requireValue(rel && !rel.startsWith('..') && !isAbsolute(rel), 'Salida fuera de dist-private/windows.');
  for (let path = absolute; path !== parse(path).root; path = dirname(path)) if (existsSync(path))
    requireValue(!lstatSync(path).isSymbolicLink() && realpathSync(path).toLowerCase() === path.toLowerCase(), 'Enlaces/alias en la salida privada.');
  return absolute;
}

export function installerPath(path) {
  safePath(path);
  requireValue(/^[\x20-\x7e]+$/.test(path) && !/["{};*?<>|]/.test(path), 'Ruta del inventario no admitida por el adaptador.');
  requireValue(!/(sqlite|drive-sync|local-backups|credentials|token|snapshot|diagnostics|client_secret)/i.test(path) || path === 'sqlite3.dll', 'Datos o secretos fuera del inventario binario.');
  requireValue(!/^\.autofinance-/i.test(path) && !/^unins\d+\./i.test(path) && path !== bridgePath, 'Ruta reservada del instalador.');
  return path;
}

// Inno 6's adapter is Win32 /MT; inspect without loading it. PE32 and its normal
// AND delay imports must only refer to Windows components, never the host CRT.
export function verifyBridge(bytes) {
  requireValue(bytes.length >= 64 && bytes.readUInt16LE(0) === 0x5a4d, 'Adaptador PE ausente.');
  const pe = bytes.readUInt32LE(0x3c), optional = pe + 24;
  requireValue(pe + 248 <= bytes.length && bytes.readUInt32LE(pe) === 0x4550 && bytes.readUInt16LE(pe + 4) === 0x14c && bytes.readUInt16LE(optional) === 0x10b, 'Inno 6 requiere adaptador Win32.');
  const sectionCount = bytes.readUInt16LE(pe + 6), optionalSize = bytes.readUInt16LE(pe + 20), sections = optional + optionalSize;
  requireValue(optionalSize >= 224 && sections + sectionCount * 40 <= bytes.length, 'Adaptador PE truncado.');
  function offset(rva) {
    for (let i = 0; i < sectionCount; ++i) {
      const at = sections + i * 40, delta = rva - bytes.readUInt32LE(at + 12);
      if (delta >= 0 && delta < bytes.readUInt32LE(at + 16)) {
        const result = bytes.readUInt32LE(at + 20) + delta;
        requireValue(result < bytes.length, 'RVA del adaptador fuera de archivo.'); return result;
      }
    }
    throw new Error('RVA del adaptador no resoluble.');
  }
  const imports = new Set();
  for (const [index, width, nameOffset] of [[1, 20, 12], [13, 32, 4]]) {
    const rva = bytes.readUInt32LE(optional + 96 + index * 8), size = bytes.readUInt32LE(optional + 100 + index * 8);
    if (!rva) continue;
    const at = offset(rva); let terminated = false;
    for (let entry = at; entry + width <= at + size && entry + width <= bytes.length; entry += width) {
      if (bytes.subarray(entry, entry + width).every(b => b === 0)) { terminated = true; break; }
      if (index === 13) requireValue(bytes.readUInt32LE(entry) === 1, 'Delay import debe usar RVA.');
      const nameAt = offset(bytes.readUInt32LE(entry + nameOffset)), end = bytes.indexOf(0, nameAt);
      requireValue(end > nameAt && end - nameAt < 100, 'Import del adaptador no válido.');
      const name = bytes.toString('ascii', nameAt, end).toLowerCase();
      requireValue(['kernel32.dll', 'user32.dll', 'advapi32.dll', 'bcrypt.dll', 'shell32.dll', 'ole32.dll', 'version.dll', 'ntdll.dll'].includes(name), 'El adaptador requiere una dependencia ajena a Windows o un CRT global.');
      imports.add(name);
    }
    requireValue(terminated, 'Imports del adaptador truncados.');
  }
  return [...imports].sort();
}

export function validateCandidate(manifest, actual, pubspec, { commit, toolchainHash, lockfileHash, payloadToolchainHash } = {}) {
  const version = applicationVersion(pubspec);
  requireValue(manifest.payloadManifestVersion === 1 && manifest.installationContractVersion === 1 && manifest.appId === contract.appId, 'Contrato de payload distinto.');
  requireValue(manifest.architecture === 'x64' && manifest.appEnvironment === 'production' && manifest.sourceDirty === false && /^[0-9a-f]{40}$/.test(manifest.sourceCommit), 'Se requiere candidato production x64 de commit limpio.');
  requireValue(manifest.applicationVersion === version.applicationVersion && manifest.windowsVersion === version.windowsVersion, 'Versión distinta de pubspec.');
  requireValue(!commit || manifest.sourceCommit === commit, 'Payload y script deben pertenecer al mismo commit.');
  requireValue(manifest.toolchain?.inno === pins.inno.version && manifest.toolchain?.msvc === pins.msvc && manifest.toolchain?.windowsSdk === pins.windowsSdk, 'Toolchain del payload distinta del pin.');
  for (const [field, expected] of [['toolchainSha256', toolchainHash], ['lockfileSha256', lockfileHash], ['payloadToolchainSha256', payloadToolchainHash]])
    if (expected) requireValue(manifest.toolchain[field] === expected, 'Entradas del payload alteradas.');
  requireValue(manifest.runtime?.version === pins.runtimeFileVersion && manifest.runtime.source === pins.runtimeSource && pins.runtimeFiles.every(path => actual.some(file => file.path === path)), 'CRT app-local incompleto.');
  requireValue(Array.isArray(manifest.licenses) && manifest.licenses.length >= 6 && manifest.licenses.every(file => actual.some(value => value.path === file.path && value.sha256 === file.sha256 && value.size === file.size)), 'Licencias incompletas o alteradas.');
  compareInventory(manifest.payload, actual);
  actual.forEach(file => installerPath(file.path));
  return version;
}

const innoString = value => {
  requireValue(!/["\r\n\x00]/.test(value), 'Valor Inno no válido.');
  return value.replaceAll('{', '{{');
};
export function ownershipManifest(version, files) {
  requireValue(/^\d+\.\d+\.\d+\.\d+$/.test(version), 'Versión PE no válida.');
  return `AutofinanceFilesV1\t${contract.appId}\t${version}\n` + files.map(file => {
    if (file.path !== bridgePath) installerPath(file.path);
    requireValue(/^[0-9a-f]{64}$/.test(file.sha256) && Number.isSafeInteger(file.size) && file.size >= 0, 'Inventario no válido.');
    return `${file.sha256}\t${file.size}\t${file.path}\n`;
  }).join('');
}

export function writePackage({ payload, files, bridge, output, version }) {
  requireValue(!existsSync(output), 'La salida ya existe; no se sobreescribe una entrega.');
  const bridgeBytes = readFileSync(bridge);
  const bridgeImports = verifyBridge(bridgeBytes);
  const bridgeEntry = { path: bridgePath, size: bridgeBytes.length, sha256: sha256(bridgeBytes) };
  requireValue(files.some(file => file.path === 'myautofinance.exe'), 'Falta EXE del payload.');
  const owned = [...files, bridgeEntry];
  // Keep the launch path absent until every dependent payload file is in place.
  const copyOrder = [...files.filter(file => file.path !== 'myautofinance.exe'), files.find(file => file.path === 'myautofinance.exe')];
  files.forEach(file => installerPath(file.path));
  mkdirSync(output, { recursive: true });
  const manifestPath = resolve(output, '.autofinance-files');
  const manifestBytes = Buffer.from(ownershipManifest(version.windowsVersion, owned), 'utf8');
  writeFileSync(manifestPath, manifestBytes);
  const fileLine = (source, dest, flags) => `Source: "${innoString(resolve(source))}"; DestDir: "${dest}"; Flags: ${flags}`;
  const lines = [
    `#define ApplicationVersion "${version.applicationVersion}"`,
    `#define WindowsVersion "${version.windowsVersion}"`,
    `#define PrivateOutput "${innoString(resolve(output))}"`,
    '[Files]',
    fileLine(bridge, '{tmp}', 'dontcopy'),
    fileLine(resolve(payload, 'myautofinance.exe'), '{tmp}', 'dontcopy'),
    fileLine(manifestPath, '{tmp}', 'dontcopy'),
    fileLine(bridge, '{app}\\installer', 'ignoreversion'),
    fileLine(manifestPath, '{app}', 'ignoreversion'),
    ...copyOrder.map(file => {
      const folder = file.path.includes('/') ? '\\' + file.path.slice(0, file.path.lastIndexOf('/')).replaceAll('/', '\\') : '';
      return fileLine(resolve(payload, file.path), '{app}' + innoString(folder), 'ignoreversion');
    }),
  ];
  writeFileSync(resolve(output, 'package.iss.inc'), lines.join('\n') + '\n');
  const installationMetadata = { path: '.autofinance-files', size: manifestBytes.length, sha256: sha256(manifestBytes) };
  writeFileSync(resolve(output, 'installer-inputs.json'), JSON.stringify({ installerInputsVersion: 1, ...version, payload: owned, installationMetadata, bridgeImports, verification: 'candidate; native clean-profile acceptance pending', signing: 'notObserved; build script records actual signatures' }, null, 2) + '\n');
  return owned;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [command, payload, candidate, bridge, output, commit] = process.argv.slice(2);
    requireValue(command === 'prepare' && output && /^[0-9a-f]{40}$/.test(commit), 'Uso: windows-installer.mjs prepare payload payload-manifest bridge salida commit');
    privateOutputPath(output);
    const files = inventory(payload);
    const version = validateCandidate(JSON.parse(readFileSync(candidate, 'utf8')), files, readFileSync(resolve(root, 'pubspec.yaml'), 'utf8'), {
      commit,
      toolchainHash: sha256(readFileSync(resolve(root, 'toolchain.json'))),
      lockfileHash: sha256(readFileSync(resolve(root, 'pubspec.lock'))),
      payloadToolchainHash: sha256(readFileSync(resolve(root, 'packaging/windows/payload-toolchain.json'))),
    });
    verifyPayload(payload, files);
    writePackage({ payload, files, bridge, output, version });
    console.log('Entrada Inno privada preparada; no es entrega final T06 ni aceptación T08.');
  } catch (error) {
    console.error(error.code ? 'No se pudo leer/escribir la entrada Inno.' : error.message);
    process.exitCode = 1;
  }
}
