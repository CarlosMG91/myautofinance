import { readFileSync, writeFileSync } from 'node:fs';
const read = name => readFileSync(new URL(name, import.meta.url), 'utf8');
let html = read('../ep-012/mockup-importacion.html');
html = html.replaceAll('MA-TSK-108', 'MA-TSK-128').replace('Revisión e historial ·', 'Openbank ·');
html = html.replace('Propuesta v1', 'Suplemento Openbank v1');
html = html.replace('Los lectores CSV/XLS, SQLite y la importación de producción pertenecen a tickets posteriores.', 'Suplemento de EP-002 y EP-012. Sin muestra Openbank: no se interpretan bytes ni se presuponen hojas, columnas o formatos. Todo dato mostrado pertenece al dominio común y es sintético.');
html = html.replace('Guion: resolver cuenta y categoría → revisar cada solapamiento → confirmar → consultar lote y origen.', 'Guion: seleccionar archivo → confirmar cuenta → revisar cada solapamiento → confirmar lote → consultar historial y origen.');
html = html.replace(/<label>Escenario <select id="scenario">[\s\S]*?<\/select><\/label><button id="load">Cargar escenario<\/button>/, '<button id="load">Seleccionar / cambiar archivo</button>');
const start = html.indexOf('const fixture=');
const end = html.indexOf('function initialBatches()', start);
html = html.slice(0, start) + `const fixture=[
 {ordinal:2,type:'REAL',date:'2026-01-05',concept:'Café',original:-1000,amount:-1000,cat:null,overlap:true},
 {ordinal:3,type:'REAL',date:'2026-01-05',concept:'Café',original:-1000,amount:-1000,cat:null,overlap:true},
 {ordinal:4,type:'REAL',date:'2026-01-07',concept:'Compra sintética',original:-3525,amount:-3525,cat:null},
 {ordinal:5,type:'REAL',date:'2026-01-09',concept:'Abono sintético',original:100000,amount:100000,cat:null}
];
const originalFields=()=>[]; // No hay campos bancarios caracterizados.
` + html.slice(end);
const initialStart = html.indexOf('function initialBatches()');
const initialEnd = html.indexOf('let batches=', initialStart);
html = html.slice(0, initialStart) + `function initialBatches(){return [{id:'LOT-001',name:'anterior-sintetico.xls',source:'Openbank · simulación',version:'Común 1 · formato sin caracterizar',hash:sameHash,confirmed:'08/10/2026 · 10:00',real:2,budget:0,rows:fixture.slice(0,2).map(r=>({...r,account:'Cuenta diaria',fields:[],current:r.ordinal===3?null:{...r,account:'Cuenta diaria',amount:-1200}}))}];}
` + html.slice(initialEnd);
html = html.replace('newSession();\n</script>', read('suplemento-openbank.js') + '\n</script>');
html = html.replace('</style>', '.large .card dl{grid-template-columns:1fr}.large .card dd{text-align:left} .phone .reviewer{padding:16px}@media(forced-colors:active){button,.panel,.card,.warning,.notice,.error{border:1px solid CanvasText}}\n</style>');
writeFileSync(new URL('mockup-openbank.html', import.meta.url), html, 'utf8');
console.log('Generado docs/ep-014/mockup-openbank.html desde EP-012 + suplemento.');
