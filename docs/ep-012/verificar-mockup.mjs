import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const html = readFileSync(new URL('./mockup-importacion.html', import.meta.url), 'utf8');
const elements = new Map();
const events = new Map();
let context;
function field(id) {
  if (!elements.has(id)) elements.set(id, {
    id, value: '', checked: false, disabled: false, innerHTML: '', textContent: '', open: false, isConnected: true,
    focus() { context.document.activeElement = this; },
    showModal() { this.open = true; }, close() { this.open = false; },
    addEventListener(type, callback) { events.set(`${id}:${type}`, callback); },
    setAttribute() {}, classList: { add() {}, remove() {}, toggle() { return true; } },
  });
  return elements.get(id);
}
context = vm.createContext({ Intl, console, setTimeout: callback => callback(),
  document: { getElementById: field, querySelector: field, querySelectorAll: () => [],
    addEventListener(type, callback) { events.set(`document:${type}`, callback); }, activeElement: null },
  window: { addEventListener(type, callback) { events.set(`window:${type}`, callback); } },
  history: { pushState() {} },
});
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
const run = code => vm.runInContext(code, context);
const snapshot = () => run('JSON.stringify({batches,refs})');
const reset = kind => run(`batches=initialBatches();refs=[];failNext=false;staleNext=false;busy=false;newSession('${kind ?? 'mixed'}');`);
const prepare = () => run("bind('account','Cuenta diaria');bind('category','Alimentación / Mercado');session.reviewed=[2,3];session.ack=true;");

// Simulación: comprueba reglas y controladores, no un DOM real ni SQLite.
assert.equal(run('total("REAL","amount")'), -5525n);
assert.equal(run('total("PRESUPUESTO","original")'), 40000n);
assert.equal(run('total("PRESUPUESTO","amount")'), -40000n);
assert.equal(run('ready()'), false);
assert.equal(run('pending().length'), 2);
const untouched = snapshot();
run("bind('account','Cuenta diaria');bind('category','Alimentación / Mercado');");
assert.equal(run('ready()'), false, 'Los avisos bloquean confirmación');
assert.equal(run('category(session.rows[2])'), 'Sin clasificar');
assert.equal(snapshot(), untouched, 'Previsualizar no guarda');
run('session.reviewed=[2]');
assert.equal(run('ready()'), false, 'Hay que revisar cada ordinal');
run('session.reviewed.push(3)');
assert.equal(run('ready()'), true);
run("bind('account','Cuenta ahorro')");
assert.equal(run('overlaps().length'), 0, 'La cuenta forma parte de la comparación');
run("bind('account','Cuenta diaria')");
assert.equal(run('ready()'), false, 'Cambiar asignación invalida las marcas');

for (const kind of ['invalid', 'conflict', 'empty']) {
  reset(kind); prepare();
  const before = snapshot();
  assert.equal(run('commitModel().kind'), 'blocked');
  assert.equal(snapshot(), before, `${kind} rechaza todo`);
  assert.ok(run('review()').includes('No se puede confirmar el lote'));
}
reset();
run("newRef('category');");
field('ref-name').value = 'Raíz nueva'; field('ref-parent').value = ''; field('income').value = '';
run("act('create-ref:category')");
assert.equal(run('session.category'), null, 'Nueva raíz requiere marca expresa');
field('income').value = 'no';
run("act('create-ref:category')");
assert.equal(run('session.plans.category.income'), false, 'Marca explícita independiente del signo');
assert.equal(run('refs.length'), 0);
run("bind('category','Alimentación / Mercado')");
assert.equal(run('session.newRefs.length'), 0, 'Sustituir una asignación descarta su alta preparada');

reset(); prepare();
run("bind('account','Cuenta nueva',true);session.ack=true;failNext=true");
let before = snapshot();
assert.equal(run('commitModel().kind'), 'failed');
assert.equal(snapshot(), before, 'Fallo sin lote ni referencias parciales');
assert.equal(run('session.newRefs[0]'), 'Cuenta nueva');
assert.equal(run('session.ack'), false);
run('session.ack=true');
assert.equal(run('commitModel().kind'), 'confirmed');
assert.equal(run('refs.length'), 1);
assert.equal(run('batches[1].rows.length'), 5, 'Duplicados ordinales se conservan');
assert.equal(run('batches[1].rows[0].ordinal'), 2);
assert.equal(run('batches[1].rows[1].ordinal'), 3);
assert.equal(run('batches[1].rows[3].amount'), -40000, 'No invertir dos veces');
assert.equal(run('batches[1].rows[3].fields.find(f=>f.name==="Importe").value'), '400,00');

reset(); prepare();run('staleNext=true');before=snapshot();
assert.equal(run('commitModel().kind'), 'stale');
assert.equal(snapshot(), before);
assert.equal(run('session.account'), null);
assert.equal(run('session.reviewed.length'), 0);
assert.equal(run('session.rows.length'), 5, 'Cambio concurrente conserva filas');

reset('repeat');run('session.ack=true');before=snapshot();
assert.equal(run('commitModel().kind'), 'already');
assert.equal(snapshot(), before, 'Mismos bytes renombrados: cero altas');
assert.equal(run('batches[0].rows[1].current'), null, 'No recrea borrado');
assert.equal(run('batches[0].rows[2].current.amount'), -42000, 'No revierte corrección');

reset();before=snapshot();run("bind('account','Cuenta nueva',true);go('history');act('dest:Estado')");
assert.equal(field('dialog').open, true, 'Salir del historial también protege sesión');
run("act('close')");assert.ok(run('session'));
run("act('dest:Estado');act('discard')");
assert.equal(run('session'), null);
assert.equal(snapshot(), before, 'Cancelar conserva confirmados');
assert.equal(run('view'), 'origin');

reset();prepare();field('confirm-check').checked=true;
run('confirmDialog()');assert.equal(field('dialog').open,true);
run("act('close')");assert.ok(run('session'));
field('confirm-check').checked=true;
await run('Promise.all([confirmAll(),confirmAll()])');
assert.equal(run('batches.length'), 2, 'Doble envío crea un solo lote');
assert.equal(run('view'), 'result');
run("selectedBatch='LOT-001';page=1;sourceOrdinal=5;go('source')");
assert.match(field('content').innerHTML, /corregido/);
run("act('back-detail')");assert.equal(run('page'),1);
run("sourceOrdinal=3;go('source')");assert.match(field('content').innerHTML,/Registro borrado/);
events.get('window:popstate')();assert.equal(run('view'),'detail');

assert.match(html, /@media\(max-width:839px\)/);
assert.match(html, /aria-labelledby="dialog-title"/);
assert.match(html, /Texto 200/);
console.log('Mockup MA-TSK-108: escenarios y controladores correctos. Sin acreditación de DOM, layout, SQLite ni plataformas nativas.');
