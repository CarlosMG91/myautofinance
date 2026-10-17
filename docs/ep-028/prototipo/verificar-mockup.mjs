import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

// Verifica la máquina de estados del HTML; no equivale a un navegador ni a Inno.
const html=readFileSync(new URL('./instalador-v1.html',import.meta.url),'utf8');
const fields=new Map();
let buttons=[];
class Element {
  constructor(id){this.id=id;this.hidden=false;this.checked=false;this.disabled=false;this.textContent='';this.open=false;this.attrs={};}
  set innerHTML(value){
    this.html=value;
    if(this.id==='content'){
      for(const [id] of fields)if(!fixed.has(id))fields.delete(id);
      for(const m of value.matchAll(/id="([^"]+)"/g))fields.set(m[1],new Element(m[1]));
    }
  }
  get innerHTML(){return this.html;}
  setAttribute(k,v){this.attrs[k]=v;}
  focus(){this.focused=true;}
  showModal(){this.open=true;}
  close(){this.open=false;}
  append(e){if(e.dataset?.journey)buttons.push(e);}
}
const fixed=new Set([...html.slice(0,html.indexOf('<script>')).matchAll(/id="([^"]+)"/g)].map(m=>m[1]));
for(const id of fixed)fields.set(id,new Element(id));
const context=vm.createContext({document:{
  getElementById:id=>fields.get(id)||null,
  createElement:()=>{const e=new Element();e.dataset={};return e;},
  querySelectorAll:s=>s==='nav button'?buttons:[],
  addEventListener(){},
  documentElement:{classList:{toggle:()=>true}},
}});
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1],context);
const run=s=>vm.runInContext(s,context);
const click=()=>run('next()');
const choose=s=>run(`choose('${s}')`);
const id=()=>run('current()');
const text=()=>fields.get('content').innerHTML;
for(const flow of ['install','adoption','update','repair','uninstall']){
  choose(flow);
  let visited=[];
  while(id()!=='exit'){
    visited.push(id());
    assert.ok(visited.length<12);
    click();
  }
  assert.match(fields.get('launchResult').textContent,/no se habría abierto/);
  assert.ok(visited.includes('progress'));
  assert.ok(visited.includes({install:'done',adoption:'done',update:'updated',repair:'repaired',uninstall:'removed'}[flow]));
}
choose('adoption');click();click();
assert.equal(id(),'adopt');assert.equal(fields.get('consent').checked,false);
assert.match(text(),/11111111-1111-4111-8111-111111111111/);
assert.match(text(),/María López/);
fields.get('consent').checked=true;click();
assert.match(fields.get('transferSummary').textContent,/autorizada/);
run("$('back').onclick()");assert.equal(fields.get('consent').checked,true);
fields.get('consent').checked=false;click();assert.match(fields.get('transferSummary').textContent,/sin transferencia/);
choose('conflict');click();assert.match(fields.get('transferSummary').textContent,/conserva la sesión del destino/);
choose('unknown');assert.match(text(),/No se elegirá una sesión/);click();assert.equal(run('consent'),false);
choose('open');click();assert.equal(id(),'open');assert.match(fields.get('openStatus').textContent,/sigue abierto/);
fields.get('simulateClosed').onclick();click();assert.equal(id(),'update');
choose('downgrade');assert.match(text(),/No se ha iniciado la instalación/);click();assert.equal(id(),'exit');
choose('install');run('askCancel()');assert.equal(fields.get('confirmCancel').open,true);
fields.get('continue').onclick();assert.equal(id(),'welcome');
run('askCancel()');fields.get('confirmStop').onclick();assert.equal(id(),'cancelled');assert.match(fields.get('cancelledDetail').textContent,/no se inició/);
choose('update');click();assert.equal(id(),'progress');run('askCancel()');fields.get('confirmStop').onclick();assert.match(fields.get('cancelledDetail').textContent,/parcialmente/);
choose('failure');assert.match(text(),/No se ha completado/);assert.equal(fields.get('launch'),undefined);
choose('restart');assert.match(text(),/aún no está completada/);assert.equal(fields.get('launch'),undefined);
choose('install');click();fields.get('desktop').checked=true;click();assert.match(fields.get('accessSummary').textContent,/escritorio/);click();click();
assert.equal(fields.get('launch').checked,false);fields.get('launch').checked=true;click();assert.match(fields.get('launchResult').textContent,/por tu elección/);
choose('signature');assert.match(text(),/sin firma digital/);assert.match(text(),/no demuestra su autoría/);
assert.equal(/https?:\/\//.test(html),false,'Artefacto autocontenido, sin recursos externos');
assert.match(html,/:focus-visible/);assert.match(html,/@media\(forced-colors:active\)/);assert.match(html,/Texto al 200/);
console.log('Correcto: cinco recorridos, consentimiento y retirada, aislamiento de sesiones, cierre/reintento, downgrade, cancelación antes/después de cambios, fallo, reinicio y apertura voluntaria. Sin navegador ni instalación nativa.');
