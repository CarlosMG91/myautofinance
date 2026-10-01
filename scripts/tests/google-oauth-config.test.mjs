import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { readApplicationId, validatePublicConfig } from '../check-google-oauth.mjs';

const packageId = 'com.carlosmg91.myautofinance';
const manifest = JSON.parse(readFileSync(new URL('../../config/google-oauth.public.json', import.meta.url), 'utf8'));
const clone = () => structuredClone(manifest);

// Identificadores y huellas sintéticos; nunca se usan para autorizar con Google.
function configured() {
  const config = clone();
  config.status = 'configured';
  config.project = { id: 'autofinance-synthetic', number: '123456789012' };
  config.consent.testUserAdded = true;
  config.drive.apiEnabled = true;
  config.windows.clientId = '123456789012-windows.apps.googleusercontent.com';
  config.android.clients = [{
    clientId: '123456789012-android.apps.googleusercontent.com',
    certificateSha1: Array(20).fill('AA').join(':'),
    certificateSha256: Array(32).fill('BB').join(':'),
    builds: [{ source: 'local-debug', apkSha256: 'c'.repeat(64) }],
  }];
  return config;
}

test('el inventario del repositorio respeta el paquete real de Gradle', () => {
  const gradle = readFileSync(new URL('../../android/app/build.gradle.kts', import.meta.url), 'utf8');
  assert.equal(validatePublicConfig(manifest, readApplicationId(gradle)), manifest.status);
});

test('el bloqueo externo nunca satisface el control de configuración completada', () => {
  const config = clone();
  config.status = 'blocked_external';
  assert.throws(() => validatePublicConfig(config, packageId, { requireConfigured: true }), /Bloqueo externo/);
});

test('un inventario completo de un proyecto común pasa el control estricto', () => {
  assert.equal(validatePublicConfig(configured(), packageId, { requireConfigured: true }), 'configured');
});

for (const forbidden of ['drive', 'drive.readonly', 'drive.metadata.readonly', 'drive.appdata', 'drive.appfolder']) {
  test(`rechaza permisos fuera del contrato: ${forbidden}`, () => {
    const config = clone();
    config.drive.scopes.push(`https://www.googleapis.com/auth/${forbidden}`);
    assert.throws(() => validatePublicConfig(config, packageId), /Solo se permite/);
  });
}

test('rechaza scopes de identidad innecesarios y drive.file duplicado', () => {
  for (const extra of ['openid', 'email', 'profile', manifest.drive.scopes[0]]) {
    const config = clone();
    config.drive.scopes.push(extra);
    assert.throws(() => validatePublicConfig(config, packageId), /Solo se permite/);
  }
});

test('rechaza secretos, tokens, cuentas y configuraciones crudas sin imprimir su contenido', () => {
  for (const key of ['client_secret', 'access_token', 'refresh_token', 'private_key', 'testUsers', 'installed', 'serviceAccount']) {
    for (const context of ['root', 'project', 'consent', 'drive', 'android', 'windows', 'client', 'build']) {
      const config = configured();
      const target = context === 'root' ? config
        : context === 'client' ? config.android.clients[0]
          : context === 'build' ? config.android.clients[0].builds[0] : config[context];
      target[key] = 'SYNTHETIC_PRIVATE_VALUE';
      assert.throws(() => validatePublicConfig(config, packageId), error =>
        /campos no permitidos/.test(error.message) && !error.message.includes('SYNTHETIC_PRIVATE_VALUE'));
    }
  }
});

test('rechaza clientes de proyectos distintos o duplicados', () => {
  const config = configured();
  config.windows.clientId = '999999999999-windows.apps.googleusercontent.com';
  assert.throws(() => validatePublicConfig(config, packageId), /proyecto común/);
  config.windows.clientId = config.android.clients[0].clientId;
  assert.throws(() => validatePublicConfig(config, packageId), /duplicado/);
});

test('rechaza configuración incompleta declarada como configurada', () => {
  for (const alter of [c => c.project.id = null, c => c.drive.apiEnabled = false,
    c => c.consent.testUserAdded = false, c => c.android.clients = [], c => c.windows.clientId = null]) {
    const config = configured();
    alter(config);
    assert.throws(() => validatePublicConfig(config, packageId));
  }
});

test('rechaza huellas inválidas y evidencia de APK ausente', () => {
  for (const alter of [c => c.certificateSha1 = 'AA', c => c.certificateSha256 = 'BB',
    c => c.builds = [], c => c.builds[0].apkSha256 = 'CC', c => c.builds[0].source = 'unknown']) {
    const config = configured();
    alter(config.android.clients[0]);
    assert.throws(() => validatePublicConfig(config, packageId));
  }
});

test('rechaza un paquete distinto y variantes Gradle sin revisar', () => {
  assert.throws(() => validatePublicConfig(clone(), 'com.example.other'), /paquete OAuth/);
  assert.throws(() => readApplicationId('applicationIdSuffix = ".debug"'), /variantes/);
  assert.throws(() => readApplicationId('applicationId = dynamicValue'), /applicationId/);
});
