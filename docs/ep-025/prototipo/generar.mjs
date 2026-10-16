import {readFileSync,writeFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const dir=dirname(fileURLToPath(import.meta.url));
const read=p=>readFileSync(resolve(dir,p),'utf8').replace(/\r\n/g,'\n');
const fonts=[['regular',400],['medium',500],['bold',700]].map(([name,weight])=>`@font-face{font-family:Roboto;src:url(data:font/ttf;base64,${readFileSync(resolve(dir,`../../ep-026/identidad/assets/roboto-${name}.ttf`)).toString('base64')}) format('truetype');font-weight:${weight};font-display:swap}`).join('\n');
const html=read('plantilla.html').replace('/* STYLES */',()=>read('../../ep-026/identidad/tokens.css')+fonts+read('../../ep-026/prototipo/prototipo.css')+read('suplemento.css')).replace('/* APP */',()=>read('diagnostico.js'));
if(process.argv.includes('--check')){if(read('diagnostico-v1.html')!==html)throw Error('Regenerar HTML');console.log('HTML reproducible: correcto');}else writeFileSync(resolve(dir,'diagnostico-v1.html'),html);
