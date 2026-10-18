// Inspector de solo lectura. No genera, instala ni declara una entrega completa.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const contract = JSON.parse(readFileSync(join(root, 'packaging/android/distribution-contract.json'), 'utf8'));

function requiredMatch(text, pattern, label) {
  const value = text.match(pattern)?.[1];
  if (!value) throw new Error(`No se puede acreditar ${label}.`);
  return value;
}

export function parseApk(badging, certificates) {
  const fingerprints = [...certificates.matchAll(/^Signer #\d+ certificate SHA-256 digest: ([a-f\d]{64})\s*$/gim)];
  if (fingerprints.length !== 1) throw new Error('Se requiere exactamente un certificado verificado.');
  return {
    applicationId: requiredMatch(badging, /package: name='([^']+)'/, 'paquete'),
    splitName: badging.match(/^package:.*\bsplit='([^']+)'/m)?.[1] ?? null,
    versionCode: Number(requiredMatch(badging, /\bversionCode='(\d+)'/, 'versionCode')),
    versionName: requiredMatch(badging, /\bversionName='([^']+)'/, 'versionName'),
    minimumSdk: Number(requiredMatch(badging, /(?:minSdkVersion|sdkVersion):'?(\d+)'?/, 'minSdk')),
    compileSdk: Number(requiredMatch(badging, /\bcompileSdkVersion='(\d+)'/, 'compileSdk')),
    targetSdk: Number(requiredMatch(badging, /targetSdkVersion:'?(\d+)'?/, 'targetSdk')),
    abis: [...requiredMatch(badging, /^native-code: (.+)$/m, 'ABIs').matchAll(/'([^']+)'/g)].map(x => x[1]),
    debuggable: /^application-debuggable\s*$/m.test(badging),
    debugCertificate: /^Signer #1 certificate DN:.*CN=Android Debug(?:,|\s|$)/mi.test(certificates),
    certificateSha256: fingerprints[0][1].toLowerCase(),
    certificateSha1: requiredMatch(certificates, /^Signer #1 certificate SHA-1 digest: ([a-f\d]{40})\s*$/im, 'SHA-1 de certificado').toLowerCase(),
  };
}

export function checkApk(apk, { version, expectedCertificate, allowDebug = false, previous, deviceApi, deviceAbis } = {}) {
  const problems = [];
  if (apk.splitName) problems.push('APK dividido: se requiere un APK universal independiente');
  for (const key of ['applicationId', 'minimumSdk', 'compileSdk', 'targetSdk']) {
    if (apk[key] !== contract[key]) problems.push(`${key} incompatible con el contrato`);
  }
  if (!Number.isSafeInteger(apk.versionCode) || apk.versionCode <= 0 || apk.versionCode > 2100000000) problems.push('versionCode fuera de rango');
  if (version) {
    const parsed = /^(\d+\.\d+\.\d+)\+([1-9]\d*)$/.exec(version);
    if (!parsed || apk.versionName !== parsed[1] || apk.versionCode !== Number(parsed[2])) problems.push('versión efectiva distinta de pubspec');
  }
  if (contract.requiredAbis.some(abi => !apk.abis.includes(abi)) || apk.abis.some(abi => !contract.supportedAbis.includes(abi))) problems.push('ABIs incompatibles: se requiere APK universal');
  if (!allowDebug && apk.debuggable) problems.push('APK debuggable: solo inspección de pruebas con --allow-debug');
  if (!allowDebug && apk.debugCertificate) problems.push('certificado Android Debug: no es firma de distribución');
  if (!allowDebug && !expectedCertificate) problems.push('falta certificado de distribución esperado e independiente del APK');
  if (expectedCertificate && (!/^[a-f\d]{64}$/i.test(expectedCertificate) || apk.certificateSha256 !== expectedCertificate.toLowerCase())) problems.push('certificado de distribución distinto o inválido');
  if (previous) {
    if (apk.applicationId !== previous.applicationId) problems.push('paquete distinto de la instalación anterior');
    if (apk.certificateSha256 !== previous.certificateSha256) problems.push('firma distinta: transición bloqueada; conservar datos e instalación');
    if (apk.versionCode <= previous.versionCode) problems.push('versionCode no creciente: actualización bloqueada');
  }
  if (deviceApi !== undefined && (!Number.isInteger(deviceApi) || deviceApi < apk.minimumSdk)) problems.push('API del dispositivo incompatible');
  if (deviceAbis !== undefined && !deviceAbis.some(abi => apk.abis.includes(abi))) problems.push('ABI del dispositivo incompatible');
  return problems;
}

export function inspectApk(path, sdk, jdk) {
  const hash = () => createHash('sha256').update(readFileSync(path)).digest('hex');
  const before = hash();
  const tools = join(sdk, 'build-tools', '36.0.0');
  const executable = process.platform === 'win32' ? '.exe' : '';
  const run = (command, args) => execFileSync(command, args, { encoding: 'utf8', timeout: 120000, stdio: ['ignore', 'pipe', 'pipe'] });
  const badging = run(join(tools, `aapt2${executable}`), ['dump', 'badging', resolve(path)]);
  // Java directo evita shell/.bat e impide interpretar rutas como comandos.
  const certificates = run(join(jdk, 'bin', `java${executable}`), ['-jar', join(tools, 'lib', 'apksigner.jar'), 'verify', '--verbose', '--print-certs', resolve(path)]);
  const result = parseApk(badging, certificates);
  result.apkSha256 = hash();
  if (result.apkSha256 !== before) throw new Error('El APK cambió durante la inspección; repetir sobre un archivo estable.');
  return result;
}

function main() {
  const { values } = parseArgs({ options: {
    apk: { type: 'string' }, sdk: { type: 'string' }, jdk: { type: 'string' },
    'expected-certificate': { type: 'string' }, 'previous-apk': { type: 'string' },
    'device-api': { type: 'string' }, 'device-abis': { type: 'string' },
    'allow-debug': { type: 'boolean', default: false },
  } });
  if (!values.apk || !values.sdk || !values.jdk) throw new Error('Se requieren --apk, --sdk y --jdk (JDK 17).');
  const apk = inspectApk(values.apk, values.sdk, values.jdk);
  const pubspec = readFileSync(join(root, 'pubspec.yaml'), 'utf8');
  const version = requiredMatch(pubspec, /^version:\s*(\S+)\s*$/m, 'versión de pubspec');
  const previous = values['previous-apk'] ? inspectApk(values['previous-apk'], values.sdk, values.jdk) : undefined;
  const problems = checkApk(apk, {
    version, previous, expectedCertificate: values['expected-certificate'],
    allowDebug: values['allow-debug'],
    deviceApi: values['device-api'] === undefined ? undefined : Number(values['device-api']),
    deviceAbis: values['device-abis']?.split(','),
  });
  console.log(JSON.stringify({ contractVersion: contract.contractVersion, purpose: 'technical-inspection-only', completeDelivery: false, apk, problems }, null, 2));
  if (problems.length) process.exitCode = 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(); } catch {
    // No imprimir stderr externo: puede contener rutas o identificadores privados.
    console.error('APK-CONTRACT: no se pudo inspeccionar. Revisa argumentos, APK firmado y SDK/JDK fijados. No se ha instalado ni borrado nada.');
    process.exitCode = 1;
  }
}
