import assert from 'node:assert/strict';
import {readFileSync,mkdirSync} from 'node:fs';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const dir=dirname(fileURLToPath(import.meta.url));
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE||resolve(dir,'../../../.tools/ma-tsk-141-browser/node_modules/playwright'));
const html=readFileSync(resolve(dir,'diagnostico-v1.html'));
const server=createServer((req,res)=>{res.setHeader('Content-Type','text/html; charset=utf-8');res.end(html);});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const url=process.env.MOCKUP_URL||`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe'});
mkdirSync(resolve(dir,'capturas'),{recursive:true});
const failures=[],remotes=[];
let captures=0;
try{
 const page=await browser.newPage({viewport:{width:1440,height:960}});
 page.on('pageerror',e=>failures.push(e.message));
 page.on('request',r=>{if(!r.url().startsWith(new URL(url).origin)&&!r.url().startsWith('data:'))remotes.push(r.url());});
 const act=async a=>{await page.locator(`[data-act="${a}"]`).first().click();const target=a.startsWith('detail:')?'/diagnostico/detalle':({results:'/diagnostico',return:'/diagnostico',origin:'/origen',other:'/origen/segundo',recover:'/diagnostico'})[a];if(target)await page.waitForFunction(p=>location.hash==='#'+p&&document.querySelector('#content').dataset.rendered===p,target);};
 const text=()=>page.locator('#content').innerText();
 const capture=async name=>{await page.screenshot({path:resolve(dir,`capturas/${name}.png`),fullPage:true});captures++;};
 const run=async scenario=>{if(!await page.locator('#review').evaluate(e=>e.open))await page.locator('#review summary').click();await page.selectOption('#scenario',scenario);await page.locator('#review summary').click();await act('run');await page.getByRole('heading',{name:'Ejecutando diagnóstico',exact:true}).waitFor({state:'hidden'});};
 for(const [device,width,height] of [['windows',1440,960],['android',412,915]]){
  await page.setViewportSize({width,height});await page.goto(url);await page.evaluate(()=>document.fonts.ready);
  assert.match(await text(),/Diagnóstico de coherencia/);await page.getByRole('button',{name:'Abrir diagnóstico de coherencia',exact:true}).click();
  assert.match(await text(),/Listo para revisar/);await capture(device+'-inicio');
  await act('run');await capture(device+'-progreso');await act('cancel');assert.match(await text(),/Diagnóstico cancelado/);assert.doesNotMatch(await text(),/Sin hallazgos/);
  await run('mixed');assert.equal(await page.locator('.finding').count(),6);await capture(device+'-resultados');
  await page.selectOption('#severity','Aviso');assert.equal(await page.locator('.finding').count(),1);await act('detail:duplicate');assert.match(await text(),/lote-a.*fila 2/s);assert.match(await text(),/lote-b.*fila 8/s);await capture(device+'-duplicado');
  await act('other');assert.match(await text(),/lote-b/);await act('return');assert.equal(await page.locator('#severity').inputValue(),'Aviso');
  await page.selectOption('#severity','Todas');await act('detail:conflict');await act('origin');assert.match(await text(),/enero de 2026/);await act('change');await act('return');assert.match(await text(),/Resultado obsoleto/);await capture(device+'-obsoleto');
  await run('clean');assert.match(await text(),/Sin hallazgos/);assert.match(await text(),/9 de 9/);await capture(device+'-sin-hallazgos');
  await page.selectOption('#month','1');assert.match(await text(),/Resultado obsoleto/);await run('pending');assert.equal(await page.locator('.finding').count(),3);await act('detail:photo');assert.match(await text(),/1 de febrero de 2026/);await act('origin');assert.match(await text(),/month=2/);await act('return');await capture(device+'-pendientes');
  await run('income');await act('detail:indicator');assert.match(await text(),/marzo de 2026/);await act('origin');assert.match(await text(),/month=3/);await act('return');
  await run('skipped');assert.match(await text(),/Revisión incompleta/);assert.match(await text(),/8 de 9/);assert.doesNotMatch(await text(),/Sin hallazgos/);await capture(device+'-no-ejecutada');
  await run('error');assert.match(await text(),/No se pudo leer la base local/);assert.equal(await page.locator('.summary-counts').count(),0);await capture(device+'-error-lectura');await page.getByRole('button',{name:'Abrir Recuperación local',exact:true}).click();assert.match(await text(),/Recuperación local/);await act('recover');assert.match(await text(),/No se completó la ejecución/);
  await run('stale');assert.match(await text(),/Resultado obsoleto/);await page.reload();await page.getByRole('heading',{name:'Listo para revisar',exact:true}).waitFor();assert.equal(await page.locator('.summary-counts').count(),0);
 }
 await run('mixed');
 for(const width of [320,360,412,839,840,1024,1440]){
  await page.setViewportSize({width,height:960});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`Desbordamiento a ${width}`);
 }
 await page.setViewportSize({width:360,height:960});await page.locator('#review summary').click();await page.locator('#scale').click();await page.locator('#review summary').click();assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'Texto 200 %');await capture('android-texto-200');
 await act('detail:photo');assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'Detalle 200 %');await capture('android-detalle-200');
 assert.deepEqual(failures,[]);assert.deepEqual(remotes,[]);
 console.log(`Correcto: recorridos Windows/Android, 8 escenarios, cancelación, filtros/retorno, destinos/periodos, obsolescencia y sesión vacía al recargar; 7 anchos y texto 200 % sin desbordamiento; ${captures} capturas HTML; sin errores JS ni solicitudes externas.`);
} finally{await browser.close();await new Promise(r=>server.close(r));}
