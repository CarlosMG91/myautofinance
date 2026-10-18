import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { checkApk, contract, parseApk } from '../check-android-apk-contract.mjs';

// Salida sintética, nunca certificado/artefacto de distribución.
const fingerprint = 'ab'.repeat(32);
const badging = `package: name='com.carlosmg91.myautofinance' versionCode='2' versionName='0.1.0' compileSdkVersion='36'
minSdkVersion:'24'
targetSdkVersion:'36'
native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'`;
const certificates = `Signer #1 certificate DN: CN=Synthetic fixture
Signer #1 certificate SHA-256 digest: ${fingerprint}
Signer #1 certificate SHA-1 digest: ${'cd'.repeat(20)}`;
const candidate = () => parseApk(badging, certificates);
const options = { version: '0.1.0+2', expectedCertificate: fingerprint };

test('lee valores efectivos, certificado y ABI ARMv7 sin confundir hash de archivo', () => {
  const apk = candidate();
  assert.equal(apk.minimumSdk, 24);
  assert.deepEqual(apk.abis, ['arm64-v8a', 'armeabi-v7a', 'x86_64']);
  assert.equal(apk.apkSha256, undefined);
  assert.deepEqual(checkApk(apk, options), []);
  assert.equal(parseApk(badging.replace('minSdkVersion', 'sdkVersion'), certificates).minimumSdk, 24);
});
test('falla si falta evidencia de manifiesto o certificado o hay varios firmantes', () => {
  assert.throws(() => parseApk(badging.replace(" compileSdkVersion='36'", ''), certificates));
  assert.throws(() => parseApk(badging, ''));
  assert.throws(() => parseApk(badging, `${certificates}\nSigner #2 certificate SHA-256 digest: ${fingerprint}`));
});
test('no acepta debug como distribución, incluso release no debuggable firmado debug', () => {
  const debug = parseApk(`${badging}\napplication-debuggable`, certificates.replace('CN=Synthetic fixture', 'CN=Android Debug'));
  assert.equal(checkApk(debug, options).length, 2);
  debug.debuggable = false;
  assert.equal(checkApk(debug, options).length, 1);
  assert.deepEqual(checkApk(debug, { allowDebug: true }), []);
});
test('exige huella independiente y rechaza certificado distinto', () => {
  assert.match(checkApk(candidate())[0], /falta certificado/);
  assert.match(checkApk(candidate(), { expectedCertificate: 'ef'.repeat(32) })[0], /certificado/);
});
test('N a N+1 exige paquete y firma iguales y código creciente numérico', () => {
  const apk = candidate();
  assert.deepEqual(checkApk(apk, { ...options, previous: { ...apk, versionCode: 1 } }), []);
  for (const code of [2, 3, 10]) assert.match(checkApk(apk, { ...options, previous: { ...apk, versionCode: code } }).join(), /no creciente/);
  const previous = { ...apk, applicationId: 'other.package', certificateSha256: 'ef'.repeat(32), versionCode: 1 };
  assert.equal(checkApk(apk, { ...options, previous }).length, 2);
});
test('rechaza SDK cambiado, APK parcial y dispositivo incompatible sin instalar', () => {
  for (const key of ['minimumSdk', 'compileSdk', 'targetSdk']) assert.ok(checkApk({ ...candidate(), [key]: 37 }, options).some(x => x.includes(key)));
  assert.match(checkApk({ ...candidate(), abis: ['arm64-v8a'] }, options).join(), /universal/);
  assert.match(checkApk(candidate(), { ...options, deviceApi: 23, deviceAbis: ['x86'] }).join(), /API.*ABI/);
  assert.deepEqual(checkApk(candidate(), { ...options, deviceApi: 24, deviceAbis: ['arm64-v8a'] }), []);
});
test('rechaza un split aunque anuncie las ABI requeridas y tenga firma válida', () => {
  const split = parseApk(badging.replace(" versionCode=", " split='config.synthetic' versionCode="), certificates);
  assert.equal(split.splitName, 'config.synthetic');
  assert.match(checkApk(split, options).join(), /APK dividido/);
  assert.equal(candidate().splitName, null);
});
test('no admite override de versión, código inválido ni contador reiniciado', () => {
  for (const version of ['0.1.0+1', '0.2.0+2', '0.1.0-beta+2']) assert.match(checkApk(candidate(), { ...options, version }).join(), /pubspec/);
  for (const versionCode of [0, -1, 1.5, 2100000001]) assert.match(checkApk({ ...candidate(), versionCode }, options).join(), /fuera de rango/);
  const previous = { ...candidate(), versionCode: 9 };
  assert.match(checkApk({ ...candidate(), versionName: '0.2.0', versionCode: 1 }, { expectedCertificate: fingerprint, previous }).join(), /no creciente/);
});
test('contrato coincide con toolchain, identidad y delegación Gradle existentes', () => {
  const toolchain = JSON.parse(readFileSync(new URL('../../toolchain.json', import.meta.url)));
  const gradle = readFileSync(new URL('../../android/app/build.gradle.kts', import.meta.url), 'utf8');
  assert.equal(String(contract.compileSdk), toolchain.androidPlatform);
  assert.equal(contract.ndk, toolchain.androidNdk);
  assert.ok(gradle.includes(`applicationId = "${contract.applicationId}"`));
  assert.ok(gradle.includes('versionCode = flutter.versionCode'));
  assert.ok(gradle.includes('versionName = flutter.versionName'));
  assert.equal(contract.delivery.publicArtifacts, false);
});
