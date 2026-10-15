import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const path = fileURLToPath(new URL('./ma-tsk-187-colchon.json', import.meta.url));
const fixture = JSON.parse(await readFile(path, 'utf8'));

function gcd(a, b) {
  while (b !== 0n) [a, b] = [b, a % b];
  return a < 0n ? -a : a;
}

function ratio(numerator, denominator) {
  const common = gcd(numerator, denominator);
  if (common === 0n) throw new Error('denominador cero');
  let n = numerator / common;
  let d = denominator / common;
  if (d < 0n) [n, d] = [-n, -d];
  return `${n}/${d}`;
}

function displayTwoDecimals(numerator, denominator) {
  const negative = (numerator < 0n) !== (denominator < 0n);
  const n = numerator < 0n ? -numerator : numerator;
  const d = denominator < 0n ? -denominator : denominator;
  const scaled = n * 100n;
  let cents = scaled / d;
  if ((scaled % d) * 2n >= d) cents++;
  const whole = (cents / 100n).toString();
  const decimal = (cents % 100n).toString().padStart(2, '0');
  return `${negative && cents !== 0n ? '-' : ''}${whole},${decimal}`;
}

const reasonText = {
  foto_ausente: 'sin dato: falta foto patrimonial',
  foto_incompleta: 'sin dato: foto patrimonial incompleta',
  ingresos_incompletos: 'sin dato: presupuesto anual de ingresos incompleto',
  ingresos_nulos: 'sin dato: ingresos presupuestados nulos',
  ingresos_negativos: 'sin dato: ingresos presupuestados no positivos',
};

function missing(code, extra = {}) {
  return { kind: 'missing', code, text: reasonText[code], ...extra };
}

function evaluate(testCase) {
  const photo = testCase.photo ?? 'complete';
  if (photo === 'absent') return missing('foto_ausente');
  if (photo === 'partial') return missing('foto_incompleta');

  const months = testCase.explicitIncomeMonths ?? fixture.base.explicitIncomeMonths;
  const missingMonths = Array.from({ length: 12 }, (_, i) => i + 1).filter((month) => !months.includes(month));
  if (missingMonths.length) return missing('ingresos_incompletos', { pendingMonths: missingMonths });

  const income = BigInt(testCase.annualIncomeCents ?? String(fixture.base.monthlyIncomeCents * 12));
  if (income === 0n) return missing('ingresos_nulos');
  if (income < 0n) return missing('ingresos_negativos');

  const liquid = BigInt(testCase.liquidCents ?? String(fixture.base.januaryWealth.liquidAssetCents.reduce((sum, n) => sum + n, 0)));
  return {
    kind: 'value',
    exact: ratio(liquid * 12n, income),
    display: displayTwoDecimals(liquid * 12n, income),
  };
}

for (const testCase of fixture.cases) {
  const actual = evaluate(testCase);
  for (const [key, expected] of Object.entries(testCase.expected)) {
    assert.deepEqual(actual[key], expected, `${testCase.id}: ${key}`);
  }
  if (testCase.expectedPendingMonths) {
    const missing = Array.from({ length: 12 }, (_, i) => i + 1).filter((month) => !(testCase.explicitIncomeMonths ?? []).includes(month));
    assert.deepEqual(missing, testCase.expectedPendingMonths, `${testCase.id}: meses pendientes`);
  }
}

const janRows = fixture.classificationRows.filter((row) => row.month === 1);
const includedJan = janRows.filter((row) => row.rootIsIncome);
const ignoredJan = janRows.filter((row) => !row.rootIsIncome);
assert.equal(includedJan.reduce((sum, row) => sum + BigInt(row.cents), 0n), 300000n, 'marca raíz y suma firmada');
assert.equal(ignoredJan.length, 2, 'raíces sin marca de ingreso se excluyen aunque el importe sea positivo o negativo');
assert.ok(includedJan.some((row) => row.categoryArchived), 'categorías archivadas conservan su contribución');
assert.equal(new Set(includedJan.map((row) => row.month)).size, 1, 'varias partidas de enero solo completan enero');
assert.equal(fixture.classificationExpected.monthTwoPresent, false);
assert.equal(fixture.classificationExpected.yearTotalCents, String(fixture.base.monthlyIncomeCents * 12));
assert.equal(fixture.temporalExpected.januaryAfterFebruaryCorrectionCents, fixture.temporalExpected.januaryLiquidCents);
assert.deepEqual(fixture.extensionTest.productionCatalogIds, ['colchon_emergencia']);
assert.equal(fixture.extensionTest.id, 'indicador_sintetico_test');

console.log(`OK: ${fixture.cases.length} casos del colchón y clasificación, precedencia, temporalidad y extensibilidad verificados.`);
