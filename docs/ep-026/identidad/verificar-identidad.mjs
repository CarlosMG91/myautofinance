import assert from 'node:assert/strict';
import {readFileSync, existsSync, mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {resolve, extname, sep} from 'node:path';
import {execFileSync} from 'node:child_process';
const root = resolve(fileURLToPath(new URL('./',import.meta.url)));
const tokens=JSON.parse(readFileSync(resolve(root,'tokens-visuales.json'),'utf8'));
const luminance = hex => {
  const [r,g,b]=hex.slice(1).match(/../g).map(v=>parseInt(v,16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);
  return .2126*r+.7152*g+.0722*b;
};
for(const [a,b,min] of tokens.contrastPairs){
  const l=[luminance(tokens.color[a]),luminance(tokens.color[b])].sort((a,b)=>b-a);
  const contrast=(l[0]+.05)/(l[1]+.05);
  assert.ok(contrast>=min,`${a}/${b}: ${contrast.toFixed(2)} < ${min}`);
  console.log(`Contraste ${a}/${b}: ${contrast.toFixed(2)}:1`);
}
execFileSync(process.execPath,[resolve(root,'generar-tokens.mjs'),'--check'],{stdio:'inherit'});
const hashes={
  'roboto-regular.ttf':'79e851404657dac2106b3d22ad256d47824a9a5765458edb72c9102a45816d95',
  'roboto-medium.ttf':'f205cc511821ea56078a105557fcea6253129404d411c997e1866fbd006abb68',
  'roboto-bold.ttf':'7d0b991ee3e0be7af01ad7ea8cd2beea6c00a25e679a0226b6737f079aaFFF86'.toLowerCase()
};
for(const [file,hash] of Object.entries(hashes))assert.equal(createHash('sha256').update(readFileSync(resolve(root,'assets',file))).digest('hex'),hash);
assert.match(readFileSync(resolve(root,'assets/LICENSE-Roboto.txt'),'utf8'),/Apache License/);
execFileSync(process.execPath,[fileURLToPath(new URL('../../ep-001/verificar-casos.mjs',import.meta.url))],{stdio:'inherit'});
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const server=createServer((req,res)=>{
  const path=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://local').pathname));
  if(!path.startsWith(root+sep)||!existsSync(path)){res.writeHead(404);res.end();return;}
  res.setHeader('Content-Type',({'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.ttf':'font/ttf'})[extname(path)]||'text/plain');
  res.end(readFileSync(path));
});
await new Promise(done=>server.listen(0,'127.0.0.1',done));
const origin=`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});
try{
  const page=await browser.newPage({viewport:{width:1440,height:1000}});
  const errors=[],remote=[],fontRequests=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',route=>{
    const url=route.request().url();
    if(!url.startsWith(origin+'/')){remote.push(url);return route.abort();}
    if(url.endsWith('.ttf'))fontRequests.push(url);
    return route.continue();
  });
  await page.goto(origin+'/galeria.html');await page.evaluate(()=>document.fonts.ready);
  assert.equal(await page.evaluate(()=>document.fonts.check('16px AfRoboto')),true);
  assert.equal(new Set(fontRequests).size,3,'Los tres pesos deben cargar localmente');
  const captures=resolve(root,'capturas');mkdirSync(captures,{recursive:true});
  await page.screenshot({path:resolve(captures,'windows.png'),fullPage:true});
  await page.screenshot({path:resolve(captures,'windows-resumen.png')});
  await page.locator('#graficos').screenshot({path:resolve(captures,'windows-graficos.png')});
  assert.match(await page.locator('.summary-grid').innerText(),/\+1\.229,75/);
  assert.equal(await page.locator('#serie [data-segment]').count(),0,'No unir enero/abril a través de meses ausentes');
  assert.equal(await page.locator('#serie .point').count(),2);
  assert.match(await page.locator('#serie table').innerText(),/Feb\s+Sin dato\s+Mar\s+Sin dato/);
  for(const [value,shares] of [['completa',3],['incompleta',0],['cero',0],['invalida',0],['incoherente',0]]){
    await page.locator('#foto-caso').selectOption(value);
    assert.equal(await page.locator('#distribucion [data-share]').count(),shares);
    const text=await page.locator('#distribucion').innerText();
    assert.doesNotMatch(text,/NaN|Infinity|undefined/);
    if(value==='incompleta')assert.match(text,/Activos, deudas y neto: sin dato/);
    if(value==='cero'){assert.match(text,/Total de activos cero/);assert.match(text,/Deudas.*5\.000,00/);}
    if(value==='invalida')assert.match(text,/magnitud inválida/);
    if(value==='incoherente')assert.match(text,/total incoherente/);
  }
  await page.locator('#foto-caso').selectOption('completa');
  for(const value of ['normal','mixto','cero','ausente']){
    await page.locator('#barra-caso').selectOption(value);
    assert.equal(await page.locator('#barras .plot-zero').count(),1);
    const table=await page.locator('#barras table').innerText();
    if(value==='normal'){assert.match(table,/−350,25/);assert.match(table,/−400,00/);}
    if(value==='mixto'){
      assert.match(table,/\+30,00/);assert.match(table,/−400,00/);
      assert.ok(Number(await page.locator('#barras rect.bar-real').getAttribute('x'))>=260);
      assert.ok(Number(await page.locator('#barras rect.bar-budget').getAttribute('x'))<260);
    }
    if(value==='cero')assert.equal(await page.locator('#barras circle').count(),2);
    if(value==='ausente'){assert.match(table,/Sin presupuesto/);assert.equal(await page.locator('#barras .bar-budget').count(),0);}
  }
  await page.locator('#barra-caso').selectOption('normal');
  await page.locator('#importe').fill('abc');await page.locator('button[type=submit]').click();
  assert.equal(await page.locator('#importe').getAttribute('aria-invalid'),'true');
  assert.equal(await page.locator('#importe').evaluate(el=>el===document.activeElement),true);
  assert.equal(await page.locator('#importe-error').isVisible(),true);
  await page.locator('#importe').fill('-350,25');await page.locator('button[type=submit]').click();
  assert.match(await page.locator('#form-status').innerText(),/No se ha guardado/);
  await page.locator('button[type=reset]').click();
  await page.goto(origin+'/galeria.html');await page.keyboard.press('Tab');
  assert.equal(await page.evaluate(()=>document.activeElement.className),'skip');
  await page.keyboard.press('Enter');await page.keyboard.press('Tab');
  assert.equal(await page.evaluate(()=>document.activeElement.id),'texto');
  const focus=await page.locator('#texto').evaluate(el=>getComputedStyle(el).outlineWidth);
  assert.equal(focus,'3px');
  for(const width of [320,360,412,840,1024,1440]){
    await page.setViewportSize({width,height:915});
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`Overflow ${width}`);
    assert.equal(await page.locator('input').first().evaluate(el=>el.getBoundingClientRect().height>=48),true);
  }
  await page.setViewportSize({width:412,height:915});await page.evaluate(()=>scrollTo(0,0));
  await page.screenshot({path:resolve(captures,'android.png'),fullPage:true});
  await page.screenshot({path:resolve(captures,'android-resumen.png')});
  await page.locator('#texto').click();
  for(const width of [320,412,1024,1440]){
    await page.setViewportSize({width,height:915});
    assert.equal(await page.evaluate(()=>getComputedStyle(document.body).fontSize),'32px');
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`Overflow texto 200% ${width}`);
    assert.equal(await page.locator('#serie table').isVisible(),true);
  }
  await page.setViewportSize({width:412,height:915});await page.evaluate(()=>scrollTo(0,0));
  await page.screenshot({path:resolve(captures,'texto-200.png'),fullPage:true});
  await page.screenshot({path:resolve(captures,'texto-200-resumen.png')});
  await page.emulateMedia({reducedMotion:'reduce'});
  assert.equal(await page.evaluate(()=>getComputedStyle(document.documentElement).scrollBehavior),'auto');
  assert.deepEqual(errors,[]);assert.deepEqual(remote,[],'La galería no debe pedir recursos remotos');
  const localPage=await browser.newPage();const localRemote=[];
  await localPage.route('**/*',route=>{
    const url=route.request().url();
    if(!url.startsWith('file:')){localRemote.push(url);return route.abort();}
    return route.continue();
  });
  await localPage.goto(pathToFileURL(resolve(root,'galeria.html')).href);
  await localPage.evaluate(()=>document.fonts.ready);
  assert.equal(await localPage.evaluate(()=>document.fonts.check('16px AfRoboto')),true);
  assert.equal(await localPage.locator('#distribucion [data-share]').count(),3);
  assert.deepEqual(localRemote,[]);await localPage.close();
  console.log('OK: assets locales, contraste, fixtures EP-001, barras firmadas/cero/ausencia, distribución protegida, huecos, formulario/foco, 6 anchos y texto 200%, reducción de movimiento, capturas.');
}finally{await browser.close();await new Promise(done=>server.close(done));}
