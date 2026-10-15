import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync,mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE||'playwright');
const url=process.env.MOCKUP_URL||'http://localhost:4310/mockups/autofinance-ma-tsk-185-v1.html';
const bytes=Buffer.from(await (await fetch(url)).arrayBuffer());
assert.deepEqual(bytes,readFileSync(new URL('mockup-colchon-v1.html',import.meta.url)));
const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});
const errors=[],external=[];mkdirSync(new URL('capturas/',import.meta.url),{recursive:true});
try{
 const page=await browser.newPage({viewport:{width:1440,height:900}});
 page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',r=>{if(!r.request().url().startsWith(new URL(url).origin)&&!r.request().url().startsWith('data:')){external.push(r.request().url());r.abort();}else r.continue();});
 await page.goto(url);await page.evaluate(()=>document.fonts.ready);
 const content=()=>page.locator('#content').innerText();
 const choose=async s=>{await page.locator('#review').evaluate(e=>e.open=true);await page.selectOption('#scenario',s);};
 assert.match(await content(),/3,00/);assert.match(await content(),/9\.000,00/);assert.match(await content(),/36\.000,00/);
 await page.screenshot({path:new URL('capturas/pc.png',import.meta.url).pathname.replace(/^\/([A-Z]:)/,'$1'),fullPage:true});
 for(const [s,c] of [['absent','foto_ausente'],['partial','foto_incompleta'],['incomeMissing','ingresos_incompletos'],['incomeZero','ingresos_nulos'],['incomeNegative','ingresos_negativos']]){
  await choose(s);assert.match(await content(),new RegExp(c));assert.match(await content(),/Sin dato/);
 }
 await choose('partial');assert.match(await content(),/Cuenta de ahorro/);assert.match(await content(),/Cartera/);
 await page.locator('#content [data-route="/patrimonio/foto"]').click();assert.equal(await page.evaluate(()=>key()),'2026-02');
 assert.equal(await page.evaluate(()=>route),'/patrimonio/foto');await page.evaluate(()=>back());assert.equal(await page.evaluate(()=>route),'/indicadores');
 await choose('incomeMissing');await page.locator('[data-income-month="2"]').click();assert.equal(await page.evaluate(()=>key()),'2026-03');assert.equal(await page.evaluate(()=>route),'/presupuesto/mensual');
 await page.evaluate(()=>back());assert.equal(await page.evaluate(()=>key()),'2026-01');assert.match(await content(),/ingresos_incompletos/);
 await choose('liquidZero');assert.match(await content(),/0,00/);assert.match(await content(),/Cero calculable/);assert.doesNotMatch(await content(),/Código:/);
 await page.selectOption('#queryState','loading');assert.doesNotMatch(await content(),/Código:|0,00/);
 await page.selectOption('#queryState','error');assert.doesNotMatch(await content(),/Código:/);await page.locator('[data-action="retry"]').click();assert.match(await content(),/Cero calculable/);
 await choose('base');await page.locator('#content [data-route="/indicadores/detalle"]').first().click();for(const c of ['foto_ausente','foto_incompleta','ingresos_incompletos','ingresos_nulos','ingresos_negativos'])assert.match(await content(),new RegExp(c));
 for(const width of [320,360,412,1024,1440]){
  await page.setViewportSize({width,height:900});
  for(const s of ['base','absent','partial','incomeMissing','incomeZero','incomeNegative','liquidZero']){
   await choose(s);assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${width} ${s}: desbordamiento`);
  }
 }
 await page.setViewportSize({width:412,height:915});await choose('partial');await page.locator('#review').evaluate(e=>e.open=false);
 await page.screenshot({path:new URL('capturas/android.png',import.meta.url).pathname.replace(/^\/([A-Z]:)/,'$1'),fullPage:true});
 await page.locator('#review').evaluate(e=>e.open=true);await page.locator('#scale').click();await page.locator('#review').evaluate(e=>e.open=false);
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Texto 200 %');
 await page.screenshot({path:new URL('capturas/texto-200.png',import.meta.url).pathname.replace(/^\/([A-Z]:)/,'$1'),fullPage:true});
 assert.deepEqual(errors,[]);assert.deepEqual(external,[]);
 console.log('Siete escenarios, detalle, destinos/retorno, carga/error/reintento, 35 combinaciones de ancho/estado y texto 200 %: OK');
 console.log('SHA-256 '+createHash('sha256').update(bytes).digest('hex'));
}finally{await browser.close();}
