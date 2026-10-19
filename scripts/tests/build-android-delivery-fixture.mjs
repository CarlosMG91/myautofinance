// Exercise the actual universal release pipeline with an ephemeral key, APP_ENV=test.
import { execFileSync } from 'node:child_process';
import { randomBytes, createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, rmdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const jdk = process.env.JAVA_HOME;
const sdk = process.env.ANDROID_HOME;
if (!jdk || !sdk) throw new Error('Se requieren JAVA_HOME y ANDROID_HOME fijados.');
const temporary = mkdtempSync(join(tmpdir(), 'autofinance-apk-fixture-'));
const password = randomBytes(48).toString('base64');
const env = { ...process.env };
for (const name of Object.keys(env)) if (name.startsWith('AUTOFINANCE_SIGNING_')) delete env[name];
const keytool = join(jdk, process.platform === 'win32' ? 'bin/keytool.exe' : 'bin/keytool');
const store = join(temporary, 'fixture.p12');
try {
  const common = ['-keystore', store, '-storetype', 'PKCS12', '-alias', 'ephemeral-ci', '-storepass:env', 'FIXTURE_PASSWORD'];
  const key = args => execFileSync(keytool, args, { env: { ...env, FIXTURE_PASSWORD: password }, stdio: 'pipe' });
  key(['-genkeypair', '-noprompt', ...common, '-keyalg', 'RSA', '-keysize', '2048', '-validity', '2', '-dname', 'CN=Ephemeral APK Fixture']);
  const cert = join(temporary, 'certificate.der');
  key(['-exportcert', ...common, '-file', cert]);
  Object.assign(env, { AUTOFINANCE_SIGNING_STORE_FILE: store, AUTOFINANCE_SIGNING_STORE_PASSWORD: password,
    AUTOFINANCE_SIGNING_KEY_ALIAS: 'ephemeral-ci', AUTOFINANCE_SIGNING_KEY_PASSWORD: password,
    AUTOFINANCE_SIGNING_FIXTURE: '1', AUTOFINANCE_SIGNING_FIXTURE_SHA256: createHash('sha256').update(readFileSync(cert)).digest('hex') });
  execFileSync(process.platform === 'win32' ? 'powershell.exe' : 'pwsh', ['-NoProfile', '-File',
    resolve(root, 'scripts/build-private-android-delivery.ps1'), '-Fixture', '-Jdk', jdk, '-AndroidSdk', sdk],
  { cwd: root, env, stdio: 'inherit' });
} finally {
  for (const name of ['fixture.p12', 'certificate.der']) rmSync(join(temporary, name), { force: true });
  rmdirSync(temporary);
}
