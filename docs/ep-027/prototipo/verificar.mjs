import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});
try{
 const page=await browser.newPage({viewport:{width:1440,height:1000}});const errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.goto(process.env.MOCKUP_URL||pathToFileURL(resolve('docs/ep-027/prototipo/exportacion-v1.html')).href);
 const click=a=>page.locator(`[data-action="${a}"]`).click();
 const text=()=>page.locator('main').innerText();
 const has=async re=>assert.match(await text(),re);
 await page.screenshot({path:'docs/ep-027/prototipo/windows.png',fullPage:true});
 await click('datos');await has(/signos/);await has(/distinto del CSV histórico/);
 await page.locator('input[value=months]').check();
 await page.locator('#from').fill('2026-03');await page.locator('#to').fill('2026-01');await click('start');
 await has(/debe ser anterior/);
 await page.locator('#from').fill('2026-01');await page.locator('#to').fill('2026-01');
 await page.locator('#from').blur();await has(/2026-01 a 2026-01/);
 await page.locator('main').focus();await page.screenshot({path:'docs/ep-027/prototipo/windows-rango.png',fullPage:true});
 await click('back');assert.equal(await page.locator('dialog').isVisible(),true);
 await page.keyboard.press('Escape');assert.equal(await page.locator('dialog').isVisible(),false);
 await page.goBack();assert.equal(await page.locator('dialog').isVisible(),true);await click('stay');
 async function start(){await click('start');await has(/Capturando una revisión/)}
 async function destination(){await click('next');await click('next');await click('next');assert.equal(await page.locator('dialog').isVisible(),true)}
 await start();await click('cancel');await click('stay');await destination();await click('selectorcancel');
 await has(/No se ha guardado ningún archivo/);await click('edit');assert.equal(await page.locator('#to').inputValue(),'2026-01');
 await page.locator('#review').evaluate(e=>e.open=true);
 for(const outcome of ['generation','conflict','write','partial','ok']){
  await page.locator('#outcome').selectOption(outcome);await start();
  if(outcome==='generation'){await click('next');await click('next');await has(/No se ha podido generar/)}
  else{await destination();await click('chosen');
   if(outcome==='ok'){await click('cancel');await click('stop');await has(/Se ha solicitado salir/);assert.doesNotMatch(await text(),/ZIP guardado/)}
   await click('next');await has({conflict:/Ese nombre ya existe/,write:/No se ha podido guardar/,partial:/Puede quedar un documento incompleto/,ok:/ZIP guardado/}[outcome]);
  }
  await click('edit');
 }
 await start();await click('cancel');await click('stop');await has(/Operación cancelada/);await click('finish');
 await click('copia');assert.equal(await page.locator('input[value=months]').isDisabled(),true);await has(/siempre incluye todo el histórico/);
 await click('guide');await has(/carpeta nueva de Windows/);await has(/solo lectura/);await click('guideback');
 await page.locator('#platform').selectOption('Android');await page.locator('#outcome').selectOption('ok');await start();await destination();await click('chosen');await click('next');await has(/Ubicación no facilitada/);assert.doesNotMatch(await text(),/Documentos \/ Exportaciones/);await click('edit');
 for(const width of [320,360,412,840,1440]){
  await page.setViewportSize({width,height:915});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`overflow ${width}`);
 }
 await page.setViewportSize({width:320,height:915});await page.locator('#review').evaluate(e=>e.open=false);
 await page.locator('main').focus();await page.screenshot({path:'docs/ep-027/prototipo/android-320.png',fullPage:true});
 await page.locator('#review').evaluate(e=>e.open=true);await page.locator('#scale').click();await page.locator('#review').evaluate(e=>e.open=false);
 for(const route of ['form','guide','progress','result']){
  if(route==='guide')await click('guide');
  if(route==='progress'){await click('guideback');await start()}
  if(route==='result'){await destination();await click('chosen');await click('next')}
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`overflow 320/200% ${route}`);
 }
 await page.locator('main').focus();await page.screenshot({path:'docs/ep-027/prototipo/android-320-texto200.png',fullPage:true});
 await click('edit');
 await click('back');await click('datos');await page.locator('input[value=all]').check();await page.locator('input[value=months]').check();
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'CSV 320/200%');
 await page.locator('main').focus();await page.screenshot({path:'docs/ep-027/prototipo/android-320-rango-texto200.png',fullPage:true});
 await click('back');assert.equal(await page.locator('dialog').isVisible(),true);
 assert.equal(await page.locator('dialog').evaluate(e=>e.scrollWidth>e.clientWidth),false,'diálogo 320/200%');
 assert.equal(await page.locator('dialog').evaluate(e=>e.scrollTop),0);
 await page.screenshot({path:'docs/ep-027/prototipo/android-320-abandonar-texto200.png'});await click('stay');
 await page.keyboard.press('Tab');assert.notEqual(await page.evaluate(()=>document.activeElement.tagName),'BODY');
 assert.deepEqual(errors,[]);console.log('OK: dos modos, validación meses, preservación de selección, borrador/Back/Escape, fases, cancelaciones, cinco resultados, guía, Android sin ruta inventada, 320–1440 y 320/texto200%, teclado, sin errores JS.');
}finally{await browser.close()}
