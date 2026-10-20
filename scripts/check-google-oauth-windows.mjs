// Inventario local: no contacta Google ni acredita una sesión o un EXE final.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readApplicationId, validatePublicConfig } from './check-google-oauth.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const requireValue = (condition, message) => { if (!condition) throw new Error(message); };

// Conserva todas las validaciones globales, incluso las de Android. No cambia
// status para hacer pasar una plataforma pendiente ni exige completar Android.
export function validateWindowsOAuthConfig(config, applicationId) {
  validatePublicConfig(config, applicationId);
  requireValue(config.project.id !== null && config.project.number !== null,
    'Bloqueo externo Windows: falta acreditar el proyecto Google común.');
  requireValue(config.drive.apiEnabled && config.consent.testUserAdded,
    'Bloqueo externo Windows: falta habilitar Drive API o acreditar la cuenta tester.');
  requireValue(config.windows.clientId !== null,
    'Bloqueo externo Windows: falta el Client ID Desktop público.');
  return {
    platform: 'windows',
    configuration: 'declared',
    globalStatus: config.status,
    clientId: config.windows.clientId,
    completeDelivery: false,
    realDriveVerified: false,
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    requireValue(process.argv.length === 2, 'Argumento no permitido.');
    const config = JSON.parse(readFileSync(resolve(root, 'config/google-oauth.public.json'), 'utf8'));
    const applicationId = readApplicationId(readFileSync(resolve(root, 'android/app/build.gradle.kts'), 'utf8'));
    console.log(JSON.stringify(validateWindowsOAuthConfig(config, applicationId), null, 2));
  } catch (error) {
    // JSON/errores de E/S pueden contener datos privados: no reproducirlos.
    console.error(error instanceof SyntaxError || error?.code
      ? 'OAUTH-WINDOWS: no se pudo leer una configuración pública válida.'
      : `OAUTH-WINDOWS: ${error.message}`);
    process.exitCode = 1;
  }
}
