import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { inventory, sha256, compareInventory, verifyPayload } from './windows-payload.mjs';
import { validateCandidate, privateOutputPath, ownershipManifest, bridgePath } from './windows-installer.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const hash = path => sha256(readFileSync(path));
const requireValue = (value, message) => { if (!value) throw new Error(message); };

export function validateDelivery({ payload, actual, build, inputs, quality, pubspec, evidence, installer, ownership }) {
  const version = validateCandidate(payload, actual, pubspec, evidence);
  requireValue(quality.status === 'passed' && quality.command === 'scripts/check-quality.ps1' && quality.sourceCommit === evidence.commit &&
    quality.lockfileSha256 === evidence.lockfileHash && quality.toolchainSha256 === evidence.toolchainHash, 'Calidad ausente, fallida o de otras fuentes.');
  requireValue(build.installerBuildVersion === 1 && build.sourceDirty === false && build.sourceCommit === evidence.commit &&
    build.appId === payload.appId && build.applicationVersion === version.applicationVersion && build.windowsVersion === version.windowsVersion, 'Instalador de otras fuentes/version.');
  requireValue(build.installer.path === `Autofinance-${version.applicationVersion}-windows-x64-private.exe` &&
    build.installer.windowsVersion === version.windowsVersion && build.installer.signing === 'NotSigned' &&
    build.installer.size === installer.length && build.installer.sha256 === sha256(installer), 'EXE/firma/version alterados.');
  requireValue(build.inputs.payloadManifestSha256 === evidence.payloadManifestHash &&
    build.inputs.ownershipManifestSha256 === sha256(ownership), 'Manifiestos de entrada alterados.');
  requireValue(inputs.installerInputsVersion === 1 && inputs.applicationVersion === version.applicationVersion && inputs.windowsVersion === version.windowsVersion, 'Version de entrada Inno distinta.');
  const bridge = inputs.payload.find(file => file.path === bridgePath);
  requireValue(bridge && bridge.sha256 === build.bridge.sha256 && build.bridge.runtime === 'static', 'Adaptador no verificable.');
  compareInventory([...actual, bridge], inputs.payload);
  requireValue(ownership.toString('utf8') === ownershipManifest(version.windowsVersion, inputs.payload), 'Inventario de propiedad no coincide.');
  return version;
}

export function finalizeDelivery(payloadDirectory, payloadManifestPath, output, qualityPath, commit) {
  privateOutputPath(output);
  const destination = privateOutputPath(resolve(output, 'delivery'));
  requireValue(!existsSync(destination), 'La entrega ya existe; no se sobreescribe.');
  const payload = read(payloadManifestPath), build = read(resolve(output, 'installer-build.json'));
  const inputs = read(resolve(output, 'installer-inputs.json')), quality = read(qualityPath);
  const actual = inventory(payloadDirectory);
  // Validate basename before reading any path from a manifest.
  requireValue(build.installer?.path === `Autofinance-${payload.applicationVersion}-windows-x64-private.exe` && /^\d+\.\d+\.\d+\+\d+$/.test(payload.applicationVersion), 'Nombre EXE no valido.');
  const installerPath = resolve(output, build.installer.path), installer = readFileSync(installerPath);
  const evidence = { commit, toolchainHash: hash(resolve(root, 'toolchain.json')), lockfileHash: hash(resolve(root, 'pubspec.lock')),
    payloadToolchainHash: hash(resolve(root, 'packaging/windows/payload-toolchain.json')), payloadManifestHash: hash(payloadManifestPath) };
  const version = validateDelivery({ payload, actual, build, inputs, quality, pubspec: readFileSync(resolve(root, 'pubspec.yaml'), 'utf8'), evidence,
    installer, ownership: readFileSync(resolve(output, '.autofinance-files')) });
  verifyPayload(payloadDirectory, actual);
  mkdirSync(destination);
  const copy = (source, path) => { mkdirSync(dirname(resolve(destination, path)), { recursive: true }); copyFileSync(source, resolve(destination, path)); };
  copy(installerPath, build.installer.path);
  copy(payloadManifestPath, 'payload-manifest.json');
  copy(resolve(output, 'installer-build.json'), 'installer-build.json');
  copy(qualityPath, 'quality.json');
  for (const file of payload.licenses) copy(resolve(payloadDirectory, file.path), file.path);
  const files = inventory(destination);
  // Check the copy too; write the delivery manifest last, never after a failure.
  requireValue(files.find(file => file.path === build.installer.path)?.sha256 === build.installer.sha256 &&
    files.find(file => file.path === 'payload-manifest.json')?.sha256 === evidence.payloadManifestHash, 'Copia de entrega alterada.');
  for (const file of payload.licenses) requireValue(files.some(value => value.path === file.path && value.sha256 === file.sha256 && value.size === file.size), 'Licencia copiada alterada.');
  const pins = read(resolve(root, 'packaging/windows/payload-toolchain.json'));
  const manifest = { deliveryManifestVersion: 1, ...version, sourceCommit: commit, sourceDirty: false, appEnvironment: 'production', architecture: 'x64',
    distribution: 'privateLocalOnly', builtAtUtc: new Date().toISOString(), toolchain: payload.toolchain,
    inno: pins.inno, signing: { status: 'unsigned', observedAuthenticode: build.installer.signing },
    integrity: 'SHA256 solo detecta cambios accidentales; no acredita autoria, confianza ni SmartScreen.',
    verification: { status: 'buildVerified', quality: 'passed', payload: 'passed', installer: 'passed', cleanWindowsE2E: 'pending T08' }, files };
  writeFileSync(resolve(destination, 'delivery-manifest.json'), JSON.stringify(manifest, null, 2) + '\n', { flag: 'wx' });
  verifyDelivery(destination);
  return manifest;
}

export function verifyDelivery(directory) {
  const manifest = read(resolve(directory, 'delivery-manifest.json'));
  requireValue(manifest.deliveryManifestVersion === 1 && manifest.distribution === 'privateLocalOnly' && manifest.appEnvironment === 'production' &&
    manifest.architecture === 'x64' && manifest.sourceDirty === false && /^[0-9a-f]{40}$/.test(manifest.sourceCommit) &&
    manifest.verification?.status === 'buildVerified' && manifest.signing?.observedAuthenticode === 'NotSigned', 'Contrato de entrega no valido.');
  compareInventory(manifest.files, inventory(directory).filter(file => file.path !== 'delivery-manifest.json'));
  return manifest;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv[2] === 'verify') {
      requireValue(process.argv.length === 4, 'Uso: windows-delivery.mjs verify directorio');
      verifyDelivery(process.argv[3]);
      console.log('Integridad local coincide con el manifiesto. No acredita autoria ni confianza de Windows.');
    } else {
    requireValue(process.argv.length === 7 && /^[0-9a-f]{40}$/.test(process.argv[6]), 'Uso: windows-delivery.mjs payload manifiesto salida calidad commit');
    finalizeDelivery(...process.argv.slice(2));
    console.log('Manifiesto privado generado. Compilacion verificada; E2E pendiente. No publicar.');
    }
  } catch (error) { console.error(error.code ? 'Fallo de archivos al cerrar entrega privada.' : error.message); process.exitCode = 1; }
}
