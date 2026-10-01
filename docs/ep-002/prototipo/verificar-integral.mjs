import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

// Ejecuta los manejadores reales; no simula layout, teclado ni eventos táctiles.
const elements=new Map(),handlers={},actions=[];
let document;
const element=id=>{
  if(!elements.has(id))elements.set(id,{id,value:id==='year'?'2026':id==='month'?'1':'',innerHTML:'',textContent:'',open:false,
    addEventListener(){},showModal(){this.open=true;},close(){this.open=false;},
    focus(){document.activeElement=this;},querySelector(){return true;},add(){}});
  return elements.get(id);
};
document={getElementById:element,activeElement:element('origin'),addEventListener(n,fn){handlers[n]=fn;},querySelectorAll(){return actions;}};
const context=vm.createContext({document,structuredClone,Intl,Option:function(){},FormData:class{
  constructor(f){this.f=f;}get(n){return this.f[n]??'';}has(n){return !!this.f[n];}
}});
const dir=new URL('./',import.meta.url);
for(const file of ['data.js','model.js','app.js'])vm.runInContext(fs.readFileSync(new URL(file,dir),'utf8'),context);
const run=s=>vm.runInContext(s,context);
const click=action=>handlers.click({target:{closest:()=>({dataset:{action}})}});
const submit=(id,values)=>element(id).onsubmit({preventDefault(){},target:values});
const snapshot=()=>run('JSON.stringify({records:state.records,photos:state.photos,known:state.known,remote:state.remote,dirty:state.dirty})');
const reset=()=>element('reset').onclick();

// A–F: compara cada registro con el CSV, no solo su cantidad.
const csv=fs.readFileSync(new URL('../../ep-001/historico-ejemplo.csv',dir),'utf8').trim().split(/\r?\n/).slice(1);
const reference=JSON.parse(run('JSON.stringify(REFERENCE)'));
csv.forEach((line,i)=>{
  const [date,concept,amount,type,...rest]=line.split(';');
  const [root,child,leaf,account,discretion]=rest;
  assert.deepEqual(reference[i],{date,concept,amount:Math.round(Number(amount)*100)*(type==='PRESUPUESTO'?-1:1),type,path:[root,child,leaf].filter(Boolean).join(' / '),account,discretion});
});
for(const [month,real] of [[1,122975],[2,109990]]){
  element('month').value=String(month);element('month').onchange();
  assert.equal(run(`M.sum(M.rows(state,'REAL',2026,${month}))`),real);
  assert.equal(run(`M.sum(M.rows(state,'PRESUPUESTO',2026,${month}))`),110000);
}
for(const path of ['Alimentación','Alimentación / Supermercado','Alimentación / Supermercado / Compra semanal']){
  assert.equal(run(`M.sum(M.rows(state,'REAL',2026,1,${JSON.stringify(path)}))`),-35025);
}
element('month').value='1';click('list|REAL|1|Ocio');
assert.equal((element('dialogBody').innerHTML.match(/Café/g)||[]).length,2);
element('cancel').onclick();

// Retorno al disparador original aun al encadenar lista → editor → guardar.
const trigger={dataset:{action:'list|REAL|1|Ocio'},focus(){document.activeElement=this;}};
actions.push(trigger);document.activeElement=trigger;click(trigger.dataset.action);
document.activeElement=element('editTrigger');click('edit|52');
assert.equal(run('origin.action'),trigger.dataset.action);
element('cancel').onclick();assert.equal(document.activeElement,trigger);
const replacement={...trigger,focus(){document.activeElement=this;}};
actions.splice(0,1,replacement);run('restoreFocus(origin)');assert.equal(document.activeElement,replacement);

// D/G: ausencia, parcial, cero, corrección y motivos de indicador.
reset();element('month').value='2';click('photo');
submit('photoForm',{v0:'6200.00',v1:'',v2:'',v3:'4800.00'});
assert.match(run('M.indicator(state,2026,2).reason'),/incompleta/);
click('photo');submit('photoForm',{v0:'6200,00',v1:'0,00',v2:'10500,00',v3:'4800,00'});
assert.equal(run('M.photo(state,"2026-02").net'),1190000);
click('photo');submit('photoForm',{v0:'6300.00',v1:'0.00',v2:'10500.00',v3:'4800.00'});
assert.equal(run('M.photo(state,"2026-02").net'),1200000);
assert.equal(run('M.photo(state,"2026-01").net'),1400000);
const photoBefore=snapshot();click('photo');submit('photoForm',{v0:'-1.00',v1:'0.00',v2:'10500.00',v3:'4800.00'});
assert.equal(snapshot(),photoBefore);element('cancel').onclick();
reset();run('state.records=state.records.filter(r=>!(r.type==="PRESUPUESTO"&&r.path.startsWith("Ingresos")&&r.date==="2026-03-01"))');
assert.match(run('M.indicator(state,2026,1).reason'),/ingresos incompleto/);
for(const [amount,reason] of [[0,/nulos/],[-10000,/no positivos/]]){
  reset();run(`state.records.filter(r=>r.type==='PRESUPUESTO'&&r.path.startsWith('Ingresos')).forEach(r=>r.amount=${amount})`);
  assert.match(run('M.indicator(state,2026,1).reason'),reason);
}
reset();run('state.photos["2026-01"][0]=state.photos["2026-01"][1]=0');assert.equal(run('M.indicator(state,2026,1).value'),0);

// H: cancelación, importes inválidos, desglose y sustitución expresamente confirmada.
reset();click('view|Presupuesto');const beforeProposal=snapshot();click('proposal');element('cancel').onclick();assert.equal(snapshot(),beforeProposal);
click('proposal');const draft=JSON.parse(run('JSON.stringify(M.proposal(state,2027))'));
assert.equal(draft.find(r=>r.date==='2027-02-01'&&r.path==='Alimentación').amount,-43000);
assert.ok(draft.filter(r=>r.date==='2027-03-01').every(r=>r.amount===0));
const values=Object.fromEntries(draft.map((r,i)=>['p'+i,(r.amount/100).toFixed(2)]));
values.p2='incorrecto';submit('proposalForm',values);assert.equal(snapshot(),beforeProposal);
values.p2='-370.00';values.split=true;submit('proposalForm',values);assert.equal(snapshot(),beforeProposal);
element('saveProposal').onclick();assert.equal(run('M.sum(M.rows(state,"PRESUPUESTO",2026))'),1320000);
assert.equal(run('M.rows(state,"PRESUPUESTO",2027,1,"Alimentación")[0].path'),'Alimentación / Supermercado');
assert.equal(run('M.rows(state,"PRESUPUESTO",2027,1,"Alimentación")[0].amount'),-37000);

// J: sin clasificar no es categoría presupuestable; directo y agregado coinciden.
reset();element('pending').onclick();assert.match(element('content').innerHTML,/Real directo: \+4,00 €/);
click('list|PRESUPUESTO|1|Sin clasificar');assert.doesNotMatch(element('dialogBody').innerHTML,/Crear partida/);element('cancel').onclick();
const beforeClassify=snapshot();click('edit|60');element('cancel').onclick();assert.equal(snapshot(),beforeClassify);
click('edit|60');submit('editForm',{date:'2026-01-03',concept:'Abono pendiente',amount:'7.00',path:'Ocio',account:'Cuenta principal',discretion:''});
assert.equal(run('M.sum(M.rows(state,"REAL",2026,1))'),122475);
assert.equal(run('M.sum(M.rows(state,"REAL",2026,1).filter(r=>!r.path))'),-300);
assert.equal(run('M.photo(state,"2026-01").net'),1400000);

// Validación de entrada del editor y precisión monetaria.
for(const amount of ['0.00','1.234','Infinity','99999999999999999999999.00']){
  const before=snapshot();click('newReal');submit('editForm',{date:'2026-01-03',concept:'Prueba',amount,path:'Ocio',account:'Cuenta principal'});assert.equal(snapshot(),before);element('cancel').onclick();
}
assert.equal(run('parseAmount("-12,50")'),-1250);

// C: previsualizar/cancelar no escribe; referencias y solapamientos bloquean.
element('empty').onclick();click('view|Importar CSV');
for(const scenario of ['invalid','unresolved','overlap']){
  const before=snapshot();element('csvScenario').value=scenario;click('importPreview');assert.match(element('dialogBody').innerHTML,/disabled/);element('cancel').onclick();assert.equal(snapshot(),before);
}
element('csvScenario').value='valid';click('importPreview');element('cancel').onclick();assert.equal(run('state.records.length'),0);
click('importPreview');element('confirmImport').onclick();assert.equal(run('state.records.length'),58);
click('importPreview');element('confirmImport').onclick();assert.equal(run('state.records.length'),58);

// I: todas las ramas de error y recuperación permanecen manuales.
reset();click('view|Copia en Drive');
for(const scenario of ['Divergencia','Versión desconocida','Cambio durante publicación','Respuesta perdida','Sin conexión','Autenticación fallida']){
  const before=snapshot();element('driveScenario').value=scenario;click('upload');assert.equal(snapshot(),before);assert.doesNotMatch(element('notice').textContent,/Copia subida/);
}
element('driveScenario').value='Sin copia';const beforeMissing=snapshot();click('download');assert.equal(snapshot(),beforeMissing);
click('upload');assert.equal(run('state.known'),1);assert.match(element('notice').textContent,/Copia subida/);
run('state.records[0].amount+=100;state.dirty=true');const beforeDownload=snapshot();
element('driveScenario').value='Normal';click('download');assert.match(element('dialogBody').innerHTML,/sí; dejarán/);element('cancel').onclick();assert.equal(snapshot(),beforeDownload);
for(const scenario of ['Descarga inválida','Respaldo fallido','Apertura fallida']){
  element('driveScenario').value=scenario;click('download');element('confirmDownload').onclick();assert.equal(snapshot(),beforeDownload);
}
element('driveScenario').value='Normal';click('download');element('confirmDownload').onclick();assert.equal(run('state.dirty'),false);
click('restore');assert.equal(snapshot(),beforeDownload);
console.log('OK MA-TSK-018: CSV por registro, A–J simulados, cancelaciones, errores, propuesta/desglose, recuperación y referencias de foco. No acredita renderizado, teclado real ni tacto.');
