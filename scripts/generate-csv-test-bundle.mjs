import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// Sólo datos sintéticos: empaquetar bytes exactos para el runner nativo,
// que no dispone del checkout. La prueba de VM contrasta cada archivo.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const manifest = JSON.parse(await readFile(resolve(root, 'docs/ep-013/fixtures/manifiesto.json'), 'utf8'));
const entries = [['historico-ejemplo.csv', 'docs/ep-001/historico-ejemplo.csv'],
  ...manifest.files.map(({ file }) => [file, `docs/ep-013/fixtures/archivos/${file}`])];
let dart = '// Generado por scripts/generate-csv-test-bundle.mjs. No editar.\n'
  + 'const csvTestBundle = <String, String>{\n';
for (const [name, path] of entries) {
  const bytes = await readFile(resolve(root, path));
  dart += `  '${name}': '${bytes.toString('base64')}',\n`;
}
dart += '};\n';
const target = resolve(root, 'test/support/csv_test_bundle.dart');
if (process.argv.includes('--check')) {
  if (await readFile(target, 'utf8') !== dart) throw new Error('Bundle CSV desactualizado');
  console.log(`OK: ${entries.length} archivos binarios exactos para pruebas nativas.`);
} else await writeFile(target, dart);
