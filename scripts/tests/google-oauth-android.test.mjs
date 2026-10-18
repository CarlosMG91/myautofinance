import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { validatePublicConfig } from '../check-google-oauth.mjs';
import { inspectApk } from '../check-android-apk-contract.mjs';
import { loadAndroidOAuthConfiguration, validateAndroidOAuthApk, validateAndroidOAuthConfig,
  validateDistributionIdentity } from '../check-google-oauth-android.mjs';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const identity = JSON.parse(read('packaging/android/oauth-distribution.public.json'));
const pem = read('packaging/android/distribution-certificate.pem');
const packageId = identity.applicationId;
const manifest = JSON.parse(read('config/google-oauth.public.json'));
const hex = value => value.replaceAll(':', '').toLowerCase();

// Proyecto e IDs exclusivamente sintéticos; no se escriben al inventario real.
function androidOnly() {
  const config = structuredClone(manifest);
  config.status = 'blocked_external';
  config.project = { id: 'autofinance-synthetic', number: '123456789012' };
  config.consent.testUserAdded = true;
  config.drive.apiEnabled = true;
  config.windows.clientId = null;
  config.android.serverClientId = '123456789012-web.apps.googleusercontent.com';
  config.android.clients = [{
    clientId: '123456789012-android.apps.googleusercontent.com',
    certificateSha1: identity.certificateSha1,
    certificateSha256: identity.certificateSha256,
    builds: [{ source: 'distribution', apkSha256: identity.technicalApkSha256 }],
  }];
  return config;
}

function apk() {
  return {
    applicationId: packageId, splitName: null, versionName: '0.1.1', versionCode: 2,
    minimumSdk: 24, compileSdk: 36, targetSdk: 36,
    abis: ['arm64-v8a', 'armeabi-v7a', 'x86_64'],
    debuggable: false, debugCertificate: false,
    certificateSha1: hex(identity.certificateSha1),
    certificateSha256: hex(identity.certificateSha256), apkSha256: 'a'.repeat(64),
  };
}

test('la identidad pública coincide con el PEM independiente de T02', () => {
  assert.equal(validateDistributionIdentity(identity, pem, packageId), identity);
});

test('rechaza identidad modificada, campos sensibles y PEM privado/múltiple', () => {
  for (const alter of [x => x.version = 2, x => x.applicationId = 'com.example.other',
    x => x.certificateSha1 = Array(20).fill('AA').join(':'),
    x => x.certificateSha256 = Array(32).fill('BB').join(':'),
    x => x.technicalApkSha256 = 'invalid', x => x.private_key = 'SYNTHETIC_PRIVATE_VALUE']) {
    const copy = structuredClone(identity);
    alter(copy);
    assert.throws(() => validateDistributionIdentity(copy, pem, packageId),
      error => !error.message.includes('SYNTHETIC_PRIVATE_VALUE'));
  }
  for (const invalid of [pem + pem, '-----BEGIN PRIVATE KEY-----synthetic', 'invalid']) {
    assert.throws(() => validateDistributionIdentity(identity, invalid, packageId));
  }
});

test('Android completo pasa sin Windows y conserva el bloqueo global sin mutaciones', () => {
  const config = androidOnly();
  const before = structuredClone(config);
  const result = validateAndroidOAuthConfig(config, packageId, identity);
  assert.equal(result.serverClientId, config.android.serverClientId);
  assert.equal(result.globalStatus, 'blocked_external');
  assert.equal(result.completeDelivery, false);
  assert.equal(result.realDriveVerified, false);
  assert.deepEqual(config, before);
  assert.throws(() => validatePublicConfig(config, packageId, { requireConfigured: true }), /Bloqueo externo/);
  config.status = 'configured';
  assert.throws(() => validatePublicConfig(config, packageId), /Windows/);
});

test('rechaza proyecto, API, tester, Web o cliente de distribución pendientes', () => {
  for (const alter of [c => c.project.id = null, c => c.project.number = null,
    c => c.drive.apiEnabled = false, c => c.consent.testUserAdded = false,
    c => c.android.serverClientId = null, c => c.android.clients = []]) {
    const config = androidOnly();
    alter(config);
    assert.throws(() => validateAndroidOAuthConfig(config, packageId, identity));
  }
});

test('no acepta otro certificado, ni debug/CI como evidencia de distribución', () => {
  for (const alter of [c => c.certificateSha1 = Array(20).fill('AA').join(':'),
    c => c.certificateSha256 = Array(32).fill('BB').join(':'),
    c => c.builds[0].source = 'local-debug', c => c.builds[0].source = 'ci-debug',
    c => c.builds[0].apkSha256 = 'f'.repeat(64)]) {
    const config = androidOnly();
    alter(config.android.clients[0]);
    assert.throws(() => validateAndroidOAuthConfig(config, packageId, identity));
  }
});

test('conserva esquema cerrado, proyecto común y scope exacto del control global', () => {
  for (const alter of [c => c.android.serverClientId = '999999999999-web.apps.googleusercontent.com',
    c => c.android.applicationId = 'com.example.other',
    c => c.drive.scopes.push('openid'), c => c.drive.scopes.push('https://www.googleapis.com/auth/drive'),
    c => c.android.client_secret = 'SYNTHETIC_PRIVATE_VALUE']) {
    const config = androidOnly();
    alter(config);
    assert.throws(() => validateAndroidOAuthConfig(config, packageId, identity),
      error => !error.message.includes('SYNTHETIC_PRIVATE_VALUE'));
  }
});

test('un APK posterior del mismo certificado pasa sin exigir el hash del APK técnico', () => {
  assert.deepEqual(validateAndroidOAuthApk(apk(), identity), {
    apkSha256: 'a'.repeat(64), certificateMatched: true,
  });
});

test('el APK final con otra firma, paquete, debug, split o plataforma incompatible falla', () => {
  for (const alter of [a => a.applicationId = 'com.example.other',
    a => a.certificateSha1 = 'a'.repeat(40), a => a.certificateSha256 = 'b'.repeat(64),
    a => a.debuggable = true, a => a.debugCertificate = true, a => a.splitName = 'arm64',
    a => a.minimumSdk = 25, a => a.targetSdk = 37, a => a.abis = ['x86_64'],
    a => a.apkSha256 = 'invalid']) {
    const candidate = apk();
    alter(candidate);
    assert.throws(() => validateAndroidOAuthApk(candidate, identity));
  }
});

test('CLI rechaza argumentos incompletos sin imprimir valores privados de entrada', () => {
  for (const args of [['--apk', 'SYNTHETIC_PRIVATE_VALUE'],
    ['--apk', '', '--sdk', '', '--jdk', ''], ['--SYNTHETIC_PRIVATE_VALUE']]) {
    const result = spawnSync(process.execPath, ['scripts/check-google-oauth-android.mjs',
      ...args], { encoding: 'utf8' });
    assert.equal(result.status, 1);
    assert.doesNotMatch(result.stdout + result.stderr, /SYNTHETIC_PRIVATE_VALUE/);
  }
});

// Opt-in local de solo lectura: no firma, instala ni necesita Google.
test('contrasta huellas públicas contra el APK técnico real disponible', {
  skip: !process.env.AUTOFINANCE_T02_APK,
}, () => {
  const result = inspectApk(process.env.AUTOFINANCE_T02_APK,
    process.env.AUTOFINANCE_ANDROID_SDK, process.env.AUTOFINANCE_JDK17);
  assert.equal(result.apkSha256, identity.technicalApkSha256);
  assert.equal(validateAndroidOAuthApk(result, identity).certificateMatched, true);
});

test('inventario real pendiente no se sustituye por la fixture sintética', () => {
  if (manifest.android.serverClientId === null) {
    assert.throws(() => loadAndroidOAuthConfiguration(), /Bloqueo externo Android/);
  } else {
    assert.equal(loadAndroidOAuthConfiguration().configuration.serverClientId, manifest.android.serverClientId);
  }
});
