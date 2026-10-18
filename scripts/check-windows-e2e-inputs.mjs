import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { verifyDelivery } from './windows-delivery.mjs';
import { validateCandidate } from './windows-installer.mjs';
import { applicationVersion, sha256 } from './windows-payload.mjs';

const requireValue = (value, message) => { if (!value) throw new Error(message); };

// Read-only preparation on the build host. Never starts Setup, opens a database,
// reads Credential Manager, or certifies that these bytes have run on Windows.
export function inspectE2EInput(directory) {
  const delivery = verifyDelivery(directory);
  const bytes = name => readFileSync(resolve(directory, name));
  const json = name => JSON.parse(bytes(name));
  requireValue(/^\d+\.\d+\.\d+\+\d+$/.test(delivery.applicationVersion), 'Version de entrega no valida.');
  const version = applicationVersion(`version: ${delivery.applicationVersion}\n`);
  requireValue(delivery.applicationVersion === version.applicationVersion && delivery.windowsVersion === version.windowsVersion,
    'Versiones app/PE de entrega incoherentes.');
  const payload = json('payload-manifest.json'), build = json('installer-build.json'), quality = json('quality.json');
  // The payload inventory is declared metadata here; T06 verifies its real files
  // at build time. T08 must still compare installed files and actual PE resources.
  validateCandidate(payload, payload.payload, `version: ${version.applicationVersion}\n`, { commit: delivery.sourceCommit });
  requireValue(payload.applicationVersion === version.applicationVersion &&
    isDeepStrictEqual(delivery.toolchain, payload.toolchain), 'Payload de otra version/toolchain.');
  requireValue(delivery.verification.quality === 'passed' && delivery.verification.payload === 'passed' &&
    delivery.verification.installer === 'passed' && quality.status === 'passed' &&
    quality.command === 'scripts/check-quality.ps1' && quality.sourceCommit === delivery.sourceCommit &&
    quality.toolchainSha256 === payload.toolchain.toolchainSha256 && quality.lockfileSha256 === payload.toolchain.lockfileSha256,
  'Calidad ausente, fallida o de otras fuentes.');
  requireValue(build.installerBuildVersion === 1 && build.sourceDirty === false && build.sourceCommit === delivery.sourceCommit &&
    build.appId === payload.appId && build.applicationVersion === version.applicationVersion && build.windowsVersion === version.windowsVersion &&
    build.inputs?.payloadManifestSha256 === sha256(bytes('payload-manifest.json')), 'Build de instalador incoherente.');
  const name = `Autofinance-${version.applicationVersion}-windows-x64-private.exe`;
  const entry = delivery.files.find(file => file.path === name);
  requireValue(entry && build.installer?.path === name && build.installer.windowsVersion === version.windowsVersion &&
    build.installer.signing === 'NotSigned' && delivery.signing.status === 'unsigned' &&
    build.installer.size === entry.size && build.installer.sha256 === entry.sha256, 'Identidad/hash/firma de EXE incoherentes.');
  return { ...version, sourceCommit: delivery.sourceCommit, appId: payload.appId,
    deliveryManifestSha256: sha256(bytes('delivery-manifest.json')), installer: entry };
}

export function inspectE2EPair(previous, next) {
  const n = inspectE2EInput(previous), n1 = inspectE2EInput(next);
  const a = n.windowsVersion.split('.').map(Number), b = n1.windowsVersion.split('.').map(Number);
  const difference = b.map((value, i) => value - a[i]).find(value => value !== 0);
  requireValue(difference > 0, 'N+1 debe ser numericamente posterior a N; igualdad solo prueba reparacion.');
  requireValue(n.appId === n1.appId && n.sourceCommit !== n1.sourceCommit, 'Se requieren AppId estable y commits declarados distintos.');
  return { status: 'inputsConsistent', e2e: 'notExecuted', previous: n, next: n1,
    limitation: 'Solo integridad/coherencia de entradas; no acredita procedencia, recursos PE, instalacion, OAuth ni aceptacion Windows.' };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    requireValue(process.argv.length === 4, 'Uso: node scripts/check-windows-e2e-inputs.mjs entrega-N entrega-N+1');
    console.log(JSON.stringify(inspectE2EPair(...process.argv.slice(2)), null, 2));
  } catch (error) {
    console.error(error.code || error instanceof SyntaxError
      ? 'Entradas E2E ausentes o ilegibles; no se ha ejecutado ningun instalador.' : error.message);
    process.exitCode = 1;
  }
}
