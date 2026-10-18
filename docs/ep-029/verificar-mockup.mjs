import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE||'playwright');
const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});
try{
 const page=await browser.newPage({viewport:{width:1440,height:1100}});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const response=await page.goto(process.env.MOCKUP_URL||'http://localhost:4310/mockups/autofinance-ma-tsk-240-v1.html');
 assert.equal(response.status(),200);
 const action=async name=>page.locator(`[data-action="${name}"]`).click();
 const expectText=async text=>assert.ok((await page.locator('#content').innerText()).includes(text),text);
 await action('install');await action('cancel');await expectText('Has cancelado');
 await action('root');await action('install');await action('opened');await expectText('Tu resumen, primero');
 await action('drive');await action('upload');await expectText('Conecta con Google antes');
 await action('authorize');await page.locator('#back').click();await expectText('Sin conexión');
 await action('authorize');await action('cancelAuth');await expectText('sin transferir datos');
 await action('authorize');await action('authorized');await action('upload');await expectText('Subida confirmada solo');
 await action('download');await action('returnDrive');await expectText('sin transferir datos');
 await action('imports');await action('csv');await action('cancelPicker');await expectText('No se ha importado');
 await action('openbank');await page.goBack();await expectText('Gestión');
 await action('csv');await action('selected');await expectText('Pendiente de revisión');
 await action('imports');await action('update');await action('updateSystem');await action('updated');
 await expectText('24 movimientos');await expectText('2.450,00');await expectText('copia local y estado Drive');
 await action('signature');await expectText('Transición bloqueada');
 assert.equal(await page.getByRole('button',{name:/desinstalar/i}).count(),0);
 await page.locator('#scenario').selectOption('google');await expectText('Google Drive no está disponible');
 await action('home');await expectText('Cuenta hogar');
 await page.locator('#restart').click();await page.locator('#back').click();await expectText('Inicio del guion');
 const noOverflow=async label=>assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,label);
 for(const width of [320,360,412,840,1440]){
  await page.setViewportSize({width,height:1000});
  for(const large of [false,true]){
   if((await page.locator('#zoom').getAttribute('aria-pressed'))!==String(large))await page.locator('#zoom').click();
   for(let i=0;i<6;i++){await page.locator(`[data-step="${i}"]`).click();await noOverflow(`${width}, ${large?'200':'100'}%, paso ${i+1}`)}
   for(const scenario of ['signature','cancel','google','version']){
    await page.locator('#scenario').selectOption(scenario);await noOverflow(`${width}, ${large?'200':'100'}%, ${scenario}`);
   }
   for(const name of ['csv','openbank','authorize','download','updateSystem']){
    await page.locator('#scenario').selectOption('normal');
    const step=name==='csv'||name==='openbank'?4:name==='updateSystem'?5:3;
    await page.locator(`[data-step="${step}"]`).click();
    if(name==='download'){await action('authorize');await action('authorized')}
    await action(name);await noOverflow(`${width}, ${large?'200':'100'}%, ${name}`);
   }
  }
 }
 await page.locator('#zoom').click();await page.setViewportSize({width:1440,height:1100});await page.locator('#restart').click();
 await page.screenshot({path:'docs/ep-029/mockup-escritorio.png',fullPage:true});
 await page.setViewportSize({width:320,height:960});await page.locator('[data-step="5"]').click();
 await page.screenshot({path:'docs/ep-029/mockup-320.png',fullPage:true});
 await page.locator('#zoom').click();await action('signature');
 await page.screenshot({path:'docs/ep-029/mockup-320-200.png',fullPage:true});
 assert.deepEqual(errors,[]);
 console.log('OK: HTTP 200; instalación/cancelación, Drive conectar/cancelar/subir/revisión descarga, CSV/Openbank seleccionar/cancelar/volver, actualización y bloqueo de firma; Back y navegador; 150 combinaciones de ancho/texto/paso/estado, sin desbordamiento; 3 capturas HTML; sin errores JS. No prueba Android nativo.');
}finally{await browser.close()}
