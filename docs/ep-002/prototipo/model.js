(function(root){
const roots=['Ingresos','Vivienda','Alimentación','Ahorro','Ocio'];
const names=['Cuenta principal','Cuenta de ahorro','Cartera','Deuda familiar'];
function initial(empty=false){return {records:empty?[]:structuredClone(root.REFERENCE),imported:!empty,photos:empty?{}:{'2026-01':[600000,300000,1000000,500000]},dirty:false,known:1,remote:1,backup:null};}
function rows(s,type,y,m,path=''){return s.records.filter(r=>r.type===type&&r.date.startsWith(String(y))&&(!m||+r.date.slice(5,7)===+m)&&(!path||r.path===path||r.path.startsWith(path+' / ')));}
const sum=a=>a.reduce((t,r)=>t+r.amount,0);
function photo(s,key){let v=s.photos[key];if(!v||v.every(x=>x===null))return {reason:'sin dato: falta foto patrimonial'};let missing=names.filter((_,i)=>v[i]===null);if(missing.length)return {reason:'sin dato: foto patrimonial incompleta',missing};return {liquid:v[0]+v[1],assets:v[0]+v[1]+v[2],debt:v[3],net:v[0]+v[1]+v[2]-v[3]};}
function indicator(s,y,m){let p=photo(s,`${y}-${String(m).padStart(2,'0')}`);if(p.reason)return p;let months=Array.from({length:12},(_,i)=>rows(s,'PRESUPUESTO',y,i+1,'Ingresos'));if(months.some(a=>!a.length))return {reason:'sin dato: presupuesto anual de ingresos incompleto'};let income=sum(months.flat());if(income<=0)return {reason:income===0?'sin dato: ingresos presupuestados nulos':'sin dato: ingresos presupuestados no positivos'};return {value:p.liquid/(income/12),liquid:p.liquid,income};}
function conflict(s,r,ignore){return s.records.some(x=>x!==ignore&&x.type==='PRESUPUESTO'&&x.date===r.date&&(x.path===r.path||x.path.startsWith(r.path+' / ')||r.path.startsWith(x.path+' / ')));}
function proposal(s,y){return Array.from({length:12},(_,i)=>roots.map(path=>{let n=sum(rows(s,'REAL',y-1,i+1,path));return {date:`${y}-${String(i+1).padStart(2,'0')}-01`,type:'PRESUPUESTO',path,amount:Math.sign(n)*Math.ceil(Math.abs(n)/1000)*1000,concept:'Propuesta',account:'',discretion:''};})).flat();}
root.Model={roots,names,initial,rows,sum,photo,indicator,conflict,proposal};
})(globalThis);
