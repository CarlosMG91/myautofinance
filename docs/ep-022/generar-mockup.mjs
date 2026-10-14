import {readFileSync,writeFileSync} from 'node:fs';
const dir='docs/ep-022/';
let html=readFileSync('docs/ep-026/prototipo/autofinance-v1.html','utf8');
html=html.replace('<title>Autofinance · Prototipo integral v1 · MA-TSK-207</title>','<title>Real anual · Suplemento v1 · MA-TSK-175</title>')
 .replace('Prototipo v1 · MA-TSK-207 · pendiente de aprobación','Real anual · MA-TSK-175 · suplemento v1 · pendiente de aprobación humana')
 .replace(/<select id="scenario">[\s\S]*?<\/select>/,'<select id="scenario"><option value="supplement">Cobertura completa · histórico, directos y neto cero</option><option value="base">Referencia EP-001 · caso F</option><option value="netZero">Transferencia con neto cero</option><option value="pending">Sin clasificar y signos excepcionales</option></select>')
 .replace('/* impossible placeholder */','');
html=html.replace('</style>',()=>readFileSync(dir+'suplemento.css','utf8')+'</style>');
html=html.replace('</script>',()=>readFileSync(dir+'suplemento.js','utf8')+'</script>');
const target=dir+'mockup-real-anual.html';
if(process.argv.includes('--check')){if(readFileSync(target,'utf8')!==html)throw Error('Artefacto desactualizado');console.log('Reproducibilidad correcta');}
else{writeFileSync(target,html);console.log('Suplemento generado a partir de EP-026 v1 aprobado');}
