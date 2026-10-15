import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const base=new URL('../ep-026/prototipo/autofinance-v1.html',import.meta.url);
let html=readFileSync(base,'utf8');
if(createHash('sha256').update(html).digest('hex')!=='5f000e2db4ebac1c0678899c5f18ad2351e8aeedae202deb038cfe66158ed4f6')throw Error('La referencia EP-026 ha cambiado: revisar antes de regenerar');
html=html.replace('<title>Autofinance · Prototipo integral v1 · MA-TSK-207</title>','<title>Colchón de emergencia · Suplemento v1 · MA-TSK-185</title>');
html=html.replace('Prototipo v1 · MA-TSK-207 · pendiente de aprobación','Suplemento Colchón v1 · MA-TSK-185 · pendiente de aprobación');
html=html.replace('</body>',`<script>${readFileSync(new URL('mockup-suplemento.js',import.meta.url),'utf8')}</script></body>`);
const target=new URL('mockup-colchon-v1.html',import.meta.url);
if(process.argv.includes('--check')){if(readFileSync(target,'utf8')!==html)throw Error('Artefacto desactualizado');console.log('Reproducción y referencia aprobada: OK');}
else writeFileSync(target,html);
