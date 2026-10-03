// Comprobación independiente de la plantilla sintética de EP-001.
// Ejecutar desde cualquier directorio: node docs/ep-001/verificar-casos.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const csv = readFileSync(new URL('./historico-ejemplo.csv', import.meta.url), 'utf8')
  .replace(/^\uFEFF/, '').trimEnd().split(/\r?\n/);
assert.equal(csv.shift(), 'fecha;concepto;importe_eur;tipo;categoria;subcategoria;subsubcategoria;cuenta_origen;discrecionalidad');

function cents(value) {
  assert.match(value, /^-?\d+\.\d{2}$/);
  const negative = value.startsWith('-');
  const [whole, fraction] = value.replace('-', '').split('.');
  return (negative ? -1 : 1) * (Number(whole) * 100 + Number(fraction));
}

const rows = csv.map((line, index) => {
  const fields = line.split(';');
  assert.equal(fields.length, 9, `Fila ${index + 2}`);
  const [date, concept, amount, type, root, child, leaf, account, discretionary] = fields;
  assert.match(date, /^2026-\d{2}-\d{2}$/);
  assert.ok(type === 'REAL' || type === 'PRESUPUESTO');
  return { date, concept, amount: cents(amount) * (type === 'PRESUPUESTO' ? -1 : 1),
    type, root, child, leaf, account, discretionary };
});

const budgets = rows.filter(row => row.type === 'PRESUPUESTO');
const actuals = rows.filter(row => row.type === 'REAL');
const sum = rows => rows.reduce((total, row) => total + row.amount, 0);
const select = (rows, month, root) => rows.filter(row =>
  (!month || row.date.slice(0, 7) === month) && (!root || row.root === root));
const expected = (rows, month, root, value) => assert.equal(sum(select(rows, month, root)), cents(value),
  `${month ?? '2026'} / ${root ?? 'total'}`);

// A: normalización, número de filas y duplicados dentro de una carga.
assert.equal(budgets.length, 48);
assert.equal(actuals.length, 10);
assert.equal(budgets.find(row => row.date === '2026-01-01' && row.root === 'Ingresos').amount, 300000);
assert.equal(budgets.find(row => row.date === '2026-01-01' && row.root === 'Vivienda').amount, -100000);
assert.equal(actuals.filter(row => row.concept === 'Café').length, 2);
assert.equal(new Set(budgets.map(row => `${row.date}/${row.root}/${row.child}/${row.leaf}`)).size, 48);

// B, C, E y F: raíces, meses y totales firmados de las cuatro vistas de flujos.
const roots = [
  ['Ingresos', '3000.00', '36000.00', '3100.00', '3020.00', '6120.00'],
  ['Vivienda', '-1000.00', '-12000.00', '-1000.00', '-1000.00', '-2000.00'],
  ['Alimentación', '-400.00', '-4800.00', '-350.25', '-420.10', '-770.35'],
  ['Ahorro', '-500.00', '-6000.00', '-500.00', '-500.00', '-1000.00'],
  ['Ocio', '0.00', '0.00', '-20.00', '0.00', '-20.00'],
];
for (const [root, monthlyBudget, yearlyBudget, januaryActual, februaryActual, yearlyActual] of roots) {
  for (let month = 1; month <= 12; month++) {
    expected(budgets, `2026-${String(month).padStart(2, '0')}`, root, monthlyBudget);
  }
  expected(budgets, null, root, yearlyBudget);
  expected(actuals, '2026-01', root, januaryActual);
  expected(actuals, '2026-02', root, februaryActual);
  expected(actuals, null, root, yearlyActual);
}
expected(budgets, '2026-01', null, '1100.00');
expected(actuals, '2026-01', null, '1229.75');
expected(actuals, '2026-02', null, '1099.90');
expected(budgets, null, null, '13200.00');
expected(actuals, null, null, '2329.65');
assert.equal(sum(select(actuals, '2026-01')) - sum(select(budgets, '2026-01')), cents('129.75'));
assert.equal(sum(select(actuals, '2026-02')) - sum(select(budgets, '2026-02')), cents('-0.10'));
assert.equal(actuals.filter(row => row.discretionary === 'Discrecional').length, 4);

// D y G: foto manual, patrimonio y colchón. No se derivan saldos del CSV.
const snapshot = { current: 600000, savings: 300000, portfolio: 1000000, debt: 500000 };
const liquid = snapshot.current + snapshot.savings;
assert.equal(liquid, 900000);
assert.equal(liquid + snapshot.portfolio - snapshot.debt, 1400000);
const annualIncome = sum(select(budgets, null, 'Ingresos'));
assert.equal(annualIncome, 3600000);
assert.equal(liquid * 12 / annualIncome, 3);

// H: sugerencia por raíz y mes equivalente, redondeando magnitud a la decena superior.
function proposal(amount) {
  return Math.sign(amount) * Math.ceil(Math.abs(amount) / 1000) * 1000;
}
assert.equal(proposal(sum(select(actuals, '2026-01', 'Alimentación'))), cents('-360.00'));
assert.equal(proposal(sum(select(actuals, '2026-02', 'Alimentación'))), cents('-430.00'));
assert.equal(proposal(sum(select(actuals, '2026-01', 'Ingresos'))), cents('3100.00'));
assert.equal(proposal(sum(select(actuals, '2026-03', 'Ingresos'))), 0);

// Variante independiente D: referencia numérica, no prueba de persistencia.
const historicalPortfolio = [
  { from: '2026-01-01', until: '2026-02-01', liquidity: 'medium' },
  { from: '2026-02-01', until: null, liquidity: 'liquid' },
];
const classificationAt = month => historicalPortfolio.filter(period =>
  period.from <= month && (period.until === null || month < period.until));
assert.equal(classificationAt('2026-01-01').length, 1);
assert.equal(classificationAt('2026-02-01').length, 1);
assert.equal(classificationAt('2026-01-01')[0].liquidity, 'medium');
assert.equal(classificationAt('2026-02-01')[0].liquidity, 'liquid');
assert.equal(liquid * 12 / annualIncome, 3); // Enero permanece igual.
const februaryAccounts = cents('6200.00') + cents('0.00');
const februaryPortfolio = cents('10500.00');
const februaryAssets = februaryAccounts + februaryPortfolio;
assert.equal(februaryAssets, cents('16700.00'));
assert.equal(februaryAssets - cents('4800.00'), cents('11900.00'));
assert.equal((februaryAssets * 12 / annualIncome).toFixed(2), '5.57');
assert.equal((februaryAccounts * 12 / annualIncome).toFixed(2), '2.07');

// L/M (EP-008): referencia numérica independiente, no prueba de traslados SQL.
// Reales directos de SALARIO y su descendiente IMPUESTOS; partidas hermanas
// de NÓMINA e IMPUESTOS. El tipo de raíz no determina ni cambia sus signos.
const salaryActual = cents('3000.00');
const taxActual = cents('-600.00');
const branchActual = salaryActual + taxActual;
const branchMonthlyBudget = cents('3000.00') + cents('-600.00');
const branchAnnualBudget = branchMonthlyBudget * 12;
assert.equal(branchActual, cents('2400.00'));
assert.equal(branchMonthlyBudget, cents('2400.00'));
assert.equal(branchActual - branchMonthlyBudget, 0);
assert.equal(branchAnnualBudget, cents('28800.00'));
assert.equal(branchAnnualBudget / 12, cents('2400.00'));
// Contribuciones esperadas a incomeOnly según la marca actual de la raíz.
// Traslado bajo Salida: cero partidas de ingreso, no doce ceros explícitos.
const contributions = [
  { label: 'INGRESOS/SALARIO', income: true, count: 24, amount: 2880000 },
  { label: 'GASTOS/SALARIO', income: false, count: 0, amount: 0 },
  { label: 'SALARIO promovida desde INGRESOS', income: true, count: 24, amount: 2880000 },
  { label: 'SALARIO promovida desde GASTOS', income: false, count: 0, amount: 0 },
];
for (const variant of contributions) {
  assert.equal(variant.income ? 24 : 0, variant.count, variant.label);
  assert.equal(variant.income ? branchAnnualBudget : 0, variant.amount, variant.label);
}

console.log('EP-001: 48 presupuestos, 10 reales; enero +1.229,75 €, real anual +2.329,65 €, presupuesto anual +13.200,00 €; liquidez histórica enero 3,00 y febrero 5,57 meses. EP-008 L/M: salario e impuestos +2.400,00 €/mes, +28.800,00 €/año, signos conservados. OK');
