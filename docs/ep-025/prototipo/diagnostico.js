const $=s=>document.querySelector(s);
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const months=['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
let report=null,revision=42,generation=1,running=false,cancelled=false,readError=false,step=0,timer=null,filter='Todas',selected=null;
const period=()=>`${months[Number($('#month').value)]} de ${$('#year').value}`;
const key=()=>`${$('#year').value}-${String(Number($('#month').value)+1).padStart(2,'0')}`;
const stale=()=>report&&(report.revision!==revision||report.generation!==generation||report.period!==key());
const button=(text,act,primary=false)=>`<button data-act="${act}" class="${primary?'primary':''}">${text}</button>`;
const goButton=(text,path)=>`<button data-go="${path}">${text}</button>`;
const rules=['Integridad local','Referencias persistidas','Presupuestos padre y descendiente','Repetición exacta persistida de importación','Coincidencias entre lotes','Movimientos sin categoría','Foto ausente','Foto incompleta','Disponibilidad del indicador'];
const findings={
 conflict:{severity:'Error',code:'presupuesto_solapado',title:'Dos presupuestos en la misma rama y mes',text:'Vivienda y Vivienda / Alquiler tienen partidas simultáneas en enero de 2026.',evidence:'Partida p-padre: Vivienda, −700,00 €. Partida p-hijo: Vivienda / Alquiler, −700,00 €. Mes: enero de 2026. El conflicto es histórico y pertenece al ámbito de toda la base.',target:'Presupuesto mensual · enero de 2026 · Vivienda · partida p-padre; también se mostrará p-hijo.',route:'/presupuesto/mensual?year=2026&month=1&category=cat-vivienda',owner:'Presupuesto mensual',canEdit:true},
 duplicate:{severity:'Aviso',code:'coincidencia_entre_lotes',title:'Posible duplicado entre dos lotes',text:'Café · Cuenta principal · 5 ene 2026 · −10,00 € · dos archivos distintos.',evidence:'Real r-a, lote lote-a, fila 2; real r-b, lote lote-b, fila 8. Coinciden cuenta, fecha, importe y concepto normalizado. No demuestra duplicidad. Las dos filas legítimas del mismo lote se conservan.',target:'Historial de importaciones · lote-a · fila 2 · real r-a, de enero de 2026.',route:'/importaciones/lote-a',owner:'Detalle del lote lote-a',other:'Historial de importaciones · lote-b · fila 8 · real r-b, de enero de 2026.'},
 movement:{severity:'Pendiente',code:'movimiento_sin_categoria',title:'Movimiento pendiente de categoría',text:'Abono pendiente · Cuenta principal · 10 ene 2026 · +7,00 €.',evidence:'Real r-pendiente, categoría sin asignar, cuenta válida. Es un dato permitido pendiente de completar; no es una referencia rota.',target:'Bandeja de categorización · real r-pendiente · enero de 2026 · Cuenta principal.',route:'/pendientes-categorizacion?movement=r-pendiente',owner:'Bandeja de categorización',canEdit:true},
 photo:{severity:'Pendiente',code:'foto_incompleta',title:'Foto patrimonial incompleta',text:'Falta valorar Cuenta de ahorro y Deuda familiar en la foto del día 1.',evidence:'Fichas vigentes ahorro-1 y deuda-1. No se arrastran saldos ni se calculan desde movimientos. El mes se muestra sin dato hasta completar la foto.',target:()=>`Foto del 1 de ${period().toLowerCase()} · fichas ahorro-1 y deuda-1.`,route:()=>`/patrimonio/foto?year=${$('#year').value}&month=${Number($('#month').value)+1}`,owner:'Foto patrimonial',canEdit:true},
 indicator:{severity:'Pendiente',code:'indicador_sin_dato',title:'Indicador sin dato: ingresos incompletos',text:'El presupuesto de ingresos de marzo está pendiente; el mes elegido no permite mostrar el indicador.',evidence:'Causa recibida de EP-023: ingresos_incompletos. Indicador colchon_emergencia, versión 1. Se presenta la causa prioritaria recibida, sin volver a calcular la fórmula.',target:()=>`Presupuesto de ingresos · marzo de ${$('#year').value} · Ingresos / Salario.`,route:()=>`/presupuesto/mensual?year=${$('#year').value}&month=3&category=cat-salario`,owner:'Presupuesto de ingresos',canEdit:true},
 reference:{severity:'Error',code:'referencia_invalida',title:'Referencia de categoría inexistente',text:'Un movimiento conserva una referencia que ya no se puede resolver.',evidence:'Real r-roto, enero de 2026: category_id=cat-inexistente. No se abrirá el identificador de una categoría inexistente.',target:'Catálogo de categorías · revisar referencia cat-inexistente del real r-roto de enero de 2026.',route:'/categorias',owner:'Catálogo de categorías'}
};
findings.photoIndicator={severity:'Pendiente',code:'indicador_sin_dato',title:'Indicador sin dato: foto incompleta',text:'El indicador no está disponible hasta completar la foto del mes elegido.',evidence:'Causa prioritaria recibida de EP-023: foto_incompleta. Indicador colchon_emergencia, versión 1. Conserva las fichas pendientes ahorro-1 y deuda-1; no calcula una fórmula alternativa.',target:findings.photo.target,route:findings.photo.route,owner:'Foto patrimonial',canEdit:true};
const value=x=>typeof x==='function'?x():x;
$('#month').innerHTML=months.map((m,i)=>`<option value="${i}" ${i===9?'selected':''}>${m}</option>`).join('');
$('#month').onchange=$('#year').onchange=()=>{selected=null;render();};
$('#scale').onclick=()=>document.documentElement.classList.toggle('bigtext');
$('#reset').onclick=()=>location.reload();
function goto(path){location.hash=path;}
function start(){
 if(running)return;
 clearInterval(timer);report=null;running=true;cancelled=false;readError=false;step=0;selected=null;filter='Todas';
 const scenario=$('#scenario').value,requestPeriod=key(),requestLabel=period(),requestRevision=revision,requestGeneration=generation;
 render();
 timer=setInterval(()=>{step++;if(step<4){render();return;}clearInterval(timer);running=false;
  if(scenario==='error'){readError=true;render();return;}
  const ids={mixed:['conflict','reference','duplicate','movement','photo','photoIndicator'],clean:[],pending:['movement','photo','photoIndicator'],income:['indicator'],duplicate:['duplicate'],skipped:[],stale:['movement']}[scenario];
  const items=Object.fromEntries(ids.map(id=>[id,{...findings[id],target:value(findings[id].target),route:value(findings[id].route)}]));
  report={ids,items,period:requestPeriod,label:requestLabel,revision:requestRevision,generation:requestGeneration,date:new Date().toLocaleString('es-ES'),notRun:scenario==='skipped'};
  if(scenario==='stale')revision++;
  render();
 },650);
}
function counts(){return ['Error','Aviso','Pendiente'].map(s=>`<article class="card"><p>${s==='Error'?'Errores':s==='Aviso'?'Avisos':'Pendientes'}</p><div class="value">${report.ids.filter(id=>findings[id].severity===s).length}</div></article>`).join('');}
function meta(){return `<div class="metadata"><span>${esc(report.date)}</span><span>Mes evaluado: ${esc(report.label)}</span><span>Muestra local · revisión ${report.revision} · apertura ${report.generation}</span></div>`;}
function diagnostic(){
 const obsolete=stale();
 let html=`<div class="titleline"><div><div class="eyebrow">Análisis · Revisión manual</div><h1>Diagnóstico de coherencia</h1><p>${period()} · datos locales</p></div>${button(report||readError||cancelled?'Repetir diagnóstico':'Ejecutar diagnóstico','run',true)}</div><div class="scope"><p>Comprueba la estructura de toda la base y los pendientes patrimoniales y del indicador del mes elegido.</p><p class="muted">Solo lectura. Los hallazgos abren su origen para revisarlo. El resultado dura esta sesión; volver a esta pantalla no ejecuta otra revisión.</p></div>`;
 if(running)return html+`<section class="card section" role="status"><h2>Ejecutando diagnóstico</h2><p>${['Preparando lectura coherente','Comprobando estructura de toda la base','Revisando pendientes del mes','Preparando resultados'][step]}</p><progress max="4" value="${step}" aria-label="Progreso del diagnóstico"></progress><p class="muted">${step} de 4 etapas · no se modifican datos</p>${button('Cancelar diagnóstico','cancel')}</section>`;
 if(readError)return html+`<section class="alert error" role="alert"><h2>No se pudo leer la base local</h2><p>No hay un resultado verificable ni recuentos de hallazgos. No se obtuvo la revisión local. Las reglas dependientes no se ejecutaron.</p>${goButton('Abrir Recuperación local','/copias-locales')}</section>`;
 if(!report)return html+`<section class="empty section" role="status"><h2>${cancelled?'Diagnóstico cancelado':'Listo para revisar'}</h2><p>${cancelled?'No se completó la ejecución. Las reglas pendientes quedaron sin ejecutar; no hay resultado conforme.':'Elige el mes y pulsa Ejecutar diagnóstico cuando quieras revisar tus datos.'}</p></section>`;
 html+=(obsolete?`<section class="alert" role="status"><h2>Resultado obsoleto</h2><p>El mes o los datos locales han cambiado desde la ejecución. Este resultado corresponde a ${esc(report.label)}, revisión ${report.revision}. Repite el diagnóstico explícitamente para comprobar la situación actual.</p>${button('Repetir diagnóstico','run',true)}</section>`:'')+meta();
 html+=`<section aria-labelledby="resultTitle"><div class="status-heading"><h2 id="resultTitle">${obsolete?'Resultado anterior':report.notRun?'Revisión incompleta':report.ids.length?'Revisión con hallazgos':'Sin hallazgos'}</h2><span class="tag ${obsolete||report.notRun?'warn':report.ids.length?'':'good'}">${obsolete?'Obsoleto':report.notRun?'8 de 9 reglas ejecutadas':'9 de 9 reglas ejecutadas'}</span></div>`;
 if(!report.ids.length&&!report.notRun)html+=`<p>Las nueve reglas se ejecutaron y no encontraron incidencias${obsolete?' en la ejecución anterior': ' en el ámbito revisado'}. Un mes sin presupuesto es válido; las fotos completas a cero y las referencias archivadas conservadas también.</p>`;
 if(report.notRun)html+=`<div class="no-run section"><h3>Regla no ejecutada: disponibilidad del indicador</h3><p>Proveedor EP-023 no disponible en esta simulación. La regla no equivale a conforme y no es un hallazgo de severidad «pendiente».</p><p class="muted">Puedes repetir el diagnóstico cuando el proveedor esté disponible. Las ocho comprobaciones independientes sí se completaron.</p></div>`;
 html+=`<div class="summary-counts">${counts()}</div><label>Filtrar hallazgos por severidad<select id="severity">${['Todas','Error','Aviso','Pendiente'].map(s=>`<option ${s===filter?'selected':''}>${s}</option>`).join('')}</select></label><div class="groups section">`;
 let visible=0;
 for(const [s,label] of [['Error','Errores'],['Aviso','Avisos'],['Pendiente','Pendientes']]){
  const ids=report.ids.filter(id=>findings[id].severity===s&&(filter==='Todas'||filter===s));if(!ids.length)continue;visible+=ids.length;
  html+=`<section class="group"><h2>${label} · ${ids.length}</h2>${ids.map(id=>{const f=findings[id];return `<article class="card finding"><div><span class="tag ${s==='Error'?'bad':'warn'}">${s}</span><h3>${f.title}</h3><p class="muted">${f.text}</p></div>${button('Ver detalle','detail:'+id)}</article>`;}).join('')}</section>`;
 }
 if(!visible&&report.ids.length)html+='<p role="status">No hay hallazgos con esta severidad. Los recuentos del resumen muestran el total de la ejecución.</p>';
 html+=`</div><details class="coverage card"><summary>Ver cobertura de las nueve reglas</summary>${rules.map((r,i)=>`<div class="rule-row"><span>${r}</span><strong>${report.notRun&&i===8?'No ejecutada · proveedor no disponible':'Ejecutada'}</strong></div>`).join('')}<p class="muted">Las reglas estructurales abarcan toda la base. Fotos e indicador se limitan a ${esc(report.label)}; los ingresos del indicador pertenecen a ese año. No se comparan cifras personales con los casos sintéticos de regresión.</p></details></section>`;
 return html;
}
function detail(){
 const f=report?.items[selected];if(!f)return diagnostic();
 return `<div class="eyebrow">Diagnóstico · Detalle del hallazgo</div><h1>${f.title}</h1><span class="tag ${f.severity==='Error'?'bad':'warn'}">${f.severity}</span>${meta()}${stale()?'<div class="alert">Este resultado está obsoleto. Repite el diagnóstico al volver.</div>':''}<section class="card section"><h2>Qué se ha encontrado</h2><p>${f.evidence}</p><dl class="detail-facts"><dt>Regla</dt><dd>${f.code}</dd><dt>Ámbito</dt><dd>${['photo','indicator','photoIndicator'].includes(selected)?esc(report.label):'Toda la base local; se conserva el periodo propio de cada registro.'}</dd></dl><div class="destination"><h3>Qué se abrirá</h3><p>${esc(value(f.target))}</p></div><p class="muted">Revisa el origen antes de decidir cualquier cambio. El diagnóstico no corrige ni borra registros.</p><div class="actions">${button('Abrir origen','origin',true)}${f.other?button('Abrir segundo lote · lote-b · fila 8','other'):''}${button('Volver a resultados','results')}</div></section>`;
}
function origin(other=false){
 const f=report?.items[selected];
 if(!f)return '<h1>Origen no disponible</h1>'+button('Volver a diagnóstico','results');
 const destination=other?f.other:value(f.target),path=other?'/importaciones/lote-b':value(f.route);
 return `<div class="eyebrow">Destino existente · Simulación de navegación</div><h1>${other?'Detalle del lote lote-b':f.owner}</h1><section class="card section"><h2>Contexto de apertura</h2><p>${esc(destination)}</p><p class="muted route-code">Destino lógico: ${esc(path)}</p><p>La implementación usará la pantalla propietaria y sus validaciones. Aquí solo se muestra el destino con datos ficticios.</p>${selected==='duplicate'?'<p>Los dos movimientos siguen conservados. Puedes revisar los lotes y volver sin modificar nada.</p>':''}${f.canEdit?button('Simular cambio guardado en el editor','change',true):''}${button('Volver al diagnóstico','return')}</section>`;
}
function secondary(management=false){return `<div class="eyebrow">${management?'Herramientas':'Informes'}</div><h1>${management?'Gestión':'<span class="text-pc">Análisis</span><span class="text-mobile">Más</span>'}</h1><p class="muted">Navegación secundaria existente · suplemento centrado en el diagnóstico</p><section class="card section"><h2>Diagnóstico de coherencia</h2><p>Comprueba tus datos locales cuando tú decidas.</p>${goButton('Abrir diagnóstico de coherencia','/diagnostico')}</section>`;}
function recovery(){return `<div class="eyebrow">Gestión · Destino existente</div><h1>Recuperación local</h1><section class="card section"><h2>Proteger y recuperar la base</h2><p>La base no se ha podido leer. Revisa las copias locales desde el flujo de recuperación existente. No se abren editores de registros de una base ilegible.</p><p class="muted">Simulación del destino. No se restaura ni se sustituye ninguna base real.</p>${button('Simular recuperación local completada','recover',true)}${button('Volver al diagnóstico','results')}</section>`;}
function render(){
 let path=location.hash.slice(1)||'/analisis';
 const isDetail=path==='/diagnostico/detalle';
 $('#nav').innerHTML=[['Inicio','/inicio','M3 11 12 3l9 8v10H3z'],['Presupuesto','/presupuesto','M4 3h16v18H4zM8 8h8M8 12h8M8 16h4'],['Movimientos','/movimientos','M3 7h17m-5-4 5 4-5 4M21 17H4m5-4-5 4 5 4'],['Patrimonio','/patrimonio','M4 21V10h4v11m4 0V3h4v18m4 0V7h2v14'],['Análisis','/analisis','M4 20V10m8 10V4m8 16v-7']].map(([n,p,d])=>`<button data-go="${p}" ${path.startsWith('/diagnostico')&&p==='/analisis'||path===p?'aria-current="page"':''}><svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="${d}"/></svg>${n==='Análisis'?'<span class="text-pc">Análisis</span><span class="text-mobile">Más</span>':n}</button>`).join('');
 $('#breadcrumb').innerHTML=path==='/analisis'?'':`<button class="link" data-act="${isDetail?'results':path.startsWith('/origen')?'return':'back'}">← Volver a ${isDetail?'resultados':path.startsWith('/origen')?'diagnóstico':'Análisis'}</button>`;
 $('#content').innerHTML=path==='/diagnostico'?diagnostic():isDetail?detail():path.startsWith('/origen')?origin(path.endsWith('/segundo')):path==='/copias-locales'?recovery():path==='/gestion'?secondary(true):path==='/analisis'?secondary():`<h1>${esc(path.slice(1))}</h1><section class="card section"><p>Destino principal de EP-026 conservado; fuera del alcance de este suplemento.</p>${goButton('Ir a Análisis','/analisis')}</section>`;
 $('#content').dataset.rendered=path;
 if($('#severity'))$('#severity').onchange=e=>{filter=e.target.value;render();$('#severity').focus();};
 $('#month').disabled=$('#year').disabled=running||isDetail||path.startsWith('/origen');
 document.querySelectorAll('[data-act="run"]').forEach(b=>b.disabled=running);
}
document.addEventListener('click',e=>{
 const b=e.target.closest('button');if(!b)return;
 if(b.dataset.go){if(running)return;goto(b.dataset.go);return;}
 const a=b.dataset.act;
 if(a==='run')start();
 if(a==='cancel'){clearInterval(timer);running=false;cancelled=true;render();}
 if(a?.startsWith('detail:')){selected=a.split(':')[1];goto('/diagnostico/detalle');}
 if(a==='results'||a==='return')goto('/diagnostico');
 if(a==='back')goto('/analisis');
 if(a==='origin')goto('/origen');
 if(a==='other')goto('/origen/segundo');
 if(a==='change'){revision++;b.disabled=true;b.textContent='Cambio ficticio guardado · vuelve y repite';}
 if(a==='recover'){generation++;revision++;readError=false;cancelled=true;goto('/diagnostico');}
});
window.addEventListener('hashchange',()=>{if(running){clearInterval(timer);running=false;cancelled=true;}render();$('#content').focus();window.scrollTo(0,0);});
render();
