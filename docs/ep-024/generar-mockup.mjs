import {readFileSync,writeFileSync} from 'node:fs';
const dir=new URL('./',import.meta.url), read=p=>readFileSync(new URL(p,dir),'utf8');
const approved=read('../ep-026/prototipo/autofinance-v1.html');
const css=approved.match(/<style>([\s\S]*?)<\/style>/)[1];
const html=read('plantilla.html').replace('/* ESTILOS */',()=>css+'\n'+read('suplemento.css')).replace('/* INTERACCIONES */',()=>read('suplemento.js'));
const target=new URL('mockup-desgloses.html',dir);
if(process.argv.includes('--check')){if(readFileSync(target,'utf8')!==html)throw Error('HTML desactualizado');console.log('Artefacto reproducible: OK');}
else{writeFileSync(target,html);console.log('Suplemento MA-TSK-191 generado desde estilos/fuentes EP-026 v1');}
