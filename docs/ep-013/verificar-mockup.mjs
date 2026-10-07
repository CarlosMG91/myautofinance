import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const html=readFileSync(new URL('mockup-csv.html',import.meta.url),'utf8');
const elements=new Map(),events=new Map();let context;
function field(id){if(!elements.has(id))elements.set(id,{value:'',checked:false,disabled:false,innerHTML:'',textContent:'',open:false,isConnected:true,focus(){context.document.activeElement=this;},showModal(){this.open=true;},close(){this.open=false;},addEventListener(type,fn){events.set(`${id}:${type}`,fn);},setAttribute(){},classList:{add(){},remove(){},toggle(){return true;}}});return elements.get(id);}
context=vm.createContext({Intl,console,setTimeout:fn=>fn(),document:{getElementById:field,querySelector:field,querySelectorAll:()=>[],activeElement:null,addEventListener(type,fn){events.set(`document:${type}`,fn);}},window:{addEventListener(type,fn){events.set(`window:${type}`,fn);}},history:{pushState(){}}});
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1],context);
const run=code=>vm.runInContext(code,context),snapshot=()=>run('JSON.stringify({batches,refs})');
const before=snapshot();
assert.equal(run('view'),'select');assert.equal(run('session'),null);
run('csvOpenSelector();csvCancel();');assert.equal(run('session'),null);assert.equal(snapshot(),before);
for(const kind of ['read','access','unavailable','utf8','header','quotes','fields','columns','empty']){
 run(`csvApply('${kind}')`);assert.equal(run('view'),'csv-error');assert.equal(run('ready()'),false);assert.equal(run('session'),null);
 assert.ok(field('content').innerHTML.includes('no disponibles'));assert.ok(field('content').innerHTML.includes('disabled'));assert.equal(snapshot(),before);
 run("act('history');act('return-review')");assert.equal(run('view'),'csv-error');
}
assert.equal(run('csvDiagnostics.utf8[0].ordinal'),undefined);
assert.equal(run('csvDiagnostics.quotes[0].ordinal'),3);assert.equal(run('csvDiagnostics.quotes[0].line'),5);
assert.equal(run('csvDiagnostics.fields.length'),5);
run("csvApply('valid');bind('account','Cuenta diaria');bind('category','Alimentación / Mercado');session.reviewed=[2,3];");
assert.equal(run('ready()'),true);assert.equal(run('total("REAL","amount")'),-5525n);assert.equal(run('total("PRESUPUESTO","original")'),40000n);assert.equal(run('total("PRESUPUESTO","amount")'),-40000n);
assert.equal(run('session.rows[3].raw'),'400.00');assert.equal(run('session.rows[3].date'),'2026-01-01');
const sessionBefore=run('JSON.stringify(session)');
run('csvOpenSelector();csvCancel();');assert.equal(run('JSON.stringify(session)'),sessionBefore);assert.equal(run('view'),'review');assert.equal(snapshot(),before);
run('csvOpenSelector();closeDialog();');assert.equal(run('JSON.stringify(session)'),sessionBefore);assert.equal(run('csvChoosing'),false);
run('csvOpenSelector()');let prevented=false;events.get('dialog:cancel')({preventDefault(){prevented=true;}});assert.equal(prevented,true);assert.equal(run('JSON.stringify(session)'),sessionBefore);assert.equal(field('dialog').open,false);
run("csvOpenSelector();csvDeliver('utf8')");assert.equal(run('JSON.stringify(session)'),sessionBefore);assert.equal(field('dialog').open,true);
run("act('close')");assert.equal(run('JSON.stringify(session)'),sessionBefore);
run("csvOpenSelector();csvDeliver('fields');act('discard')");assert.equal(run('session'),null);assert.equal(run('view'),'csv-error');assert.equal(snapshot(),before);
run("csvApply('conflict')");assert.equal(run('ready()'),false);assert.ok(run('issues().length')>0);
run("csvApply('valid');bind('account','Cuenta diaria');bind('category','Alimentación / Mercado');session.reviewed=[2];");assert.equal(run('ready()'),false);
run('session.reviewed.push(3);session.ack=true;failNext=true');assert.equal(run('commitModel().kind'),'failed');assert.equal(snapshot(),before);
run('session.ack=true');assert.equal(run('commitModel().kind'),'confirmed');assert.equal(run('batches.length'),2);
const confirmed=snapshot();run("csvApply('repeat')");assert.equal(run('view'),'already');assert.equal(run('session'),null);assert.equal(snapshot(),confirmed);assert.ok(field('content').innerHTML.includes('Ya importado'));
assert.equal(run('origin.destination'),'Real');assert.equal(run('origin.period'),'enero de 2026');
assert.ok(html.includes('aria-labelledby="dialog-title"'));assert.ok(html.includes('@media(forced-colors:active)'));assert.ok(html.includes('Sin clasificar'));
console.log('OK: selección, cancelación, reemplazo, diagnósticos, signos, bloqueos, atomicidad simulada, repetición y contexto. DOM mínimo; sin validación visual ni lector real.');
