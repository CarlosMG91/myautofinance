/* Solo representación de fixtures sintéticas; no calcula informes ni escribe datos. */
const eur = value => (value < 0 ? '−' : value > 0 ? '+' : '') + Math.abs(value).toLocaleString('es-ES', {useGrouping:'always',minimumFractionDigits:2, maximumFractionDigits:2}) + ' €';
const magnitude = value => value.toLocaleString('es-ES', {useGrouping:'always',minimumFractionDigits:2, maximumFractionDigits:2}) + ' €';
const barCases = {normal:{real:-350.25,budget:-400},mixto:{real:30,budget:-400},cero:{real:0,budget:0},ausente:{real:-20,budget:null}};
function renderBars(){
  const {real,budget} = barCases[document.querySelector('#barra-caso').value];
  const bar = (value,y,kind) => value === null ? '' : value === 0 ? `<circle cx="260" cy="${y+9}" r="4" class="${kind}"/>` : `<rect x="${260+Math.min(0,value)*.38}" y="${y}" width="${Math.abs(value)*.38}" height="18" class="${kind}"/>`;
  document.querySelector('#barras').innerHTML = `<svg viewBox="0 0 520 150" role="img" aria-labelledby="bars-title"><title id="bars-title">Alimentación, enero 2026, EUR. Real ${eur(real)}; presupuesto ${budget===null?'sin presupuesto':eur(budget)}.</title><line x1="70" x2="450" y1="108" y2="108" class="plot-axis"/><line x1="260" x2="260" y1="18" y2="108" class="plot-zero"/><text x="4" y="39">Real</text><text x="4" y="80">Previsto</text>${bar(real,25,'bar-real')}${bar(budget,66,'bar-budget')}${budget===null?'<text x="280" y="80">Sin presupuesto</text>':''}<text x="70" y="135" text-anchor="middle">−500 €</text><text x="260" y="135" text-anchor="middle">0 €</text><text x="450" y="135" text-anchor="middle">+500 €</text></svg><table><caption>Alternativa textual · Alimentación, enero de 2026 · EUR</caption><thead><tr><th scope="col">Serie</th><th scope="col">Importe firmado</th></tr></thead><tbody><tr><th scope="row">Real (relleno petróleo)</th><td>${eur(real)}</td></tr><tr><th scope="row">Presupuesto (violeta)</th><td>${budget===null?'Sin presupuesto':eur(budget)}</td></tr></tbody></table>`;
  document.querySelector('#barras-texto').textContent = budget===null?'No dibujar una partida ficticia en cero.':'Longitudes en escala compartida; ambos signos conservados, sin porcentajes.';
}
const series = [{month:'Ene',value:14000},{month:'Feb',value:null},{month:'Mar',value:null},{month:'Abr',value:14500}];
function renderSeries(){
  const x = i => 72+i*125, y = n => 140-n/20000*110;
  // Solo unir muestras adyacentes válidas. Ningún tramo puede cruzar un null.
  const segments = series.slice(1).map((d,i)=>d.value!==null && series[i].value!==null?`<line data-segment="${i}" x1="${x(i)}" x2="${x(i+1)}" y1="${y(series[i].value)}" y2="${y(d.value)}" stroke="var(--series-asset)" stroke-width="2"/>`:'').join('');
  document.querySelector('#serie').innerHTML = `<svg viewBox="0 0 520 190" role="img" aria-labelledby="series-title"><title id="series-title">Patrimonio neto en EUR, fotos del día 1, enero a abril de 2026. Enero 14.000,00 euros; febrero y marzo sin dato; abril sintético 14.500,00 euros.</title><text x="8" y="33">20.000 €</text><text x="8" y="88">10.000 €</text><text x="8" y="144">0 €</text><line x1="68" x2="465" y1="140" y2="140" class="plot-axis"/>${segments}${series.map((d,i)=>`<text x="${x(i)}" y="174" text-anchor="middle">${d.month}</text>${d.value===null?`<text x="${x(i)}" y="118" text-anchor="middle">Sin dato</text>`:`<circle data-value="${d.value}" class="point" cx="${x(i)}" cy="${y(d.value)}" r="6"/>`}`).join('')}</svg><table><caption>Fotos del día 1 · 2026 · patrimonio neto EUR</caption><thead><tr><th scope="col">Mes</th><th scope="col">Valor</th></tr></thead><tbody>${series.map(d=>`<tr><th scope="row">${d.month}</th><td>${d.value===null?'Sin dato':magnitude(d.value)}</td></tr>`).join('')}</tbody></table>`;
}
const photos = {
  completa:{complete:true,values:[6000,3000,10000],total:19000,debt:5000},
  incompleta:{complete:false,values:[6000,null,10000],total:null,debt:5000},
  cero:{complete:true,values:[0,0,0],total:0,debt:5000},
  invalida:{complete:true,values:[-10,3000,10000],total:12990,debt:5000},
  incoherente:{complete:true,values:[6000,3000,10000],total:20000,debt:5000}
};
function renderDistribution(){
  const p=photos[document.querySelector('#foto-caso').value];
  const valid=p.complete && p.values.every(v=>Number.isFinite(v)&&v>=0) && Number.isFinite(p.total) && p.total>0 && Math.abs(p.values.reduce((a,b)=>a+b,0)-p.total)<.005;
  const target=document.querySelector('#distribucion');
  if(!p.complete){target.innerHTML='<p class="notice warning">Sin dato · foto incompleta. Falta Cuenta de ahorro. Activos, deudas y neto: sin dato.</p>';return;}
  if(p.values.some(v=>!Number.isFinite(v)||v<0)||!Number.isFinite(p.total)||p.total<0||!Number.isFinite(p.debt)||p.debt<0){target.innerHTML='<p class="notice error">No se puede representar la distribución: magnitud inválida. Revisar los datos de origen.</p>';return;}
  if(Math.abs(p.values.reduce((a,b)=>a+b,0)-p.total)>=.005){target.innerHTML='<p class="notice error">No se puede representar la distribución: total incoherente con sus activos. Revisar los datos de origen.</p>';return;}
  const names=['Cuenta principal','Cuenta de ahorro','Cartera'];
  target.innerHTML=`<p class="meta">Activos totales: ${magnitude(p.total)}.</p>${valid?`<p class="meta">Escala común de activos: 0,00 € → ${magnitude(p.total)}</p>`:''}${p.values.map((v,i)=>`<div class="distribution-row">${names[i]} · <span class="amount">${magnitude(v)}</span>${valid?`<div class="track" aria-hidden="true"><span data-share="${v/p.total}" style="width:${v/p.total*100}%"></span></div>`:''}</div>`).join('')}<p class="meta">${valid?'Longitud relativa a los activos totales; sin deuda en las barras.':'Total de activos cero: valores válidos, distribución no representable. Sin porcentajes.'}</p><hr><p>Deudas (magnitud separada): <span class="amount">${magnitude(p.debt)}</span></p>`;
}
document.querySelector('#barra-caso').addEventListener('change',renderBars);
document.querySelector('#foto-caso').addEventListener('change',renderDistribution);
document.querySelector('#texto').addEventListener('click',event=>{const large=document.documentElement.classList.toggle('large-text');event.target.setAttribute('aria-pressed',String(large));});
const form=document.querySelector('#demo-form');
form.addEventListener('submit',event=>{
  event.preventDefault(); const input=document.querySelector('#importe');
  const valid=/^[+-]?\d+[,\.]\d{2}$/.test(input.value.trim());
  input.setAttribute('aria-invalid',String(!valid));document.querySelector('#importe-error').hidden=valid;
  const requiredValid=form.reportValidity();
  document.querySelector('#form-status').textContent=valid&&requiredValid?'Ejemplo validado. No se ha guardado ningún movimiento.':'Revisa los campos indicados.';
  if(!valid)input.focus();
});
form.addEventListener('reset',()=>{document.querySelector('#importe').removeAttribute('aria-invalid');document.querySelector('#importe-error').hidden=true;document.querySelector('#form-status').textContent='Ejemplo restablecido.';});
renderBars();renderSeries();renderDistribution();
