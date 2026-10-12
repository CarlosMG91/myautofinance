import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const dir=dirname(fileURLToPath(import.meta.url));
const identity=resolve(dir,'../identidad');
const csv=readFileSync(resolve(dir,'../../ep-001/historico-ejemplo.csv'),'utf8').trim().split(/\r?\n/).slice(1);
const records=csv.map((line,i)=>{const [date,concept,amount,type,a,b,c,account,discretion]=line.split(';');return {id:`fixture-${i+2}`,ordinal:i+2,date,concept,cents:Math.round(Number(amount)*100)*(type==='PRESUPUESTO'?-1:1),type,path:[a,b,c].filter(Boolean).join(' / '),account,discretion};});
const fonts=[['regular',400],['medium',500],['bold',700]].map(([name,weight])=>`@font-face{font-family:Roboto;src:url(data:font/ttf;base64,${readFileSync(resolve(identity,`assets/roboto-${name}.ttf`)).toString('base64')}) format('truetype');font-weight:${weight};font-display:swap}`).join('\n');
const html=readFileSync(resolve(dir,'plantilla.html'),'utf8').replace('/* TOKENS */',()=>readFileSync(resolve(identity,'tokens.css'),'utf8')+'\n'+fonts+'\n'+readFileSync(resolve(dir,'prototipo.css'),'utf8')).replace('/* DATASET */',()=>`const originalRecords=${JSON.stringify(records)};`).replace('/* APP */',()=>readFileSync(resolve(dir,'prototipo.js'),'utf8'));
const target=resolve(dir,'autofinance-v1.html');
if(process.argv.includes('--check')){if(readFileSync(target,'utf8')!==html)throw Error('El HTML publicado no coincide con sus fuentes');console.log('Artefacto reproducible: OK');}else{writeFileSync(target,html);console.log('Prototipo autónomo v1 generado');}
