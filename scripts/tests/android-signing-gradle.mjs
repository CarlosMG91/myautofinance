// Actual Gradle graphs with one ephemeral key. No distribution credentials are read.
import { execFileSync } from 'node:child_process';
import { randomBytes, createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const jdk = process.env.JAVA_HOME;
assert(jdk && /^JAVA_VERSION="17\./m.test(readFileSync(join(jdk, 'release'), 'utf8')), 'JDK 17 required');
const suffix = process.platform === 'win32' ? '.exe' : '';
const temporary = mkdtempSync(join(tmpdir(), 'autofinance-signing-fixture-'));
const password = randomBytes(48).toString('base64');
const alias = `fixture-${randomBytes(16).toString('hex')}`;
const store = join(temporary, 'fixture.p12');
const env = { ...process.env };
for (const key of Object.keys(env)) if (key.startsWith('AUTOFINANCE_SIGNING_')) delete env[key];
delete env.CI;
const java = join(jdk, `bin/java${suffix}`);
const common = ['-keystore', store, '-storetype', 'PKCS12', '-alias', alias, '-storepass:env', 'FIXTURE_PASSWORD'];
const keytool = args => execFileSync(join(jdk, `bin/keytool${suffix}`), args, { env: { ...env, FIXTURE_PASSWORD: password }, stdio: 'pipe' });
function gradle(task, extraEnv = {}, expectedError, extraArgs = []) {
  let output;
  let status = 0;
  try {
    output = execFileSync(java, ['-cp', 'gradle/wrapper/gradle-wrapper.jar', 'org.gradle.wrapper.GradleWrapperMain', task,
      '--no-daemon', '--no-configuration-cache', '--console=plain', '-Dorg.gradle.jvmargs=-Xmx2G', ...extraArgs], {
      cwd: join(root, 'android'), env: { ...env, ...extraEnv }, encoding: 'utf8', stdio: 'pipe', timeout: 300000,
    });
  } catch (error) {
    output = `${error.stdout ?? ''}\n${error.stderr ?? ''}`;
    status = error.status ?? 1;
  }
  // Only sanitized assertions escape this process; do not print Gradle output.
  assert(!output.includes(password), 'Gradle output must not contain fixture password');
  assert(!output.includes(alias), 'Gradle output must not contain fixture alias');
  if (expectedError) {
    assert.notEqual(status, 0, `expected ${expectedError}`);
    assert(output.includes(`APK-SIGNING[${expectedError}]`), `expected typed ${expectedError}; inspect Gradle configuration locally`);
  } else {
    assert.equal(status, 0, `expected successful ${task}; inspect Gradle configuration locally`);
  }
}
try {
  keytool(['-genkeypair', '-noprompt', ...common, '-keyalg', 'RSA', '-keysize', '2048', '-validity', '2', '-dname', 'CN=Ephemeral Signing Test']);
  const certFile = join(temporary, 'fixture.der');
  keytool(['-exportcert', ...common, '-file', certFile]);
  const sha256 = createHash('sha256').update(readFileSync(certFile)).digest('hex');
  const material = {
    AUTOFINANCE_SIGNING_STORE_FILE: store, AUTOFINANCE_SIGNING_STORE_PASSWORD: password,
    AUTOFINANCE_SIGNING_KEY_ALIAS: alias, AUTOFINANCE_SIGNING_KEY_PASSWORD: password,
  };
  const fixture = { ...material, AUTOFINANCE_SIGNING_FIXTURE: '1', AUTOFINANCE_SIGNING_FIXTURE_SHA256: sha256 };
  gradle(':app:assembleRelease', {}, 'MISSING_MATERIAL', ['--dry-run']);
  gradle(':app:verifyDistributionSigning', { ...material, AUTOFINANCE_SIGNING_STORE_FILE: 'relative.p12' }, 'INVALID_LOCATION');
  gradle(':app:verifyDistributionSigning', { ...material, AUTOFINANCE_SIGNING_STORE_PASSWORD: 'synthetic-wrong' }, 'INVALID_MATERIAL');
  gradle(':app:verifyDistributionSigning', material, 'CERTIFICATE_MISMATCH');
  gradle(':app:verifyDistributionSigning', { ...material, CI: 'true' }, 'PRIVATE_ONLY');
  gradle(':app:verifyDistributionSigning', fixture, 'INVALID_FIXTURE', ['-Pdart-defines=QVBQX0VOVj1wcm9kdWN0aW9u']);
  gradle(':app:verifyDistributionSigning', { ...fixture, CI: 'true' }, undefined, ['-Pdart-defines=QVBQX0VOVj10ZXN0']);
  // The real debug graph remains usable in the absence of distribution material.
  gradle(':app:assembleDebug', {}, undefined, ['--dry-run']);
  console.log('8 actual Gradle signing checks passed; only one ephemeral fixture key used and removed.');
} finally {
  const checked = realpathSync(temporary);
  assert.equal(dirname(checked), realpathSync(tmpdir()));
  assert(checked.startsWith(join(realpathSync(tmpdir()), 'autofinance-signing-fixture-')));
  rmSync(checked, { recursive: true });
}
