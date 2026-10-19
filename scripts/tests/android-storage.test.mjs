import { test } from 'node:test';
import assert from 'node:assert/strict';
import { auditStorage, domains } from '../check-android-storage.mjs';

const excludes = indent => domains.map(d => `${indent}E: exclude (line=1)\n${indent}  A: domain="${d}"\n${indent}  A: path="."`).join('\n');
const fixture = () => ({
  manifestDump: `E: manifest (line=1)
  A: package="com.carlosmg91.myautofinance"
  E: uses-permission (line=1)
    A: http://schemas.android.com/apk/res/android:name(0x01010003)="android.permission.INTERNET"
  E: application (line=1)
    A: http://schemas.android.com/apk/res/android:allowBackup(0x01010280)=false
    A: http://schemas.android.com/apk/res/android:fullBackupContent(0x010104eb)=@0x7f120000
    A: http://schemas.android.com/apk/res/android:dataExtractionRules(0x0101063e)=@0x7f120001`,
  resourcesDump: 'resource 0x7f120000 xml/backup_rules\nresource 0x7f120001 xml/data_extraction_rules',
  legacyDump: `E: full-backup-content (line=1)\n${excludes('  ')}`,
  extractionDump: `E: data-extraction-rules (line=1)\n  E: cloud-backup (line=1)\n${excludes('    ')}\n  E: device-transfer (line=1)\n${excludes('    ')}`,
});

test('Política completa empaquetada: no acredita entrega final', () => {
  assert.equal(auditStorage(fixture()).completeDelivery, false);
});
for (const permission of ['REQUEST_INSTALL_PACKAGES', 'READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE', 'MANAGE_EXTERNAL_STORAGE', 'READ_MEDIA_IMAGES']) {
  test(`Rechaza permiso ${permission} de cualquier manifiesto fusionado`, () => {
    const f = fixture(); f.manifestDump = f.manifestDump.replace('android.permission.INTERNET', `android.permission.${permission}`);
    assert.throws(() => auditStorage(f));
  });
}
for (const field of ['legacyDump', 'extractionDump']) {
  for (const domain of domains) test(`Rechaza exclusión incompleta ${field}/${domain}`, () => {
    const f = fixture(); f[field] = f[field].replace(`domain="${domain}"`, 'domain="file"');
    // file duplicado se prueba quitando su exclusión completa.
    if (domain === 'file') f[field] = f[field].replace(/\s*E: exclude \(line=1\)\s*A: domain="file"\s*A: path="\."/, '');
    assert.throws(() => auditStorage(f));
  });
}
test('allowBackup=false solo no basta; detecta recursos ausentes y referencias cruzadas', () => {
  for (const mutate of [f => f.resourcesDump = '', f => f.manifestDump = f.manifestDump.replace('@0x7f120001', '@0x7f120000'), f => f.manifestDump = f.manifestDump.replace('=false', '=true'), f => f.extractionDump = f.extractionDump.replace('device-transfer', 'otro')]) {
    const f = fixture(); mutate(f); assert.throws(() => auditStorage(f));
  }
});
test('No acepta exclusión parcial, includes ni atributo en otro nodo', () => {
  for (const mutate of [f => f.legacyDump = f.legacyDump.replace('path="."', 'path="sqlite"'), f => f.extractionDump = f.extractionDump.replace('E: exclude', 'E: include'), f => f.manifestDump = f.manifestDump.replace('    A: http://schemas.android.com/apk/res/android:allowBackup', '    E: activity (line=2)\n      A: http://schemas.android.com/apk/res/android:allowBackup')]) {
    const f = fixture(); mutate(f); assert.throws(() => auditStorage(f));
  }
});
test('El proveedor de fallos no puede estar en un APK sin debug', () => {
  const f = fixture();
  f.manifestDump += '\n    E: provider (line=1)\n      A: http://schemas.android.com/apk/res/android:name(0x01010003)="com.carlosmg91.myautofinance.SyntheticDocumentsProvider"';
  assert.throws(() => auditStorage(f));
  f.manifestDump = f.manifestDump.replace('    E: provider', '    A: http://schemas.android.com/apk/res/android:debuggable(0x0101000f)=true\n    E: provider');
  assert.equal(auditStorage(f).debuggable, true);
});
test('La actividad de instrumentación tampoco puede estar en release', () => {
  const f = fixture();
  f.manifestDump += '\n    E: activity (line=1)\n      A: http://schemas.android.com/apk/res/android:name(0x01010003)="com.carlosmg91.myautofinance.StorageAuditActivity"';
  assert.throws(() => auditStorage(f));
});
