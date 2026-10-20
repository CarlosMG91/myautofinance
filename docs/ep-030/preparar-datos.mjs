// Solo empaqueta entradas sintéticas; no abre SQLite, instalaciones ni Drive.
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { resolve, join } from 'node:path';
import assert from 'node:assert/strict';

const root = fileURLToPath(new URL('../../', import.meta.url));
const source = await readFile(join(root, 'docs/ep-001/historico-ejemplo.csv'));
// El paquete transportable siempre usa UTF-8/LF, igual que la copia Dart existente.
const base = source.toString('utf8').replaceAll('\r\n', '\n');
const header = base.split('\n')[0];
const pending = `${header}\n2026-01-10;Abono pendiente;7.00;REAL;;;;Cuenta principal;\n2026-01-10;Cargo pendiente;-3.00;REAL;;;;Cuenta principal;\n`;
const account = `${header}\n2026-01-10;Cuenta por resolver;-3.00;REAL;Ocio;;;Cuenta sintética sin resolver;\n`;
const conflict = `${header}\n2026-01-01;Padre incompatible;1000.00;PRESUPUESTO;Vivienda;;;;\n`;
const files = {
  'base.csv': base,
  'categoria-pendiente.csv': pending,
  'cuenta-sin-resolver.csv': account,
  'padre-incompatible.csv': conflict,
};
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
assert.equal(hash(base), '0b997f5c8092369aa47a08c8cca6d4c22050abca320880a173818d4e34576b62');
const rows = base.trimEnd().split('\n').slice(1);
assert.equal(rows.filter(r => r.split(';')[3] === 'REAL').length, 10);
assert.equal(rows.filter(r => r.split(';')[3] === 'PRESUPUESTO').length, 48);
assert.equal(rows.filter(r => r.includes(';Café;')).length, 2);
const embedded = await readFile(join(root, 'test/support/budget_proposal_reference_csv.dart'), 'utf8');
assert.equal(embedded.replaceAll('\r\n', '\n').split("r'''", 2)[1].split("'''", 1)[0], base);
const oracle = JSON.parse(await readFile(new URL('./oraculos.json', import.meta.url), 'utf8'));
for (const [name, content] of Object.entries(files)) {
  assert.equal(hash(content), oracle.files[name], `SHA-256: ${name}`);
}
if (process.argv.length === 4 && process.argv[2] === '--destino') {
  const destination = resolve(process.argv[3]);
  // mkdir sin recursive: rechaza cualquier destino existente, nunca repone encima.
  await mkdir(destination);
  for (const [name, content] of Object.entries(files)) {
    await writeFile(join(destination, name), content, { flag: 'wx' });
  }
  await writeFile(join(destination, 'oraculos.json'), `${JSON.stringify(oracle, null, 2)}\n`, { flag: 'wx' });
  console.log(`Paquete sintético nuevo: ${destination}`);
} else {
  assert.equal(process.argv.length, 2, 'Uso: node docs/ep-030/preparar-datos.mjs [--destino CARPETA_NUEVA]');
}
console.log('OK T02: CSV original, copia portable, duplicados y hashes de cuatro archivos.');
