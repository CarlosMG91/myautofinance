// Native release-upgrade fixture. No production keys, OAuth, uninstall or clear-data.
import { execFileSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, rmdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs, isDeepStrictEqual } from 'node:util';
import { zipEntries } from './android-delivery.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const packageId = 'com.carlosmg91.myautofinance';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const requireValue = (condition, message) => { if (!condition) throw new Error(message); };

export function verifyPair(n, next) {
  for (const manifest of [n, next]) {
    requireValue(manifest.appEnvironment === 'test' && manifest.purpose === 'ci-ephemeral-fixture'
      && manifest.buildMode === 'release' && manifest.format === 'universal-apk'
      && manifest.apk.applicationId === packageId && manifest.apk.debuggable === false
      && manifest.apk.certificateSha256 === manifest.expectedCertificate
      && ['apksigner', 'aapt2', 'zipalign16KB', 'elf16KB', 'payload', 'sourceStable']
        .every(check => manifest.checks[check] === true), 'Not a verified T05 release fixture');
  }
  requireValue(n.expectedCertificate === next.expectedCertificate, 'Different signing certificates');
  requireValue(Number(next.apk.versionCode) > Number(n.apk.versionCode), 'versionCode must increase');
}

export function verifyPreservation(before, after, { recovery = false } = {}) {
  requireValue(before.ok && after.ok, 'Native fixture failed');
  requireValue(isDeepStrictEqual(before.snapshot.tables, after.snapshot.tables), 'Financial tables changed');
  if (!recovery) requireValue(isDeepStrictEqual(before.snapshot.files, after.snapshot.files), 'Support files changed');
  else {
    // Recovery legitimately appends its journal/backup/catalog. Existing backup images
    // and the pending sync record must still be byte-identical.
    for (const [path, hash] of Object.entries(before.snapshot.files)) {
      if (path === 'drive-sync/state.json' || path.endsWith('/autofinance.sqlite') || path === 'upgrade-backup-id') {
        requireValue(after.snapshot.files[path] === hash, `Recovery lost ${path}`);
      }
    }
  }
  for (const key of ['package', 'keyAlias', 'keyCreated', 'ciphertextSha256']) {
    requireValue(before.native[key] === after.native[key], `Native persistence changed: ${key}`);
  }
}

async function main() {
  const { values } = parseArgs({ options: { serial: { type: 'string' }, avd: { type: 'string' },
    sdk: { type: 'string' }, jdk: { type: 'string' } } });
  requireValue(values.serial?.startsWith('emulator-') && values.avd && values.sdk && values.jdk,
    'Require --serial emulator-ID --avd DISPOSABLE_NAME --sdk PATH --jdk PATH');
  const sdk = resolve(values.sdk), jdk = resolve(values.jdk);
  const suffix = process.platform === 'win32' ? '.exe' : '';
  const adbPath = join(sdk, 'platform-tools', `adb${suffix}`);
  const command = (file, args, options = {}) => execFileSync(file, args,
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...options });
  const adb = args => command(adbPath, ['-s', values.serial, ...args]);
  requireValue(adb(['emu', 'avd', 'name']).trim().split(/[\r\n]+/)[0] === values.avd, 'Disposable AVD identity mismatch');
  requireValue(adb(['shell', 'getprop', 'sys.boot_completed']).trim() === '1', 'AVD not booted');
  requireValue(!adb(['shell', 'pm', 'list', 'packages', packageId]).includes(`package:${packageId}`),
    'Package already installed: STOP. Use a new disposable AVD; never uninstall/clear-data');
  mkdirSync(join(root, '.tools'), { recursive: true });
  const work = mkdtempSync(join(root, '.tools/243-native-'));
  const checkout = join(work, 'checkout');
  const temporary = mkdtempSync(join(tmpdir(), 'autofinance-upgrade-'));
  const env = { ...process.env, JAVA_HOME: jdk, ANDROID_HOME: sdk, ANDROID_SDK_ROOT: sdk };
  for (const name of Object.keys(env)) if (name.startsWith('AUTOFINANCE_SIGNING_')) delete env[name];
  const token = randomBytes(32).toString('hex');
  const password = randomBytes(48).toString('base64');
  const evidence = { schemaVersion: 1, ticket: 'MA-TSK-243', createdUtc: new Date().toISOString(),
    serial: values.serial, avd: values.avd, completeDelivery: false, realGoogleLogin: false,
    sourceCommit: command('git', ['rev-parse', 'HEAD'], { cwd: root }).trim(), results: {} };
  const save = () => writeFileSync(join(work, 'evidence.json'), JSON.stringify(evidence, null, 2) + '\n');
  let phase, pending, server, port;
  let reverseAdded = false;
  const keytool = join(jdk, 'bin', `keytool${suffix}`);
  const createKey = name => {
    const store = join(temporary, `${name}.p12`), cert = join(temporary, `${name}.der`);
    const common = ['-keystore', store, '-storetype', 'PKCS12', '-alias', 'upgrade-fixture', '-storepass:env', 'UPGRADE_PASSWORD'];
    const keyEnv = { ...env, UPGRADE_PASSWORD: password };
    command(keytool, ['-genkeypair', '-noprompt', ...common, '-keyalg', 'RSA', '-keysize', '2048', '-validity', '2',
      '-dname', 'CN=Synthetic Upgrade Fixture'], { env: keyEnv });
    command(keytool, ['-exportcert', ...common, '-file', cert], { env: keyEnv });
    return { store, certificate: sha(readFileSync(cert)) };
  };
  try {
    console.log('Cloning committed sources; concurrent edits excluded.');
    command('git', ['clone', '--no-local', '--quiet', root, checkout]);
    evidence.sourceCommit = command('git', ['rev-parse', 'HEAD'], { cwd: checkout }).trim();
    // Android-only checkout: prevent Flutter pub from regenerating unrelated
    // desktop-plugin symlinks on Windows hosts without Developer Mode.
    renameSync(join(checkout, 'windows'), join(work, 'windows-unused'));
    server = createServer(async (request, response) => {
      if (request.headers['x-upgrade-token'] !== token) { response.writeHead(403).end(); return; }
      if (request.url === '/command' && request.method === 'GET') {
        response.end(JSON.stringify({ phase, csv: readFileSync(join(root, 'docs/ep-001/historico-ejemplo.csv'), 'utf8') }));
      } else if (request.url === '/result' && request.method === 'POST') {
        const chunks = [];
        for await (const chunk of request) chunks.push(chunk);
        try {
          const result = JSON.parse(Buffer.concat(chunks).toString());
          response.end('{}'); pending?.(result);
        } catch { response.writeHead(400).end(); }
      } else { response.writeHead(404).end(); }
    });
    await new Promise(resolveListen => server.listen(0, '127.0.0.1', resolveListen));
    port = server.address().port;
    const fixture = readFileSync(join(root, 'scripts/fixtures/android-upgrade/main.dart'), 'utf8')
      .replace('const _port = 24300;', `const _port = ${port};`).replace('UPGRADE_RUN_TOKEN', token);
    writeFileSync(join(checkout, 'lib/main.dart'), fixture);
    const native = join(checkout, 'android/app/src/main/kotlin/com/carlosmg91/myautofinance');
    copyFileSync(join(root, 'scripts/fixtures/android-upgrade/UpgradeProbeChannel.kt'), join(native, 'UpgradeProbeChannel.kt'));
    const activity = join(native, 'MainActivity.kt');
    writeFileSync(activity, readFileSync(activity, 'utf8').replace('super.configureFlutterEngine(flutterEngine)',
      'super.configureFlutterEngine(flutterEngine)\n        UpgradeProbeChannel.attach(this, flutterEngine)'));
    const manifestPath = join(checkout, 'android/app/src/main/AndroidManifest.xml');
    writeFileSync(manifestPath, readFileSync(manifestPath, 'utf8').replace('<application', '<application android:usesCleartextTraffic="true"'));
    const key = createKey('same-key');
    Object.assign(env, { AUTOFINANCE_SIGNING_STORE_FILE: key.store, AUTOFINANCE_SIGNING_STORE_PASSWORD: password,
      AUTOFINANCE_SIGNING_KEY_ALIAS: 'upgrade-fixture', AUTOFINANCE_SIGNING_KEY_PASSWORD: password,
      AUTOFINANCE_SIGNING_FIXTURE: '1', AUTOFINANCE_SIGNING_FIXTURE_SHA256: key.certificate });
    const pubspec = join(checkout, 'pubspec.yaml'), original = readFileSync(pubspec, 'utf8');
    const build = (version, label) => {
      writeFileSync(pubspec, original.replace(/^version:\s*\S+/m, `version: ${version}`));
      console.log(`T05 generator: ${label} ${version}`);
      const log = join(work, `${label}-build.log`);
      const output = command(process.platform === 'win32' ? 'powershell.exe' : 'pwsh', ['-NoProfile', '-File',
        join(checkout, 'scripts/build-private-android-delivery.ps1'), '-Fixture', '-Jdk', jdk, '-AndroidSdk', sdk],
      { cwd: checkout, env, maxBuffer: 16 * 1024 * 1024 });
      writeFileSync(log, output);
      const apk = join(work, `${label}.apk`);
      copyFileSync(join(checkout, 'build/app/outputs/flutter-apk/app-release.apk'), apk);
      const hash = sha(readFileSync(apk));
      const manifest = JSON.parse(readFileSync(join(checkout, 'dist-private/android/ci-fixture', hash, 'manifest.json')));
      evidence[label] = manifest; save();
      return { apk, manifest };
    };
    const n = build('0.1.0+24301', 'N');
    evidence.fixtureOverlaySha256 = sha(fixture);
    evidence.probeSha256 = sha(readFileSync(join(native, 'UpgradeProbeChannel.kt')));
    adb(['reverse', `tcp:${port}`, `tcp:${port}`]); reverseAdded = true;
    const runPhase = async (action, label) => {
      phase = action;
      adb(['shell', 'am', 'force-stop', packageId]);
      const result = await new Promise((resolveResult, reject) => {
        const timer = setTimeout(() => { pending = null; reject(new Error(`Timeout: ${label}`)); }, 120000);
        pending = value => { clearTimeout(timer); pending = null; resolveResult(value); };
        try { adb(['shell', 'am', 'start', '-W', '-n', `${packageId}/.MainActivity`]); }
        catch (error) { clearTimeout(timer); pending = null; reject(error); }
      });
      evidence.results[label] = result; save();
      requireValue(action.endsWith('interrupt') ? result.readyToKill === true : result.ok === true,
        `Native ${label} failed: ${result.error ?? 'no result'}`);
      console.log(`Native ${label}: passed`);
      return result;
    };
    const install = apk => adb(['install', '-r', apk]); // Never -d, uninstall, or clear.
    requireValue(install(n.apk).includes('Success'), 'N installation failed');
    const before = await runPhase('seed', 'N-seed');
    requireValue(before.native.versionName === '0.1.0' && before.native.versionCode === 24301, 'Installed N differs');
    const reboot = async () => {
      adb(['reboot']);
      for (let i = 0; i < 120; i++) {
        await new Promise(resolveWait => setTimeout(resolveWait, 1000));
        try { if (adb(['shell', 'getprop', 'sys.boot_completed']).trim() === '1') return; } catch { /* booting */ }
      }
      throw new Error('Emulator reboot timeout');
    };
    verifyPreservation(before, await runPhase('verify', 'N-restart'));
    await runPhase('transaction-interrupt', 'N-uncommitted');
    adb(['shell', 'am', 'force-stop', packageId]);
    const next = build('0.1.1+24302', 'N1');
    verifyPair(n.manifest, next.manifest);
    requireValue(install(next.apk).includes('Success'), 'N+1 update failed');
    const after = await runPhase('verify', 'N1-updated');
    verifyPreservation(before, after);
    requireValue(after.native.versionName === '0.1.1' && after.native.versionCode === 24302, 'Installed N+1 differs');
    evidence.installedPackage = adb(['shell', 'dumpsys', 'package', packageId]);
    const rejectInstall = async (apk, reason, label) => {
      let output;
      try { output = install(apk); } catch (error) { output = `${error.stdout ?? ''}\n${error.stderr ?? ''}`; }
      requireValue(output.includes(reason) && !output.includes('Success'), `Expected ${reason}`);
      evidence.results[label] = { rejection: reason }; save();
      verifyPreservation(before, await runPhase('verify', `${label}-preserved`));
    };
    await rejectInstall(n.apk, 'INSTALL_FAILED_VERSION_DOWNGRADE', 'downgrade');
    const otherKey = createKey('other-key');
    const other = join(work, 'other-signature.apk');
    const signer = join(sdk, 'build-tools/36.0.0', process.platform === 'win32' ? 'apksigner.bat' : 'apksigner');
    const sign = (input, output, signingKey) => {
      const signerArgs = ['sign', '--ks', signingKey.store, '--ks-key-alias', 'upgrade-fixture', '--ks-pass', 'env:UPGRADE_PASSWORD',
        '--key-pass', 'env:UPGRADE_PASSWORD', '--out', output, input];
      if (process.platform === 'win32') {
        // .bat requires cmd; values are only trusted tool/generated local paths.
        requireValue(![signer, ...signerArgs].some(s => /["%\r\n]/.test(s)), 'Unsafe signer path');
        command('cmd.exe', ['/d', '/s', '/c', `""${signer}" ${signerArgs.map(s => `"${s}"`).join(' ')}"`], { env: { ...env, UPGRADE_PASSWORD: password } });
      } else command(signer, signerArgs, { env: { ...env, UPGRADE_PASSWORD: password } });
    };
    sign(next.apk, other, otherKey);
    evidence.otherCertificateSha256 = otherKey.certificate;
    evidence.otherApkSha256 = sha(readFileSync(other));
    await rejectInstall(other, 'INSTALL_FAILED_UPDATE_INCOMPATIBLE', 'other-signature');
    // Deliberately incompatible, non-deliverable install candidates. They use
    // the same package/key and a higher version, so identity/downgrade checks
    // cannot mask the Android SDK/ABI rejection. Never launch these candidates.
    const incompatible = (label, minimumSdk, abi) => {
      const directory = join(work, label);
      mkdirSync(directory);
      const xml = join(directory, 'AndroidManifest.xml');
      writeFileSync(xml, `<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="${packageId}" android:versionCode="24303" android:versionName="0.1.2"><uses-sdk android:minSdkVersion="${minimumSdk}" android:targetSdkVersion="${Math.max(36, minimumSdk)}"/><application android:hasCode="false" android:extractNativeLibs="true" android:label="Synthetic rejected APK"/></manifest>`);
      const draft = join(directory, 'draft.apk'), aligned = join(directory, 'aligned.apk'), signed = join(directory, 'rejected.apk');
      command(join(sdk, 'build-tools/36.0.0', `aapt2${suffix}`), ['link', '--manifest', xml,
        '-I', join(sdk, 'platforms/android-36/android.jar'), '-o', draft]);
      if (abi) {
        const library = zipEntries(readFileSync(next.apk)).get(`lib/${abi}/libsqlite3.so`).data();
        const payload = join(directory, 'lib', abi);
        mkdirSync(payload, { recursive: true });
        writeFileSync(join(payload, 'libsqlite3.so'), library);
        command(join(jdk, 'bin', `jar${suffix}`), ['--update', '--file', draft, '-C', directory, 'lib']);
      }
      command(join(sdk, 'build-tools/36.0.0', `zipalign${suffix}`), ['-f', '4', draft, aligned]);
      sign(aligned, signed, key);
      evidence.results[`${label}-artifact`] = { sha256: sha(readFileSync(signed)),
        certificateSha256: key.certificate, minimumSdk, abi: abi ?? null, deliverable: false };
      save(); return signed;
    };
    const unsupportedAbi = ['arm64-v8a', 'armeabi-v7a', 'x86_64'].find(abi => !before.native.abis.includes(abi));
    requireValue(unsupportedAbi, 'No incompatible ABI in the fixture payload');
    await rejectInstall(incompatible('incompatible-sdk', 99), 'INSTALL_FAILED_OLDER_SDK', 'incompatible-sdk');
    await rejectInstall(incompatible('incompatible-abi', 24, unsupportedAbi), 'INSTALL_FAILED_NO_MATCHING_ABIS', 'incompatible-abi');
    await reboot();
    adb(['reverse', `tcp:${port}`, `tcp:${port}`]);
    verifyPreservation(before, await runPhase('verify', 'N1-device-reboot'));
    await runPhase('restore-interrupt', 'N1-restore-interrupted');
    adb(['shell', 'am', 'force-stop', packageId]);
    const recovered = await runPhase('verify', 'N1-restore-recovered');
    verifyPreservation(before, recovered, { recovery: true });
    verifyPreservation(recovered, await runPhase('verify', 'N1-recovery-restarted'));
    evidence.status = 'passed-current-emulator';
    evidence.pending = ['API24', 'API36', '16KB-runtime', 'ARM64-phone-T09', 'production-Google-Openbank-T09'];
    save(); console.log(`Evidence: ${join(work, 'evidence.json')}`);
  } catch (error) {
    evidence.status = 'failed'; evidence.error = String(error.message); save();
    if (error.stdout) writeFileSync(join(work, 'failure-stdout.log'), error.stdout);
    if (error.stderr) writeFileSync(join(work, 'failure-stderr.log'), error.stderr);
    console.error(`Evidence: ${join(work, 'evidence.json')}`); throw error;
  } finally {
    if (reverseAdded) { try { adb(['reverse', '--remove', `tcp:${port}`]); } catch { /* device unavailable */ } }
    if (server) await new Promise(resolveClose => server.close(resolveClose));
    for (const name of ['same-key', 'other-key']) {
      for (const extension of ['p12', 'der']) rmSync(join(temporary, `${name}.${extension}`), { force: true });
    }
    rmdirSync(temporary);
  }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(`UPGRADE: ${error.message}`); process.exitCode = 1; });
}
