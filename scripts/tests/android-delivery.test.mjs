import test from 'node:test';
import assert from 'node:assert/strict';
import { deliveryPlan, checkPayload, loadAlignments, zipEntries, assert16KB, verifyDelivery, relroAlignment } from '../android-delivery.mjs';
import { validateAndroidOAuthConfig } from '../check-google-oauth-android.mjs';
import { readFileSync } from 'node:fs';

test('fixture requires an independent certificate and stays test/incomplete', () => {
  assert.throws(() => deliveryPlan(true, {}), /FIXTURE/);
  const env = { AUTOFINANCE_SIGNING_FIXTURE: '1', AUTOFINANCE_SIGNING_FIXTURE_SHA256: 'a'.repeat(64) };
  const plan = deliveryPlan(true, env);
  assert.equal(plan.appEnvironment, 'test');
  assert.equal(plan.serverClientId, null);
  assert.equal(plan.completeDelivery, false);
  assert.equal(plan.realDriveVerified, false);
});
test('production refuses CI and fixture environment', () => {
  assert.throws(() => deliveryPlan(false, { CI: 'true' }), /PRIVATE_ONLY/);
  assert.throws(() => deliveryPlan(false, { AUTOFINANCE_SIGNING_FIXTURE: '1' }), /PRIVATE_ONLY/);
});
test('missing external provisioning is rejected, never replaced with a fake ID', () => {
  const config = JSON.parse(readFileSync(new URL('../../config/google-oauth.public.json', import.meta.url)));
  config.project = { id: null, number: null };
  config.status = 'blocked_external';
  const identity = JSON.parse(readFileSync(new URL('../../packaging/android/oauth-distribution.public.json', import.meta.url)));
  assert.throws(() => validateAndroidOAuthConfig(config, identity.applicationId, identity), /proyecto Google/);
});
test('ELF parsing fails closed and inventories every LOAD alignment', () => {
  assert.deepEqual(loadAlignments(' LOAD off 0x00 align 2**14\n LOAD off 0x10 align 2**16'), [14, 16]);
  assert.deepEqual(loadAlignments(' LOAD off 0x00 align 2**12'), [12]);
  assert.throws(() => loadAlignments('unrecognized output'), /LOAD/);
  assert.throws(() => assert16KB('lib/arm64-v8a/libsqlite3.so', [14, 12]), /ELF_16KB/);
  assert.throws(() => assert16KB('lib/x86_64/libapp.so', [12]), /ELF_16KB/);
  assert16KB('lib/arm64-v8a/libapp.so', [14, 16]);
  assert16KB('lib/armeabi-v7a/libapp.so', [12]);
});
test('payload rejects missing resources, fonts, SQLite or ABI libraries', () => {
  const entries = new Map();
  const put = (name, text = 'fixture') => entries.set(name, { data: () => Buffer.from(text) });
  for (const name of ['AndroidManifest.xml', 'resources.arsc', 'assets/flutter_assets/FontManifest.json',
    'assets/flutter_assets/assets/fonts/roboto-regular.ttf', 'assets/flutter_assets/assets/fonts/roboto-medium.ttf',
    'assets/flutter_assets/assets/fonts/roboto-bold.ttf']) put(name);
  put('classes.dex', 'com/carlosmg91/myautofinance/MainActivity dev.flutter.pigeon.google_sign_in_android');
  for (const abi of ['arm64-v8a', 'x86_64']) for (const lib of ['libapp.so', 'libflutter.so', 'libsqlite3.so', 'libdartjni.so']) put(`lib/${abi}/${lib}`);
  checkPayload(entries, ['arm64-v8a', 'x86_64']);
  for (const name of [...entries.keys()]) {
    const saved = entries.get(name);
    entries.delete(name);
    assert.throws(() => checkPayload(entries, ['arm64-v8a', 'x86_64']), /PAYLOAD/);
    entries.set(name, saved);
  }
});
test('RELRO end must also be aligned to 16 KB on relevant libraries', () => {
  const header = ' Type Offset VirtAddr PhysAddr FileSiz MemSiz Flg Align\n';
  assert.deepEqual(relroAlignment(header + ' GNU_RELRO 0x0cfaf0 0x000dfaf0 0x000dfaf0 0x01510 0x00510 R 0x1'), [true]);
  assert.deepEqual(relroAlignment(header + ' GNU_RELRO 0x0cfaf0 0x000dfaf0 0x000dfaf0 0x01510 0x01510 R 0x1'), [false]);
  assert.deepEqual(relroAlignment(header), []);
  const wholeLoad = ' LOAD 0x1000 0x11000 0x11000 0x1000 0x2000 RW 0x4000\n';
  const relro = ' GNU_RELRO 0x1000 0x11000 0x11000 0x1000 0x2000 R 0x1';
  assert.deepEqual(relroAlignment(header + wholeLoad + relro), [true]);
  assert.deepEqual(relroAlignment(header + wholeLoad + ' LOAD 0x3000 0x13000 0x13000 0x10 0x10 RW 0x4000\n' + relro), [false]);
  assert.throws(() => relroAlignment('invalid'), /headers/);
});
test('malformed ZIP cannot pass inventory', () => {
  assert.throws(() => zipEntries(Buffer.alloc(30)), /ZIP/);
});
test('changed input identity aborts before inspecting or copying an APK', () => {
  const names = ['AUTOFINANCE_SIGNING_FIXTURE', 'AUTOFINANCE_SIGNING_FIXTURE_SHA256'];
  const saved = names.map(name => process.env[name]);
  try {
    process.env[names[0]] = '1'; process.env[names[1]] = 'a'.repeat(64);
    assert.throws(() => verifyDelivery({ fixture: true, before: {}, apk: 'nonexistent' }), /INPUT_CHANGED/);
  } finally {
    names.forEach((name, i) => { if (saved[i] === undefined) delete process.env[name]; else process.env[name] = saved[i]; });
  }
});
