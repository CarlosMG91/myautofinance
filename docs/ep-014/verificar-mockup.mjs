import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const html=readFileSync(new URL('mockup-openbank.html',import.meta.url),'utf8');
const elements=new Map(),events=new Map();let context;
function field(id){if(!elements.has(id))elements.set(id,{value:'',checked:false,disabled:false,innerHTML:'',textContent:'',open:false,isConnected:true,focus(){context.document.activeElement=this;},showModal(){this.open=true;},close(){this.open=false;},addEventListener(type,fn){events.set(`${id}:${type}`,fn);},setAttribute(){},classList:{add(){},remove(){},toggle(){return true;}}});return elements.get(id);}
context=vm.createContext({Intl,console,setTimeout:fn=>fn(),document:{getElementById:field,querySelector:field,querySelectorAll:()=>[],activeElement:null,addEventListener(type,fn){events.set(`document:${type}`,fn);}},window:{addEventListener(type,fn){events.set(`window:${type}`,fn);}},history:{pushState(){}}});
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1],context);
const run=code=>vm.runInContext(code,context),snapshot=()=>run('JSON.stringify({batches,refs})');
const before=snapshot();
assert.equal(run('view'),'select');assert.equal(run('session'),null);
run('openbankSelect();closeDialog();');assert.equal(snapshot(),before);
for(const kind of ['unknown','invalid','empty','read','access','unavailable']){
 run(`openbankApply('${kind}')`);assert.equal(run('view'),'ob-error');assert.equal(run('session'),null);assert.equal(run('ready()'),false);
 assert.ok(field('content').innerHTML.includes('no disponibles'));assert.equal(snapshot(),before);
 run("act('history');act('return-review')");assert.equal(run('view'),'ob-error');
}
run("openbankApply('valid')");assert.equal(run('session.rows.length'),4);assert.equal(run('total("REAL","amount")'),94475n);
assert.equal(run('session.rows.every(r=>r.type==="REAL"&&r.cat===null)'),true);assert.equal(run('ready()'),false);
field('binding').value='Cuenta diaria';field('account-check').checked=false;
run("act('ob-account')");assert.equal(run('session.account'),null);
field('account-check').checked=true;run("act('ob-account')");assert.equal(run('accountConfirmed'),true);
run('session.reviewed=[2]');assert.equal(run('ready()'),false);
run('session.reviewed.push(3)');assert.equal(run('ready()'),true);
const review=run('JSON.stringify(session)');run('openbankSelect();closeDialog()');assert.equal(run('JSON.stringify(session)'),review);
run('openbankSelect()');events.get('dialog:cancel')({preventDefault(){}});assert.equal(field('dialog').open,false);assert.equal(run('JSON.stringify(session)'),review);
// Changing a file asks to discard first; cancelling preserves the session.
await run("openbankDeliver('unknown')");assert.equal(run('JSON.stringify(session)'),review);assert.equal(field('dialog').open,true);
run("act('close')");assert.equal(run('JSON.stringify(session)'),review);
// Changing the account invalidates all overlap acknowledgements.
field('binding').value='Cuenta ahorro';run("act('ob-account')");assert.equal(run('session.reviewed.length'),0);assert.equal(run('overlaps().length'),0);
field('binding').value='Cuenta diaria';run("act('ob-account')");assert.equal(run('ready()'),false);
run('session.reviewed=[2,3];session.ack=true;failNext=true');assert.equal(run('commitModel().kind'),'failed');assert.equal(snapshot(),before);
run('session.ack=true;staleNext=true');assert.equal(run('commitModel().kind'),'stale');assert.equal(run('session.account'),null);assert.equal(run('ready()'),false);
field('binding').value='Cuenta diaria';run("act('ob-account');session.reviewed=[2,3];confirmDialog()");
field('confirm-check').checked=false;await run('confirmAll()');assert.equal(snapshot(),before);
field('confirm-check').checked=true;await run('confirmAll()');assert.equal(run('view'),'result');assert.equal(run('batches.length'),2);
assert.equal(run('batch().rows.length'),4);assert.equal(run('batch().rows[0].ordinal'),2);assert.equal(run('batch().rows[1].ordinal'),3);
const confirmed=snapshot();run("openbankApply('repeat')");assert.equal(run('view'),'already');assert.equal(snapshot(),confirmed);assert.ok(field('content').innerHTML.includes('0 altas'));
run("act('batch:LOT-001');act('source:3')");assert.ok(field('content').innerHTML.includes('Registro borrado'));assert.ok(field('content').innerHTML.includes('no disponibles'));
run("act('back-detail');act('source:2')");assert.ok(field('content').innerHTML.includes('Importe corregido'));
run("openbankApply('valid');act('leave');act('discard')");assert.equal(run('session'),null);assert.equal(snapshot(),confirmed);
run("openbankApply('valid')");assert.equal(run('accountConfirmed'),false);
assert.ok(html.includes('aria-labelledby="dialog-title"'));assert.ok(html.includes('@media(forced-colors:active)'));assert.ok(html.includes('Texto 200 %'));
console.log('OK: selección/cancelación, diagnósticos, total +944,75 €, cuenta explícita por carga, revisión por ordinal, cambio de cuenta, confirmación, fallos/base cambiada, repetición, originales no inventados y retorno. DOM simulado; sin revisión visual o lector XLS.');
