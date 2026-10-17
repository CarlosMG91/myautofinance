import {readFileSync,writeFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const dir=dirname(fileURLToPath(import.meta.url));
const read=p=>readFileSync(resolve(dir,p),'utf8').replace(/\r\n/g,'\n');
const fonts=[['regular',400],['medium',500],['bold',700]].map(([n,w])=>`@font-face{font-family:Roboto;src:url(data:font/ttf;base64,${readFileSync(resolve(dir,`../../ep-026/identidad/assets/roboto-${n}.ttf`)).toString('base64')});font-weight:${w};font-display:swap}`).join('\n');
const html=read('plantilla.html').replace('/* STYLE */',()=>read('../../ep-026/identidad/tokens.css')+fonts+read('../../ep-026/prototipo/prototipo.css')+read('estilos.css')).replace('/* APP */',()=>read('interacciones.js'));
if(process.argv.includes('--check')){if(read('exportacion-v1.html')!==html)throw Error('Artefacto desactualizado');console.log('Artefacto reproducible: OK')}else writeFileSync(resolve(dir,'exportacion-v1.html'),html);
