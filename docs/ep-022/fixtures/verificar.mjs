import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const data = JSON.parse(await readFile(new URL('./referencias.json', import.meta.url), 'utf8'));
assert.equal(data.version, 1);
assert.equal(data.syntheticOnly, true);
const monthIndex = date => Number(date.slice(5, 7)) - 1;
const sum = rows => rows.reduce((total, row) => total + row[3], 0);
const ids = rows => rows.map(row => row[0]).sort();
const F = data.cases.F;

function verifyMovements(testCase, source) {
  const rows = testCase.base ? [...source.movements, ...testCase.addedMovements] : testCase.movements;
  const seen = new Set();
  for (const [id, date, category, cents] of rows) {
    assert(!seen.has(id), `UUID de movimiento repetido: ${id}`);
    seen.add(id);
    assert.match(date, /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/);
    const [year, month, day] = date.split('-').map(Number);
    assert.equal(new Date(Date.UTC(year, month - 1, day)).toISOString().slice(0, 10), date, `fecha calendario ${date}`);
    assert(Number.isSafeInteger(cents) && cents !== 0, `Importe inválido: ${id}`);
    assert(category === null || typeof category === 'string');
  }
  const actualMonths = Array(12).fill(0);
  for (const row of rows) actualMonths[monthIndex(row[1])] += row[3];
  assert.deepEqual(actualMonths, testCase.monthlyTotalCents, `${testCase === F ? 'F' : 'caso'} meses`);
  assert.equal(sum(rows), testCase.annualTotalCents, 'total anual desde UUID de origen');
  for (const [query, expectedIds] of Object.entries(testCase.details ?? {})) {
    let actual;
    if (query.startsWith('ocio-')) actual = rows.filter(row => row[2] === 'ocio-raiz' && monthIndex(row[1]) === 0);
    else if (query.startsWith('unclassified-')) actual = rows.filter(row => row[2] === null && monthIndex(row[1]) === 0);
    else if (query.startsWith('ahorro-')) actual = rows.filter(row => row[2] === 'aho-cuenta' && monthIndex(row[1]) === 0);
    else if (query === 'enero-salario') actual = rows.filter(row => row[2] === 'salario' && monthIndex(row[1]) === 0);
    else if (query === 'enero-impuestos') actual = rows.filter(row => row[2] === 'impuestos' && monthIndex(row[1]) === 0);
    assert.deepEqual(ids(actual), [...expectedIds].sort(), `detalle ${query}`);
  }
}

verifyMovements(F, F);
assert.deepEqual(F.monthlyTotalCents.slice(2), Array(10).fill(0));
assert.deepEqual(F.rootAnnualCents, { ingresos: 612000, vivienda: -200000, alimentacion: -77035, ahorro: -100000, ocio: -2000 });
assert.equal(F.details['ocio-enero'].length, 2); // two identical Café rows remain distinct

const J = data.cases.J;
verifyMovements(J, F);
assert.deepEqual(J.rootAnnualCents, { ingresos: 608000, vivienda: -200000, alimentacion: -78235, ahorro: -99500, ocio: -2000, unclassified: 400 });
assert.equal(J.monthlyTotalCents[0], 122475);
assert.deepEqual(J.details['unclassified-enero'], ['j-003', 'j-004']);
assert.equal(J.directByCategory.supermercado + J.directByCategory['compra-semanal'], -34825);
assert.equal(J.directByCategory.alimentacion + J.directByCategory.supermercado + J.directByCategory['compra-semanal'], -36025);

const K = data.cases.K;
verifyMovements(K, F);
assert.equal(K.monthlyTotalCents[0], 172975);
assert.equal(K.rootAnnualCents.ahorro, -50000); // includes existing transfer outflow and added second leg
assert.deepEqual(K.details['ahorro-enero'], ['f-004', 'k-001']);

const L = data.cases.L;
verifyMovements(L, L);
assert.equal(L.categories.find(category => category.id === 'impuestos').isIncome, true);
assert.equal(L.directByCategory.impuestos, -60000); // sign does not change income classification
assert.equal(L.directByCategory.salario + L.directByCategory.impuestos, 240000);
assert.deepEqual(L.annualDirectByCategoryCents, { salario: 300000, impuestos: -60000, nomina: 0 });
assert.equal(L.monthlyBudgetsCents.everyMonth.nomina + L.monthlyBudgetsCents.everyMonth.impuestos, 240000);
assert.equal(Object.keys(L.monthlyBudgetsCents.everyMonth).length * 12, 24);

const edge = data.cases.limitesYArchivo;
assert.equal(edge.accounts[0].included, true, 'cuentas cerradas siguen incluidas');
assert(edge.categories.every(category => category.status === 'archived'), 'nodos archivados conservan sus referencias');
assert.deepEqual(edge.categories[1].currentPath, ['cat-archivada', 'cat-reubicada'], 'el camino actual se resuelve por UUID');
for (const [year, expected] of Object.entries(edge.yearTotalsCents)) {
  const rows = edge.movements.filter(row => row[1].slice(0, 4) === year);
  assert.equal(sum(rows), expected, `año ${year}`);
  if (year === '2026') assert.deepEqual(ids(rows), [...edge.zeroNetYearHasMovements[year]].sort());
}
assert.equal(edge.movements.find(row => row[0] === 'edge-leap-day')[1], '2024-02-29');
assert.equal(edge.emptyYear.totalCents, 0);
assert.equal(edge.emptyYear.movementCount, 0);

console.log('OK: F/J/K/L, sumas mensuales/anuales, UUID de detalle, nulos, signos y ramas sintéticos.');
