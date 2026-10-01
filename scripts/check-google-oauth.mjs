import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const scope = 'https://www.googleapis.com/auth/drive.file';
const clientIdPattern = /^([0-9]+)-[a-z0-9]+\.apps\.googleusercontent\.com$/;

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

function keys(value, expected, context) {
  requireValue(value !== null && typeof value === 'object' && !Array.isArray(value),
    `${context}: objeto obligatorio.`);
  const actual = Object.keys(value).sort();
  requireValue(JSON.stringify(actual) === JSON.stringify([...expected].sort()),
    `${context}: campos no permitidos o ausentes; solo se admiten ajustes públicos.`);
}

function nullablePattern(value, pattern, context) {
  requireValue(value === null || (typeof value === 'string' && pattern.test(value)),
    `${context}: formato no válido.`);
}

// No red, autenticación ni impresión de valores de entrada, incluso al fallar.
// Este inventario declara configuración: no prueba que Google la haya aplicado.
export function validatePublicConfig(config, applicationId, { requireConfigured = false } = {}) {
  keys(config, ['version', 'status', 'project', 'consent', 'drive', 'android', 'windows'], 'Configuración');
  requireValue(config.version === 1, 'Versión de contrato no válida.');
  requireValue(['blocked_external', 'configured'].includes(config.status), 'Estado no válido.');
  keys(config.project, ['id', 'number'], 'Proyecto');
  nullablePattern(config.project.id, /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/, 'ID de proyecto');
  nullablePattern(config.project.number, /^[1-9][0-9]*$/, 'Número de proyecto');

  keys(config.consent, ['appName', 'audience', 'publishingStatus', 'testUserAdded'], 'Consentimiento');
  requireValue(config.consent.appName === 'Autofinance', 'Nombre de aplicación no válido.');
  requireValue(config.consent.audience === 'external', 'La cuenta personal requiere audiencia external.');
  requireValue(config.consent.publishingStatus === 'testing', 'Este contrato prepara el modo testing.');
  requireValue(typeof config.consent.testUserAdded === 'boolean', 'Indicador de usuario de prueba no válido.');

  keys(config.drive, ['apiEnabled', 'scopes'], 'Drive');
  requireValue(typeof config.drive.apiEnabled === 'boolean', 'Indicador de Drive API no válido.');
  requireValue(Array.isArray(config.drive.scopes) && config.drive.scopes.length === 1
    && config.drive.scopes[0] === scope, 'Solo se permite el scope drive.file.');

  keys(config.android, ['applicationId', 'clients'], 'Android');
  requireValue(config.android.applicationId === applicationId, 'El paquete OAuth no coincide con applicationId de Gradle.');
  requireValue(Array.isArray(config.android.clients), 'La lista de clientes Android no es válida.');
  const ids = new Set();
  const certificates = new Set();
  const builds = new Set();
  function validateClientId(value) {
    requireValue(typeof value === 'string' && clientIdPattern.test(value), 'Client ID no válido.');
    requireValue(config.project.number !== null
      && clientIdPattern.exec(value)[1] === config.project.number, 'El cliente debe corresponder al número del proyecto común.');
    requireValue(!ids.has(value), 'Client ID duplicado.');
    ids.add(value);
  }
  for (const client of config.android.clients) {
    keys(client, ['clientId', 'certificateSha1', 'certificateSha256', 'builds'], 'Cliente Android');
    validateClientId(client.clientId);
    requireValue(typeof client.certificateSha1 === 'string'
      && /^(?:[A-F0-9]{2}:){19}[A-F0-9]{2}$/.test(client.certificateSha1), 'SHA-1 de certificado no válida.');
    requireValue(typeof client.certificateSha256 === 'string'
      && /^(?:[A-F0-9]{2}:){31}[A-F0-9]{2}$/.test(client.certificateSha256), 'SHA-256 de certificado no válida.');
    requireValue(!certificates.has(client.certificateSha1), 'Certificado duplicado: reutilizar su cliente.');
    certificates.add(client.certificateSha1);
    requireValue(Array.isArray(client.builds) && client.builds.length > 0, 'Falta evidencia del APK que usa el certificado.');
    for (const build of client.builds) {
      keys(build, ['source', 'apkSha256'], 'Build Android');
      requireValue(['local-debug', 'local-release-debug-key', 'ci-debug', 'distribution'].includes(build.source),
        'Origen de build no válido.');
      requireValue(typeof build.apkSha256 === 'string' && /^[a-f0-9]{64}$/.test(build.apkSha256),
        'SHA-256 del APK no válida.');
      requireValue(!builds.has(build.apkSha256), 'Evidencia de APK duplicada.');
      builds.add(build.apkSha256);
    }
  }
  keys(config.windows, ['type', 'clientId'], 'Windows');
  requireValue(config.windows.type === 'desktop', 'Windows requiere un cliente desktop.');
  if (config.windows.clientId !== null) validateClientId(config.windows.clientId);

  if (requireConfigured || config.status === 'configured') {
    requireValue(config.status === 'configured', 'Bloqueo externo: proyecto y clientes OAuth pendientes.');
    requireValue(config.project.id !== null && config.project.number !== null,
      'Falta el proyecto Google común.');
    requireValue(config.drive.apiEnabled && config.consent.testUserAdded,
      'Falta habilitar Drive API o añadir el usuario de prueba en Google.');
    requireValue(config.android.clients.length > 0 && config.windows.clientId !== null,
      'Faltan los clientes Android y Windows.');
  }
  return config.status;
}

export function readApplicationId(gradle) {
  // Fallar ante flavors, sufijos o expresiones: requieren revisar el contrato.
  requireValue(!/applicationIdSuffix|productFlavors/.test(gradle), 'Revisar paquete OAuth: Gradle declara variantes.');
  const matches = [...gradle.matchAll(/^\s*applicationId\s*=\s*"([a-zA-Z0-9_.]+)"\s*$/gm)];
  requireValue(matches.length === 1, 'No se pudo determinar un único applicationId literal.');
  return matches[0][1];
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    requireValue(process.argv.slice(2).every(arg => arg === '--require-configured'), 'Argumento no permitido.');
    const config = JSON.parse(readFileSync(resolve(root, 'config/google-oauth.public.json'), 'utf8'));
    const applicationId = readApplicationId(readFileSync(resolve(root, 'android/app/build.gradle.kts'), 'utf8'));
    const status = validatePublicConfig(config, applicationId, {
      requireConfigured: process.argv.includes('--require-configured'),
    });
    console.log(status === 'configured'
      ? 'Contrato público válido; configuración declarada. La comprobación en Google sigue siendo manual.'
      : 'Contrato público válido. BLOQUEO EXTERNO: OAuth aún no está configurado en Google.');
  } catch (error) {
    // JSON.parse y errores de E/S pueden contener datos privados: no reproducirlos.
    console.error(error instanceof SyntaxError || error?.code
      ? 'No se pudo leer una configuración pública válida.' : error.message);
    process.exitCode = 1;
  }
}
