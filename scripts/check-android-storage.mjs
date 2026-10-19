// Auditoría independiente del APK compilado; no instala ni acredita T07/T09.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const domains = ['root', 'file', 'database', 'sharedpref', 'external', 'device_root', 'device_file', 'device_database', 'device_sharedpref'];

// aapt2 dump xmltree: conservar jerarquía para no aceptar atributos de otro nodo.
export function tree(dump) {
  const root = { name: '#document', attributes: {}, children: [], indent: -1 };
  const stack = [root];
  for (const line of dump.split(/\r?\n/)) {
    const element = /^(\s*)E: ([\w-]+)(?:\s|$)/.exec(line);
    if (element) {
      const node = { name: element[2], attributes: {}, children: [], indent: element[1].length };
      while (stack.at(-1).indent >= node.indent) stack.pop();
      stack.at(-1).children.push(node);
      stack.push(node);
    } else {
      const attribute = /^\s*A: (?:http[^\s]+:)?([\w]+)(?:\(0x[\da-f]+\))?=(.*)$/i.exec(line);
      if (attribute) {
        const value = attribute[2].trim();
        assert(!(attribute[1] in stack.at(-1).attributes), 'Atributo duplicado');
        stack.at(-1).attributes[attribute[1]] = value.startsWith('"') ? JSON.parse(value.match(/^"(?:[^"\\]|\\.)*"/)[0]) : value;
      }
    }
  }
  assert.equal(root.children.length, 1, 'XML empaquetado ausente/ambiguo');
  return root.children[0];
}

function exclusions(section) {
  assert.deepEqual(section.children.map(x => x.name), domains.map(() => 'exclude'), 'Solo exclusiones completas, sin includes');
  assert.deepEqual(section.children.map(x => x.attributes.domain).sort(), [...domains].sort(), 'Falta dominio excluido');
  for (const child of section.children) assert.deepEqual(Object.keys(child.attributes).sort(), ['domain', 'path']);
  assert(section.children.every(x => x.attributes.path === '.' && x.children.length === 0), 'Excluir dominio completo');
}

export function auditStorage({ manifestDump, legacyDump, extractionDump, resourcesDump }) {
  const manifest = tree(manifestDump);
  assert.equal(manifest.name, 'manifest');
  assert.equal(manifest.attributes.package, 'com.carlosmg91.myautofinance');
  const applications = manifest.children.filter(x => x.name === 'application');
  assert.equal(applications.length, 1);
  const application = applications[0];
  assert.equal(application.attributes.allowBackup, 'false', 'allowBackup debe ser false');
  assert(!application.attributes.backupAgent, 'Sin agente alternativo de backup');
  const debuggable = application.attributes.debuggable === 'true';
  if (!debuggable) assert(!application.children.some(x => x.name === 'provider' &&
    /SyntheticDocumentsProvider|storageaudit/.test(`${x.attributes.name} ${x.attributes.authorities}`)), 'Proveedor sintético prohibido en release');
  if (!debuggable) assert(!application.children.some(x => /StorageAuditActivity/.test(x.attributes.name)), 'Host de instrumentación prohibido en release');
  for (const [attribute, resource] of [['fullBackupContent', 'backup_rules'], ['dataExtractionRules', 'data_extraction_rules']]) {
    const id = new RegExp(`resource (0x[\\da-f]+) (?:[\\w.]+:)?xml/${resource}\\b`, 'i').exec(resourcesDump)?.[1];
    assert(id, `No se empaquetó xml/${resource}`);
    assert.equal(application.attributes[attribute]?.toLowerCase(), `@${id.toLowerCase()}`, `Referencia incorrecta: ${attribute}`);
  }
  const permissions = manifest.children.filter(x => /^uses-permission/.test(x.name)).map(x => x.attributes.name).sort();
  const allowed = new Set(['android.permission.INTERNET', 'android.permission.USE_BIOMETRIC', 'android.permission.USE_FINGERPRINT', 'com.carlosmg91.myautofinance.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION']);
  assert(permissions.every(x => allowed.has(x)), 'Permiso fuera del inventario: revisar sin ampliar automáticamente');
  assert(permissions.includes('android.permission.INTERNET'));
  const legacy = tree(legacyDump);
  assert.equal(legacy.name, 'full-backup-content'); exclusions(legacy);
  const extraction = tree(extractionDump);
  assert.equal(extraction.name, 'data-extraction-rules');
  assert.deepEqual(extraction.children.map(x => x.name).sort(), ['cloud-backup', 'device-transfer']);
  extraction.children.forEach(exclusions);
  return { debuggable, permissions, backupDomains: domains, cloudBackup: 'excluded', deviceTransfer: 'excluded', completeDelivery: false };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const args = process.argv.slice(2);
    assert(args.length === 4 && args[0] === '--apk' && args[2] === '--sdk', 'Uso: --apk archivo.apk --sdk directorio-SDK');
    const apk = resolve(args[1]);
    const aapt = join(resolve(args[3]), 'build-tools/36.0.0', `aapt2${process.platform === 'win32' ? '.exe' : ''}`);
    const hash = () => createHash('sha256').update(readFileSync(apk)).digest('hex');
    const before = hash();
    const run = args => execFileSync(aapt, [...args, apk], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 16 * 1024 * 1024 });
    const xml = file => run(['dump', 'xmltree', '--file', file]);
    const report = auditStorage({ manifestDump: xml('AndroidManifest.xml'), legacyDump: xml('res/xml/backup_rules.xml'), extractionDump: xml('res/xml/data_extraction_rules.xml'), resourcesDump: run(['dump', 'resources']) });
    assert.equal(hash(), before, 'APK cambió durante la auditoría');
    console.log(JSON.stringify({ apkSha256: before, ...report }, null, 2));
  } catch (error) {
    console.error(`ANDROID-STORAGE: ${error instanceof assert.AssertionError ? error.message.split('\n')[0] : 'No se pudo inspeccionar el APK; no se acredita la política.'}`);
    process.exitCode = 1;
  }
}
