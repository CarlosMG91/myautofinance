import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const html = readFileSync(new URL('./mockup-movimientos.html', import.meta.url), 'utf8');
const source = html.match(/<script>([\s\S]*?)<\/script>/)[1];
// DOM mínimo: verifica el modelo y recorridos de la simulación, no layout ni SQLite.
const fields = new Map();
function field(selector) {
  if (!fields.has(selector)) fields.set(selector, {
    value: '', checked: false, hidden: true, textContent: '', innerHTML: '',
    focus() {}, setAttribute() {}, append() {},
  });
  return fields.get(selector);
}
const sandbox = vm.createContext({
  document: { querySelector: field, querySelectorAll: () => [], title: '', activeElement: null },
  window: { scrollY: 180, scrollTo() {} }, structuredClone,
});
vm.runInContext(source.slice(0, source.indexOf('// Rutas secundarias simuladas')), sandbox);
vm.runInContext(`renderList=()=>{}; list=()=>{screen='list';dirty=false};
  returnFromDraft=()=>{screen='list'};
  ask=(title,body,label,fn,conservative)=>{globalThis.review={title,body,label,fn,conservative}};`, sandbox);
const run = code => vm.runInContext(code, sandbox);
const ids = () => run('query().map(r=>r.id).join(",")');
function fresh() { run('reset()'); }
function filter(code) { run(code); }
fresh();
assert.equal(ids(), 'm1,m2,m3,m4');
assert.equal(run('query().reduce((s,r)=>s+r.amount,0)'), 1750);
assert.equal(run('visible().map(r=>r.id).join(",")'), 'm1,m2');
filter("filters.search='CAFE'");
assert.equal(ids(), 'm1,m2,m3');
assert.equal(run('query().reduce((s,r)=>s+r.amount,0)'), 2050);
filter("filters.search='arbol'"); assert.equal(ids(), 'm4');
filter("filters.search='regalo'"); assert.equal(ids(), '');
filter("filters.search='';filters.category='c';filters.mode='direct'"); assert.equal(ids(), 'm1');
filter("filters.mode='branch'"); assert.equal(ids(), 'm1,m2,m3');
filter("filters.account='a1'"); assert.equal(ids(), 'm1,m2');
filter("filters.category='';filters.mode='unclassified';filters.account=''"); assert.equal(ids(), '');
filter("filters.from=filters.to='2026-04'"); assert.equal(ids(), 'm5');
assert.equal(run('query().reduce((s,r)=>s+r.amount,0)'), -200);
fresh();
const initial = run('JSON.stringify(rows)');
run("selected=new Set(['m1','m3']);");
field('#reject').checked = true;
assert.equal(run("batch('assign',[...selected],'d')"), false);
assert.equal(run('JSON.stringify(rows)'), initial);
assert.equal(run('[...selected].join(",")'), 'm1,m3');
assert.equal(run("batch('delete',['m1','unknown'])"), false);
assert.equal(run('JSON.stringify(rows)'), initial);
assert.equal(run("batch('assign',['m1','m3'],'missing')"), false);
assert.equal(run('JSON.stringify(rows)'), initial);
assert.equal(run("batch('assign',[...selected],'d')"), true);
assert.equal(run("rows.filter(r=>['m1','m3'].includes(r.id)).every(r=>r.category==='d')"), true);
assert.equal(run("JSON.stringify(rows.map(({category,...r})=>r))"), JSON.stringify(JSON.parse(initial).map(({category,...r})=>r)));
fresh();
run("selected=new Set(visible().map(r=>r.id));selectionMode='page';confirmDelete([...selected])");
assert.match(run('review.title'), /2 movimientos/);
assert.match(run('review.body'), /página visible capturada/);
assert.equal(run('JSON.stringify(rows)'), initial, 'No escribe antes de confirmar');
run('review.fn()'); assert.equal(ids(), 'm3,m4');
assert.equal(run('selected.size'), 0);
fresh();run("confirmDelete(['m2'],true)");
assert.match(run('review.title'), /1 movimiento/);
assert.match(run('review.body'), /acción individual/);
assert.equal(run('JSON.stringify(rows)'), initial);
run('review.fn()'); assert.equal(ids(), 'm1,m3,m4');
fresh();run("batch('remove',['m2','m3'])");
assert.equal(run("rows.find(r=>r.id==='m2').category"), null);
assert.equal(run("rows.find(r=>r.id==='m2').discretion"), 'regalo');
assert.match(run("rows.find(r=>r.id==='m2').source"), /r1/);
fresh();run("editing='m2';screen='editor';dirty=true");
field('#date').value = '2026-03-31';field('#concept').value = 'café';
field('#amount').value = '12,50';field('#editAccount').value = 'a1';
field('#editCategory').value = 'c1';field('#discretion').value = '  opcional  ';
field('#reject').checked = true;run('save()');
assert.equal(run('JSON.stringify(rows)'), initial);
assert.equal(run('dirty'), true);assert.equal(field('#discretion').value, '  opcional  ');
run('save()');assert.equal(run("rows.find(r=>r.id==='m2').discretion"), 'opcional');
assert.match(run("rows.find(r=>r.id==='m2').source"), /r1/);
const before = run("rows.find(r=>r.id==='m2')");
assert.equal(before.account, 'a1');assert.equal(before.amount, 1250);assert.equal(before.date, '2026-03-31');
assert.equal(run("parseAmount('−12,50')"), -1250);
assert.equal(run("parseAmount('+12.5')"), 1250);
for (const amount of ['0','1,001','1.000,00','abc','999999999999999999999']) assert.equal(run(`parseAmount(${JSON.stringify(amount)})`), null);
field('#date').value = '2026-02-30';run('save()');assert.match(field('#formError').textContent, /fecha/);
run("dirty=true;globalThis.didLeave=false;leave(()=>{didLeave=true})");
assert.equal(run('didLeave'), false);assert.equal(run('dirty'), true);
assert.equal(run('review.conservative'), 'Seguir editando');
run('review.fn()');assert.equal(run('didLeave'), true);assert.equal(run('dirty'), false);
// Filtros/contexto se conservan al volver; la página se limpia solo al cambiarla.
fresh();run("filters.search='CAFE';selected=new Set(['m1']);listFocus='open-pc-m1';rememberList();list(true)");
assert.equal(run('filters.search'), 'CAFE');assert.equal(run('selected.has("m1")'), true);
assert.equal(run('listScroll'), 180);
assert.match(html, /@container\(max-width:839px\)/);
assert.match(html, /aria-labelledby="modalTitle"/);
assert.match(html, /beforeunload/);assert.match(html, /popstate/);
console.log('Correcto: casos MA-TSK-087 de lectura, subtotal global/página, selección, confirmaciones, rechazo atómico, conservación de campos/procedencia, borrador, errores, formato y contexto. Layout, teclado real, lector y Android quedan sin verificar.');
