import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { validatePublicConfig } from '../check-google-oauth.mjs';
import { validateWindowsOAuthConfig } from '../check-google-oauth-windows.mjs';

const packageId = 'com.carlosmg91.myautofinance';
// Configuración ficticia exclusiva de pruebas; nunca se envía a Google.
function windowsOnly() {
  return {
    version: 1, status: 'blocked_external',
    project: { id: 'autofinance-synthetic', number: '123456789012' },
    consent: { appName: 'Autofinance', audience: 'external', publishingStatus: 'testing', testUserAdded: true },
    drive: { apiEnabled: true, scopes: ['https://www.googleapis.com/auth/drive.file'] },
    android: { applicationId: packageId, serverClientId: null, clients: [] },
    windows: { type: 'desktop', clientId: '123456789012-windows.apps.googleusercontent.com' },
  };
}

test('Windows declarado con Android pendiente no muta ni satisface el control global', () => {
  const config = windowsOnly(), before = structuredClone(config);
  const result = validateWindowsOAuthConfig(config, packageId);
  assert.equal(result.configuration, 'declared');
  assert.equal(result.globalStatus, 'blocked_external');
  assert.equal(result.realDriveVerified, false);
  assert.equal(result.completeDelivery, false);
  assert.deepEqual(config, before);
  assert.throws(() => validatePublicConfig(config, packageId, { requireConfigured: true }));
});

test('no oculta el falso configured global si Android está pendiente', () => {
  const config = windowsOnly();
  config.status = 'configured';
  assert.throws(() => validateWindowsOAuthConfig(config, packageId), /Faltan los clientes/);
});

test('exige proyecto, Drive API, tester y cliente Windows', () => {
  for (const alter of [c => c.project.id = null, c => c.project.number = null,
    c => c.drive.apiEnabled = false, c => c.consent.testUserAdded = false,
    c => c.windows.clientId = null]) {
    const config = windowsOnly();
    alter(config);
    assert.throws(() => validateWindowsOAuthConfig(config, packageId));
  }
});

test('mantiene tipo Desktop, proyecto común, scope exacto y paquete Android', () => {
  for (const alter of [c => c.windows.type = 'web',
    c => c.windows.clientId = '999999999999-other.apps.googleusercontent.com',
    c => c.drive.scopes.push('openid'), c => c.drive.scopes = [],
    c => c.android.applicationId = 'com.example.other',
    c => c.android.serverClientId = c.windows.clientId]) {
    const config = windowsOnly();
    alter(config);
    assert.throws(() => validateWindowsOAuthConfig(config, packageId));
  }
});

test('mantiene la validación de los campos Android presentes', () => {
  const config = windowsOnly();
  config.android.serverClientId = '999999999999-web.apps.googleusercontent.com';
  assert.throws(() => validateWindowsOAuthConfig(config, packageId), /proyecto común/);
});

test('el contrato cerrado rechaza secretos sin reflejarlos', () => {
  for (const section of ['windows', 'project', 'consent']) {
    const config = windowsOnly();
    const sensitive = 'synthetic-sensitive-value';
    config[section].client_secret = sensitive;
    assert.throws(() => validateWindowsOAuthConfig(config, packageId), error =>
      /campos no permitidos/.test(error.message) && !error.message.includes(sensitive));
  }
});

test('CLI refleja solo declaración o bloqueo del inventario vigente', () => {
  const config = JSON.parse(readFileSync(new URL('../../config/google-oauth.public.json', import.meta.url), 'utf8'));
  let declared = false;
  try { validateWindowsOAuthConfig(config, packageId); declared = true; } catch { /* bloqueo esperado */ }
  const run = spawnSync(process.execPath, ['scripts/check-google-oauth-windows.mjs'], {
    cwd: new URL('../../', import.meta.url), encoding: 'utf8',
  });
  assert.equal(run.status, declared ? 0 : 1);
  if (declared) assert.equal(JSON.parse(run.stdout).realDriveVerified, false);
  else assert.match(run.stderr, /OAUTH-WINDOWS:/);
});

test('CLI no refleja argumentos desconocidos', () => {
  const sensitive = 'synthetic-sensitive-argument';
  const run = spawnSync(process.execPath, ['scripts/check-google-oauth-windows.mjs', sensitive], {
    cwd: new URL('../../', import.meta.url), encoding: 'utf8',
  });
  assert.equal(run.status, 1);
  assert.match(run.stderr, /Argumento no permitido/);
  assert.equal((run.stdout + run.stderr).includes(sensitive), false);
});
