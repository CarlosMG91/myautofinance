// Local private packaging checks. No installation, network, or publication.
import { execFileSync } from 'node:child_process';
import { createHash, X509Certificate } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, unlinkSync, rmdirSync, copyFileSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { inflateRawSync } from 'node:zlib';
import { parseArgs } from 'node:util';
import { loadAndroidOAuthConfiguration } from './check-google-oauth-android.mjs';
import { checkApk, inspectApk, contract } from './check-android-apk-contract.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const read = path => readFileSync(join(root, path));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const requireValue = (value, message) => { if (!value) throw new Error(message); };
const run = (file, args) => execFileSync(file, args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
const hex = value => value.replaceAll(':', '').toLowerCase();

export function deliveryPlan(fixture = false, env = process.env) {
  const productionCert = hex(new X509Certificate(read('packaging/android/distribution-certificate.pem')).fingerprint256);
  if (fixture) {
    requireValue(env.AUTOFINANCE_SIGNING_FIXTURE === '1'
      && /^[a-f0-9]{64}$/.test(env.AUTOFINANCE_SIGNING_FIXTURE_SHA256 ?? '')
      && env.AUTOFINANCE_SIGNING_FIXTURE_SHA256 !== productionCert,
    'FIXTURE: se requiere certificado efímero independiente de distribución.');
    return { appEnvironment: 'test', purpose: 'ci-ephemeral-fixture', expectedCertificate: env.AUTOFINANCE_SIGNING_FIXTURE_SHA256,
      serverClientId: null, completeDelivery: false, realDriveVerified: false };
  }
  requireValue(!env.CI && !env.AUTOFINANCE_SIGNING_FIXTURE, 'PRIVATE_ONLY: producción exclusivamente local sin firma fixture.');
  const { configuration } = loadAndroidOAuthConfiguration();
  return { appEnvironment: 'production', purpose: 'private-candidate-pending-T09',
    expectedCertificate: productionCert, serverClientId: configuration.serverClientId,
    androidOAuth: configuration, completeDelivery: false, realDriveVerified: false };
}

export function inputSnapshot() {
  // Includes untracked source files and concurrent edits; never includes their contents in the report.
  const paths = run('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard', '--',
    'lib', 'assets', 'android', 'scripts', 'packaging/android', 'config/google-oauth.public.json',
    'pubspec.yaml', 'pubspec.lock', 'toolchain.json']).split('\0').filter(Boolean).sort();
  const hashes = paths.map(path => [path, sha(read(path))]);
  return { commit: run('git', ['rev-parse', 'HEAD']).trim(),
    dirty: Boolean(run('git', ['status', '--porcelain', '--untracked-files=normal']).trim()),
    sourceSha256: sha(JSON.stringify(hashes)), lockfileSha256: sha(read('pubspec.lock')),
    oauthConfigSha256: sha(read('config/google-oauth.public.json')),
    toolchain: JSON.parse(read('toolchain.json')),
    version: read('pubspec.yaml').toString().match(/^version:\s*(\S+)/m)?.[1] };
}

// Read central-directory entries rather than trusting names from an external listing.
export function zipEntries(bytes) {
  let end = bytes.length - 22;
  while (end >= Math.max(0, bytes.length - 65557) && bytes.readUInt32LE(end) !== 0x06054b50) end--;
  requireValue(end >= 0 && bytes.readUInt32LE(end) === 0x06054b50, 'ZIP: directorio ausente.');
  let position = bytes.readUInt32LE(end + 16);
  const entries = new Map();
  for (let n = 0; n < bytes.readUInt16LE(end + 10); n++) {
    requireValue(bytes.readUInt32LE(position) === 0x02014b50, 'ZIP: entrada inválida.');
    const method = bytes.readUInt16LE(position + 10);
    const size = bytes.readUInt32LE(position + 20);
    const nameLength = bytes.readUInt16LE(position + 28);
    const name = bytes.subarray(position + 46, position + 46 + nameLength).toString('utf8');
    const local = bytes.readUInt32LE(position + 42);
    requireValue(!entries.has(name) && !name.includes('..') && !name.startsWith('/'), 'ZIP: nombre duplicado o inseguro.');
    requireValue(bytes.readUInt32LE(local) === 0x04034b50, 'ZIP: cabecera local inválida.');
    const start = local + 30 + bytes.readUInt16LE(local + 26) + bytes.readUInt16LE(local + 28);
    const compressed = bytes.subarray(start, start + size);
    entries.set(name, { method, start, data: () => {
      requireValue(method === 0 || method === 8, 'ZIP: compresión no admitida.');
      return method === 0 ? compressed : inflateRawSync(compressed);
    } });
    position += 46 + nameLength + bytes.readUInt16LE(position + 30) + bytes.readUInt16LE(position + 32);
  }
  return entries;
}

export function loadAlignments(output) {
  const loads = [...output.matchAll(/^\s*LOAD\s+.*\balign 2\*\*(\d+)/gm)].map(match => Number(match[1]));
  requireValue(loads.length > 0, 'ELF: no se acreditan segmentos LOAD.');
  return loads;
}

export function assert16KB(name, alignments) {
  const required = /^lib\/(arm64-v8a|x86_64)\//.test(name);
  requireValue(!required || alignments.every(power => power >= 14), `ELF_16KB: biblioteca incompatible ${name}; no se entrega.`);
}

export function relroAlignment(output) {
  requireValue(/^\s*Type\s+Offset\s+VirtAddr/m.test(output), 'ELF: no se acreditan program headers.');
  const segments = [...output.matchAll(/^\s*(LOAD|GNU_RELRO)\s+(0x[\da-f]+)\s+(0x[\da-f]+)\s+(0x[\da-f]+)\s+(0x[\da-f]+)\s+(0x[\da-f]+)\s+([RWE ]+)\s+0x[\da-f]+/gim)]
    .map(match => ({ type: match[1], start: BigInt(match[3]), size: BigInt(match[6]), writable: match[7].includes('W') }));
  return segments.filter(segment => segment.type === 'GNU_RELRO').map(relro => {
    const end = relro.start + relro.size;
    if (end % 16384n === 0n) return true;
    // Android also permits a RELRO segment occupying its own complete LOAD.
    // Rounding protection into the unmapped gap cannot cover a writable tail.
    const wholeLoad = segments.some(load => load.type === 'LOAD' && load.start === relro.start && load.size === relro.size);
    const protectedEnd = ((end + 16383n) / 16384n) * 16384n;
    const writableTail = segments.some(load => load.type === 'LOAD' && load.writable
      && load.start < protectedEnd && load.start + load.size > end);
    return wholeLoad && !writableTail;
  });
}

export function checkPayload(entries, abis) {
  for (const name of ['AndroidManifest.xml', 'resources.arsc', 'assets/flutter_assets/FontManifest.json',
    'assets/flutter_assets/assets/fonts/roboto-regular.ttf', 'assets/flutter_assets/assets/fonts/roboto-medium.ttf',
    'assets/flutter_assets/assets/fonts/roboto-bold.ttf']) {
    requireValue(entries.has(name) && entries.get(name).data().length > 0, `PAYLOAD: falta ${name}.`);
  }
  const dex = [...entries].filter(([name]) => /^classes\d*\.dex$/.test(name));
  requireValue(dex.length > 0, 'PAYLOAD: faltan clases Android/plugins.');
  // MainActivity is stable; plugin implementation names may be obfuscated by R8.
  requireValue(dex.some(([, entry]) => entry.data().includes(Buffer.from('com/carlosmg91/myautofinance/MainActivity'))), 'PAYLOAD: falta MainActivity.');
  requireValue(dex.some(([, entry]) => entry.data().includes(Buffer.from('dev.flutter.pigeon.google_sign_in_android'))), 'PAYLOAD: falta canal nativo Google Sign-In.');
  for (const abi of abis) {
    for (const library of ['libapp.so', 'libflutter.so', 'libsqlite3.so', 'libdartjni.so']) {
      requireValue(entries.has(`lib/${abi}/${library}`), `PAYLOAD: falta ${library} en ${abi}.`);
    }
  }
}

export function verifyDelivery({ apk, sdk, jdk, fixture, before }) {
  const plan = deliveryPlan(fixture);
  const after = inputSnapshot();
  requireValue(JSON.stringify(before) === JSON.stringify(after), 'INPUT_CHANGED: código/configuración/commit cambiaron durante la generación; regenerar.');
  const inspected = inspectApk(apk, sdk, jdk);
  const problems = checkApk(inspected, { version: before.version, expectedCertificate: plan.expectedCertificate });
  requireValue(problems.length === 0, `APK: ${problems.join('; ')}`);
  const suffix = process.platform === 'win32' ? '.exe' : '';
  const revision = folder => readFileSync(join(sdk, folder, 'source.properties'), 'utf8').match(/^Pkg.Revision\s*=\s*(\S+)/m)?.[1];
  requireValue(revision(`build-tools/${before.toolchain.androidBuildTools}`) === before.toolchain.androidBuildTools
    && revision(`ndk/${before.toolchain.androidNdk}`) === before.toolchain.androidNdk,
  'TOOLCHAIN: revisión SDK/NDK diferente de la fijada.');
  const javaRelease = readFileSync(join(jdk, 'release'), 'utf8');
  const javaVersion = javaRelease.match(/^JAVA_VERSION="([^"]+)"/m)?.[1];
  requireValue(javaVersion?.startsWith('17.'), 'TOOLCHAIN: se requiere JDK 17.');
  run(join(sdk, 'build-tools', before.toolchain.androidBuildTools, `zipalign${suffix}`), ['-c', '-P', '16', '-v', '4', resolve(apk)]);
  const bytes = readFileSync(apk);
  const entries = zipEntries(bytes);
  checkPayload(entries, inspected.abis);
  const host = process.platform === 'win32' ? 'windows-x86_64' : 'linux-x86_64';
  const objdump = join(sdk, 'ndk', before.toolchain.androidNdk, 'toolchains/llvm/prebuilt', host, 'bin', `llvm-objdump${suffix}`);
  const readelf = join(sdk, 'ndk', before.toolchain.androidNdk, 'toolchains/llvm/prebuilt', host, 'bin', `llvm-readelf${suffix}`);
  const temporary = mkdtempSync(join(tmpdir(), 'autofinance-elf-'));
  const nativeLibraries = [];
  try {
    for (const [name, entry] of entries) {
      if (!/^lib\/[^/]+\/[^/]+\.so$/.test(name)) continue;
      const file = join(temporary, 'library.so');
      const data = entry.data();
      writeFileSync(file, data);
      const alignments = loadAlignments(run(objdump, ['-p', file]));
      const required16KB = /^lib\/(arm64-v8a|x86_64)\//.test(name);
      const aligned16KB = alignments.every(power => power >= 14);
      const relroAligned16KB = relroAlignment(run(readelf, ['-Wl', file]));
      nativeLibraries.push({ name, sha256: sha(data), size: data.length, zipMethod: entry.method,
        zipOffset: entry.start, loadAlignmentPowers: alignments, required16KB, aligned16KB, relroAligned16KB });
      assert16KB(name, alignments);
      requireValue(!required16KB || relroAligned16KB.every(Boolean), `ELF_16KB: RELRO incompatible ${name}; no se entrega.`);
    }
  } finally { unlinkSync(join(temporary, 'library.so')); rmdirSync(temporary); }
  requireValue(inspected.apkSha256 === sha(readFileSync(apk)) && sha(bytes) === inspected.apkSha256, 'APK_CHANGED: repetir generación.');
  requireValue(JSON.stringify(before) === JSON.stringify(inputSnapshot()), 'INPUT_CHANGED: entradas cambiaron durante la inspección; regenerar.');
  return { schemaVersion: 1, ...plan, buildMode: 'release', format: 'universal-apk', createdUtc: new Date().toISOString(),
    inputs: before, tools: { javaVersion, buildTools: before.toolchain.androidBuildTools, ndk: before.toolchain.androidNdk },
    commands: ['flutter --version', 'scripts/check-toolchain.ps1', 'flutter pub get --enforce-lockfile',
      `flutter build apk --release --config-only --dart-define=APP_ENV=${plan.appEnvironment}${plan.serverClientId ? ` --dart-define=GOOGLE_ANDROID_SERVER_CLIENT_ID=${plan.serverClientId}` : ''}`,
      `flutter build apk --release --no-pub --dart-define=APP_ENV=${plan.appEnvironment}${plan.serverClientId ? ` --dart-define=GOOGLE_ANDROID_SERVER_CLIENT_ID=${plan.serverClientId}` : ''}`,
      'aapt2 dump badging APK', 'apksigner verify --verbose --print-certs APK', 'zipalign -c -P 16 -v 4 APK', 'llvm-objdump -p EACH_NATIVE_LIBRARY', 'llvm-readelf -Wl EACH_NATIVE_LIBRARY'],
    apk: { ...inspected, size: statSync(apk).size }, nativeLibraries,
    checks: { apksigner: true, aapt2: true, zipalign16KB: true, elf16KB: true, payload: true, sourceStable: true },
    pendingGates: ['T07-preservación', 'T08-guía', 'T09-Google-real-ARM64-Openbank-MA-TSK-131'],
    reproducibility: 'Entradas identificadas; no se promete igualdad binaria entre herramientas/máquinas.' };
}

function main() {
  const { values } = parseArgs({ options: { plan: { type: 'boolean' }, fixture: { type: 'boolean' },
    snapshot: { type: 'string' }, apk: { type: 'string' }, sdk: { type: 'string' }, jdk: { type: 'string' } } });
  if (values.plan) { console.log(JSON.stringify({ ...deliveryPlan(values.fixture), inputs: inputSnapshot() })); return; }
  requireValue(values.apk && values.sdk && values.jdk && values.snapshot, 'Se requieren apk/sdk/jdk/snapshot.');
  const manifest = verifyDelivery({ ...values, before: JSON.parse(readFileSync(values.snapshot, 'utf8')).inputs });
  // Fixed destination only, ignored by Git. Failed checks leave no newly labelled candidate.
  const destination = join(root, 'dist-private/android', values.fixture ? 'ci-fixture' : 'candidate', manifest.apk.apkSha256);
  mkdirSync(destination, { recursive: true });
  copyFileSync(values.apk, join(destination, 'autofinance.apk'));
  requireValue(sha(readFileSync(join(destination, 'autofinance.apk'))) === manifest.apk.apkSha256, 'APK_CHANGED: salida copiada distinta; no hay manifiesto validado.');
  writeFileSync(join(destination, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  console.log(JSON.stringify(manifest, null, 2));
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(); } catch (error) {
    console.error(error.status || error.code ? 'APK-DELIVERY: falló herramienta/entrada local; no hay entrega validada.' : `APK-DELIVERY: ${error.message}`);
    process.exitCode = 1;
  }
}
