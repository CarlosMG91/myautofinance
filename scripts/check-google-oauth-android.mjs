// Control local de configuración declarada; nunca autentica ni acredita Drive real.
import { X509Certificate } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { readApplicationId, validatePublicConfig } from './check-google-oauth.mjs';
import { checkApk, contract, inspectApk } from './check-android-apk-contract.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const hex = value => value.replaceAll(':', '').toLowerCase();
function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

export function validateDistributionIdentity(identity, pem, applicationId) {
  requireValue(identity !== null && typeof identity === 'object'
    && JSON.stringify(Object.keys(identity).sort()) === JSON.stringify([
      'applicationId', 'certificateSha1', 'certificateSha256', 'technicalApkSha256', 'version',
    ]), 'Identidad pública: campos no permitidos o ausentes.');
  requireValue(identity.version === 1 && identity.applicationId === applicationId
    && applicationId === contract.applicationId, 'Identidad de distribución incompatible con el paquete.');
  requireValue(/^(?:[A-F0-9]{2}:){19}[A-F0-9]{2}$/.test(identity.certificateSha1)
    && /^(?:[A-F0-9]{2}:){31}[A-F0-9]{2}$/.test(identity.certificateSha256)
    && /^[a-f0-9]{64}$/.test(identity.technicalApkSha256), 'Huellas públicas de distribución no válidas.');
  requireValue(typeof pem === 'string' && /^-----BEGIN CERTIFICATE-----[\s\S]+-----END CERTIFICATE-----\s*$/.test(pem.trim())
    && !pem.includes('PRIVATE KEY') && (pem.match(/BEGIN CERTIFICATE/g) ?? []).length === 1,
  'Se requiere un único certificado público PEM.');
  const certificate = new X509Certificate(pem);
  requireValue(identity.certificateSha1 === certificate.fingerprint
    && identity.certificateSha256 === certificate.fingerprint256,
  'La identidad OAuth no coincide con el certificado público de T02.');
  return identity;
}

// No depende de Windows ni cambia status. El comprobador global conserva su contrato.
// identity debe proceder de validateDistributionIdentity, no del certificado del APK candidato.
export function validateAndroidOAuthConfig(config, applicationId, identity) {
  validatePublicConfig(config, applicationId);
  requireValue(identity.applicationId === applicationId, 'Paquete de distribución distinto.');
  requireValue(config.project.id !== null && config.project.number !== null,
    'Bloqueo externo Android: falta acreditar el proyecto Google común.');
  requireValue(config.drive.apiEnabled && config.consent.testUserAdded,
    'Bloqueo externo Android: falta habilitar Drive API o acreditar la cuenta tester.');
  requireValue(config.android.serverClientId !== null,
    'Bloqueo externo Android: falta el Client ID Web público (serverClientId).');
  requireValue(!config.android.clients.some(client => client.builds.some(build => build.source === 'ci-debug')),
    'Distribución privada: no autorizar certificados debug genéricos de CI.');
  const client = config.android.clients.find(candidate => candidate.certificateSha1 === identity.certificateSha1
    && candidate.certificateSha256 === identity.certificateSha256);
  requireValue(client, 'Bloqueo externo Android: falta el cliente del certificado exacto de distribución T02.');
  requireValue(client.builds.some(build => build.source === 'distribution'
    && build.apkSha256 === identity.technicalApkSha256), 'Falta la evidencia del APK técnico T02 en el cliente de distribución.');
  // Solo valores públicos y afirmaciones locales. No confundir este resultado con T09.
  return {
    platform: 'android',
    configuration: 'declared',
    globalStatus: config.status,
    applicationId,
    serverClientId: config.android.serverClientId,
    androidClientId: client.clientId,
    certificateSha1: identity.certificateSha1,
    certificateSha256: identity.certificateSha256,
    completeDelivery: false,
    realDriveVerified: false,
  };
}

export function validateAndroidOAuthApk(apk, identity) {
  const problems = checkApk(apk, { expectedCertificate: hex(identity.certificateSha256) });
  requireValue(problems.length === 0, 'El APK no satisface el contrato de distribución o su certificado es distinto.');
  requireValue(apk.applicationId === identity.applicationId && apk.certificateSha1 === hex(identity.certificateSha1),
    'El APK no coincide con la identidad OAuth de distribución.');
  requireValue(/^[a-f0-9]{64}$/.test(apk.apkSha256), 'Falta el hash del APK inspeccionado.');
  return { apkSha256: apk.apkSha256, certificateMatched: true };
}

export function loadAndroidOAuthConfiguration() {
  const read = path => readFileSync(resolve(root, path), 'utf8');
  const applicationId = readApplicationId(read('android/app/build.gradle.kts'));
  const identity = validateDistributionIdentity(JSON.parse(read('packaging/android/oauth-distribution.public.json')),
    read('packaging/android/distribution-certificate.pem'), applicationId);
  const config = JSON.parse(read('config/google-oauth.public.json'));
  return { configuration: validateAndroidOAuthConfig(config, applicationId, identity), identity };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const { values } = parseArgs({ options: {
      apk: { type: 'string' }, sdk: { type: 'string' }, jdk: { type: 'string' },
    } });
    const inspectionRequested = Object.keys(values).length > 0;
    requireValue(!inspectionRequested || [values.apk, values.sdk, values.jdk]
      .every(value => typeof value === 'string' && value.trim().length > 0),
      'La inspección requiere --apk, --sdk y --jdk conjuntamente.');
    const { configuration, identity } = loadAndroidOAuthConfiguration();
    const inspection = values.apk ? validateAndroidOAuthApk(inspectApk(values.apk, values.sdk, values.jdk), identity) : null;
    console.log(JSON.stringify({ ...configuration, inspection }, null, 2));
  } catch (error) {
    // No reproducir JSON, rutas, stderr externo o argumentos arbitrarios.
    console.error(error instanceof SyntaxError || error?.code || error?.opensslErrorStack
      ? 'OAUTH-ANDROID: no se pudo leer una configuración pública o inspeccionar el APK.'
      : `OAUTH-ANDROID: ${error.message}`);
    process.exitCode = 1;
  }
}
