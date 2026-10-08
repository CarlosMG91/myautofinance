import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const out = join(root, 'archivos');
const header = 'fecha;concepto;importe_eur;tipo;categoria;subcategoria;subsubcategoria;cuenta_origen;discrecionalidad';
const row = (...fields) => fields.map(field => /[;"\r\n]/.test(field) ? `"${field.replaceAll('"', '""')}"` : field).join(';');
const real = (date, concept, amount, category = '', subcategory = '', subsubcategory = '', account = 'Cuenta principal', discretionary = '') => row(date, concept, amount, 'REAL', category, subcategory, subsubcategory, account, discretionary);
const budget = (date, concept, amount, category = 'Vivienda', subcategory = 'Alquiler', subsubcategory = '', account = '', discretionary = '') => row(date, concept, amount, 'PRESUPUESTO', category, subcategory, subsubcategory, account, discretionary);
const csv = (...rows) => `${header}\n${rows.join('\n')}\n`;
const cases = new Map();

// Fixtures válidos: reproducen exactamente el escenario propuesto por MA-TSK-118.
cases.set('valido-lf.csv', csv(
  real('2026-01-05', 'Café', '-10.00', 'Ocio', '', '', 'Cuenta principal', 'Discrecional'),
  real('2026-01-06', 'Compra; urgente', '-20.00', 'Alimentación', 'Supermercado', '', 'Cuenta principal', ' Discrecional '),
  real('2026-01-07', 'Ajuste', '-25.25', 'Vivienda', 'Alquiler'),
  budget('2026-01-01', 'Presupuesto alquiler', '400.00'),
  budget('2026-01-01', 'Presupuesto cero', '-0.00', 'Ahorro', 'Cuenta de ahorro'),
));
cases.set('valido-crlf-bom.csv', '\uFEFF' + cases.get('valido-lf.csv').replaceAll('\n', '\r\n'));
cases.set('valido-comillas-multilinea.csv', csv(
  real('2026-01-05', 'Compra "especial"; con detalle\ny nota', '-20.00', 'Ocio', '', '', 'Cuenta principal', 'Necesario'),
  budget('2026-01-01', 'Presupuesto con ; y "comillas"', '25.00', 'Vivienda', 'Alquiler'),
));
cases.set('tipo-minusculas-y-espacios.csv', `${header}\n${row(' 2026-01-05 ', ' Café ', ' -10.00 ', ' real ', ' Ocio ', '', '', ' Cuenta principal ', ' Discrecional ')}\n`);
cases.set('referencias-renombradas.csv', cases.get('valido-lf.csv'));
cases.set('dos-reales-iguales.csv', csv(
  real('2026-01-09', 'Café', '-10.00', 'Ocio', '', '', 'Cuenta principal', 'Discrecional'),
  real('2026-01-09', 'Café', '-10.00', 'Ocio', '', '', 'Cuenta principal', 'Discrecional'),
));
cases.set('bytes-distintos-contenido-similar.csv', csv(
  real('2026-01-09', 'Café', '-10.01', 'Ocio', '', '', 'Cuenta principal', 'Discrecional'),
  real('2026-01-09', 'Café', '-10.00', 'Ocio', '', '', 'Cuenta principal', 'Discrecional'),
));
cases.set('referencia-ambigua.csv', csv(real('2026-01-05', 'Compra', '-8.00', 'Alimentación', 'Supermercado')));
cases.set('conflicto-padre-descendiente.csv', csv(
  budget('2026-01-01', 'Vivienda completa', '100.00', 'Vivienda', '', ''),
  budget('2026-01-01', 'Alquiler', '400.00', 'Vivienda', 'Alquiler'),
));
cases.set('conflicto-mes-y-nodo.csv', csv(
  budget('2026-01-01', 'Alquiler enero', '400.00'),
  budget('2026-01-01', 'Alquiler enero duplicado', '450.00'),
));
cases.set('presupuesto-cuenta-no-permitida.csv', csv(budget('2026-01-01', 'Alquiler', '400.00', 'Vivienda', 'Alquiler', '', 'Cuenta principal')));
cases.set('presupuesto-categoria-ausente.csv', csv(budget('2026-01-01', 'Partida sin categoría', '400.00', '', '', '')));
cases.set('arbol-incompleto.csv', csv(real('2026-01-05', 'Compra', '-8.00', '', 'Supermercado')));
cases.set('fecha-imposible.csv', csv(real('2026-02-30', 'Compra', '-8.00', 'Ocio')));
cases.set('presupuesto-no-dia-uno.csv', csv(budget('2026-01-02', 'Alquiler', '400.00')));
cases.set('real-cero-rechazado.csv', csv(real('2026-01-05', 'Ajuste', '0.00', 'Ocio')));
cases.set('presupuesto-cero-admitido.csv', csv(budget('2026-01-01', 'Presupuesto cero', '0.00')));
cases.set('cabecera-incorrecta.csv', csv(real('2026-01-05', 'Compra', '-8.00', 'Ocio')).replace('importe_eur', 'importe'));
cases.set('columna-de-mas.csv', `${header}\n${real('2026-01-05', 'Compra', '-8.00', 'Ocio')};extra\n`);
cases.set('columna-de-menos.csv', `${header}\n${row('2026-01-05', 'Compra', '-8.00', 'REAL', 'Ocio', '', '', 'Cuenta principal')}\n`);
cases.set('comillas-mal-cerradas.csv', `${header}\n2026-01-05;"Compra;-8.00;REAL;Ocio;;;;\n`);
cases.set('fila-vacia-intermedia.csv', `${header}\n${real('2026-01-05', 'Compra', '-8.00', 'Ocio')}\n\n${real('2026-01-06', 'Café', '-2.00', 'Ocio')}\n`);
cases.set('fila-final-vacia.csv', `${header}\n${real('2026-01-05', 'Compra', '-8.00', 'Ocio')}\n\n`);
cases.set('utf8-invalido.csv', Buffer.concat([Buffer.from(`${header}\n2026-01-05;`), Buffer.from([0xc3, 0x28]), Buffer.from('; -8.00;REAL;Ocio;;;;\n')]));

// Guarda un manifiesto conciso y legible para que cada archivo tenga intención explícita.
const manifest = {
  version: 1,
  syntheticOnly: true,
  files: [
    ['valido-lf.csv', 'Válido: tres REAL y dos PRESUPUESTO, incluye cero presupuestario.'],
    ['valido-crlf-bom.csv', 'Los mismos registros con BOM UTF-8 y CRLF.'],
    ['valido-comillas-multilinea.csv', 'Válido: ;, comillas duplicadas y salto de línea embebidos.'],
    ['tipo-minusculas-y-espacios.csv', 'Válido: tipo minúsculo y espacios externos eliminables.'],
    ['referencias-renombradas.csv', 'Repetición exacta para comprobar huella idéntica aunque cambie el nombre.'],
    ['dos-reales-iguales.csv', 'Dos movimientos reales idénticos que deben conservar ordinales distintos.'],
    ['bytes-distintos-contenido-similar.csv', 'Bytes distintos con filas visualmente coincidentes para revisión de solapamiento.'],
    ['referencia-ambigua.csv', 'La ruta necesita resolución expresa si coincide con varias referencias.'],
    ['conflicto-padre-descendiente.csv', 'Dos partidas del mismo mes en padre y descendiente: conflicto.'],
    ['conflicto-mes-y-nodo.csv', 'Dos partidas del mismo mes y nodo: conflicto.'],
    ['presupuesto-cuenta-no-permitida.csv', 'PRESUPUESTO con cuenta: error de campo.'],
    ['presupuesto-categoria-ausente.csv', 'PRESUPUESTO sin categoría: error de campo.'],
    ['arbol-incompleto.csv', 'Subcategoría sin categoría raíz: error de jerarquía.'],
    ['fecha-imposible.csv', 'Fecha no existente en el calendario.'],
    ['presupuesto-no-dia-uno.csv', 'PRESUPUESTO fuera del primer día del mes.'],
    ['real-cero-rechazado.csv', 'REAL cero: inválido.'],
    ['presupuesto-cero-admitido.csv', 'PRESUPUESTO cero: válido.'],
    ['cabecera-incorrecta.csv', 'Nombre de cabecera incorrecto.'],
    ['columna-de-mas.csv', 'Registro con diez campos.'],
    ['columna-de-menos.csv', 'Registro con ocho campos.'],
    ['comillas-mal-cerradas.csv', 'Sintaxis CSV no delimitable.'],
    ['fila-vacia-intermedia.csv', 'Registro vacío intermedio.'],
    ['fila-final-vacia.csv', 'Registro vacío tras un salto adicional al final.'],
    ['utf8-invalido.csv', 'Secuencia de bytes UTF-8 inválida.'],
  ].map(([file, purpose]) => ({ file, purpose })),
};
const manifestBytes = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`);

// El modo --check compara la generación determinista y detecta archivos faltantes o alterados.
if (process.argv.includes('--check')) {
  for (const [name, expected] of cases) {
    const actual = await readFile(join(out, name));
    const expectedBytes = Buffer.isBuffer(expected) ? expected : Buffer.from(expected, 'utf8');
    if (!actual.equals(expectedBytes)) throw new Error(`Fixture alterado: ${name}`);
  }
  if (cases.get('valido-lf.csv').split('\n').length !== 7) throw new Error('El fixture válido debe tener cinco registros más cabecera y línea final.');
  if (!(await readFile(join(root, 'manifiesto.json'))).equals(manifestBytes)) throw new Error('Manifiesto alterado');
  console.log(`OK: ${cases.size} fixtures sintéticos reproducibles; huellas/listado listos para revisar.`);
} else {
  await mkdir(out, { recursive: true });
  for (const [name, content] of cases) await writeFile(join(out, name), content);
  await writeFile(join(root, 'manifiesto.json'), manifestBytes);
}
