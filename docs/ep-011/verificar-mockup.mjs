import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const html = readFileSync(new URL('./mockup-presupuesto.html', import.meta.url), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const elements = new Map();
const field = id => {
  if (!elements.has(id)) elements.set(id, {
    id, value: '', textContent: '', innerHTML: '', open: false,
    focus() { context.document.activeElement = this; }, append() {},
    showModal() { this.open = true; }, close() { this.open = false; },
    setAttribute() {}, addEventListener() {}, classList: { toggle() {}, add() {}, remove() {} },
  });
  return elements.get(id);
};
const context = vm.createContext({ Intl, console,
  document: { getElementById: field, querySelectorAll: () => [], addEventListener() {},
    createElement: () => field('created'), activeElement: null },
  window: { scrollY: 37, scrollTo() {}, addEventListener() {} },
  history: { pushState() {} }, location: { hash: '' },
});
vm.runInContext(script, context);
const run = code => vm.runInContext(code, context);
const fresh = () => run("budgets=clone(fixture);sequence=10;failNext=false;dirty=false;cell=null;editing=null;view='list';month='2026-10';error='';pending=null;origin=null;");
const snapshot = () => run('JSON.stringify(budgets)');
// El harness comprueba modelo y controladores de simulación, no layout ni DOM real.
run('render=()=>{};');
for (const b of JSON.parse(run('JSON.stringify(fixture)'))) {
  run(`validate(${JSON.stringify(b)})`);
}
assert.equal(run("aggregate('food','2026-10')"), -40000);
assert.equal(run("aggregate('income','2026-10')"), 250000);
assert.equal(run("aggregate('food','2026-12')"), null);
assert.equal(run("aggregate('leisure','2026-10')"), 0);
assert.equal(run("path('tax')"), 'Ingresos / Salario / Impuestos');
assert.equal(run("income('tax')"), true);
assert.notEqual(run("path('coffee')"), run("path('work-coffee')"));
assert.equal(run("budgets.filter(b=>b.month==='2026-10').reduce((s,b)=>s+b.amount,0)"), 120000);
for (const [raw, cents] of [['−12,34', -1234], ['+20.5', 2050], ['0', 0], ['-0.00', 0]]) {
  assert.equal(run(`parseAmount(${JSON.stringify(raw)})`), cents);
}
for (const raw of ['', '1.234,00', '1,234', 'x', '1e3']) {
  assert.throws(() => run(`parseAmount(${JSON.stringify(raw)})`));
}
const unchanged = snapshot();
for (const d of [
  { month: '2026-10', cat: 'home', amount: -70000 },
  { month: '2026-11', cat: 'market', amount: 0 },
  { month: '2026-10', cat: 'tax', amount: -20000 },
]) {
  assert.throws(() => run(`commit(${JSON.stringify(d)})`), /Conflicto.*2026.*borrador/);
  assert.equal(snapshot(), unchanged);
}
assert.throws(() => run("commit({month:'2026-10',cat:'market',amount:0})"), /Ya hay una partida/);
assert.throws(() => run("commit({month:'2026-13',cat:'work',amount:0})"), /mes válido/);
assert.throws(() => run("commit({month:'2026-12',cat:'old',amount:0})"), /archivada/);
run("commit({month:'2026-12',cat:'home',amount:0});commit({month:'2026-10',cat:'work-coffee',amount:150});");
assert.equal(run("income('work-coffee')"), false, 'El signo excepcional no cambia tipo');
assert.equal(run("aggregate('home','2026-12')"), 0);
fresh();
const metadata = run("JSON.stringify(budgets.find(b=>b.id==='b4').meta)");
run("commit({id:'b4',month:'2026-12',cat:'work-coffee',amount:12345});");
assert.equal(run("JSON.stringify(budgets.find(b=>b.id==='b4').meta)"), metadata);
assert.equal(run("budgets.find(b=>b.id==='b4').cat"), 'work-coffee');
run("commit({id:'b8',month:'2026-12',cat:'old',amount:0})");
assert.equal(run("budgets.find(b=>b.id==='b8').amount"), 0, 'Permite corregir histórico archivado');
fresh();
run("cell={id:'b4',cat:'market',raw:'-333,25'};dirty=true;failNext=true;saveCell();");
assert.equal(run('cell.raw'), '-333,25');
assert.equal(run('dirty'), true);
assert.equal(run("budgets.find(b=>b.id==='b4').amount"), -32000);
assert.match(run('error'), /borrador/);
run('saveCell()');
assert.equal(run("budgets.find(b=>b.id==='b4').amount"), -33325);
assert.equal(run('dirty'), false);
assert.equal(run('cell'), null);
fresh();
run("cell={cat:'home',raw:'-800'};dirty=true;saveCell();");
assert.match(run('error'), /Hogar.*Hogar \/ Alquiler/);
assert.equal(run('cell.raw'), '-800');
assert.equal(snapshot(), unchanged);
run('cancelCell()');
assert.equal(run("document.getElementById('confirm').open"), true);
run('closeAsk()');
assert.equal(run('cell.raw'), '-800', 'Cancelar diálogo conserva borrador');
run('cancelCell();document.getElementById("confirm-action").onclick()');
assert.equal(run('cell'), null, 'Descartar celda no falla ni elimina partida');
assert.equal(snapshot(), unchanged);
fresh();
run("openForm('market','b4');draft.month='2026-12';draft.cat='local';draft.raw='0';dirty=true;failNext=true;saveForm();");
assert.equal(run('draft.month'), '2026-12');
assert.equal(run('draft.cat'), 'local');
assert.equal(run('draft.raw'), '0');
assert.equal(snapshot(), unchanged);
run('saveForm()');
assert.equal(run("budgets.find(b=>b.id==='b4').month"), '2026-12');
assert.equal(run("budgets.find(b=>b.id==='b4').amount"), 0);
assert.equal(run("JSON.stringify(budgets.find(b=>b.id==='b4').meta)"), metadata);
assert.equal(run('month'), '2026-10', 'Volver conserva mes de origen');
assert.equal(run("budgets.filter(b=>b.id==='b4').length"), 1, 'Reintento no duplica');
fresh();
run("openForm('leisure','b6');deletePart();closeAsk();");
assert.equal(run("budgets.some(b=>b.id==='b6')"), true);
run('deletePart();failNext=true;document.getElementById("confirm-action").onclick()');
assert.equal(run("budgets.some(b=>b.id==='b6')"), true);
assert.match(run('error'), /se conserva/);
run('deletePart();document.getElementById("confirm-action").onclick()');
assert.equal(run("budgets.some(b=>b.id==='b6')"), false);
assert.equal(run("aggregate('leisure','2026-10')"), null);
fresh();
assert.match(run('renderList()'), /Subtotal de rama/);
assert.match(run('renderList()'), /0,00.*registrado/);
run("readState='read'");
assert.doesNotMatch(run('renderList()'), /<table>/);
assert.match(run('renderList()'), /Reintentar/);
run("readState='loading'");
assert.doesNotMatch(run('renderList()'), /<table>/);
console.log('OK · presupuesto mensual: fixtures válidos, cifras, signos, cero/ausencia, ambos conflictos, histórico, metadatos, edición, cancelación, borrado, fallos y reintento. No verifica navegador ni Flutter.');
