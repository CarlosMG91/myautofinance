import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const directory = path.join(root, 'docs/ep-026/validacion-capturas');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const approved = '5f000e2db4ebac1c0678899c5f18ad2351e8aeedae202deb038cfe66158ed4f6';
if (digest(readFileSync(path.join(root, 'docs/ep-026/prototipo/autofinance-v1.html'))) !== approved) {
  throw new Error('El prototipo conservado no coincide con la versión aprobada.');
}
const images = [];
for (const platform of ['windows', 'android']) {
  const manifest = JSON.parse(readFileSync(path.join(directory, `${platform}-manifiesto.json`), 'utf8'));
  const results = JSON.parse(readFileSync(path.join(directory, `${platform}-resultados.json`), 'utf8'));
  if (manifest.runtime.platform !== platform || !manifest.runtime.syntheticDataOnly ||
      manifest.captures.length !== 57 || results.length !== 3 ||
      results.some(result => !result.reopened)) {
    throw new Error(`Evidencia incompleta o sin origen sintético: ${platform}`);
  }
  if (results[0].renderedRecords !== 100 || results[0].largeLoadMilliseconds < 0) {
    throw new Error(`Falta el recorrido de carga paginada: ${platform}`);
  }
  for (const image of manifest.captures) {
    if (!new RegExp(`^${platform}-(1440|1024|412|360|320)-[12]-[a-z0-9-]+\\.png$`).test(image.file)) {
      throw new Error('Nombre de captura inesperado.');
    }
    const bytes = readFileSync(path.join(directory, image.file));
    if (digest(bytes) !== image.sha256 || bytes.readUInt32BE(0) !== 0x89504e47 ||
        bytes.readUInt32BE(16) !== image.width || bytes.readUInt32BE(20) !== image.height) {
      throw new Error(`Hash o dimensiones incorrectos: ${image.file}`);
    }
    images.push(image.file);
  }
  for (const file of manifest.importCaptures) {
    if (!new RegExp(`^native-${platform}-(seleccion|resumen|resultado)\\.png$`).test(file)) {
      throw new Error('Nombre de importación inesperado.');
    }
    const name = `import-${file}`;
    const bytes = readFileSync(path.join(directory, name));
    if (bytes.readUInt32BE(0) !== 0x89504e47) throw new Error(`PNG inválido: ${name}`);
    images.push(name);
  }
}
const labels = {
  inicio: 'Inicio · enero de referencia',
  'estado-detalle': 'Estado · detalle completo',
  'movimiento-borrador': 'Edición · borrador conservado tras Back',
  'inicio-retorno': 'Inicio · retorno tras guardar el movimiento',
  presupuesto: 'Presupuesto · resumen',
  'presupuesto-detalle': 'Presupuesto · detalle y matriz',
  patrimonio: 'Patrimonio · resumen tras guardar cero',
  'patrimonio-detalle': 'Patrimonio · detalle',
  importar: 'CSV · entrada desde Inicio',
  'categorizar-vacio': 'Categorización · bandeja vacía',
  'real-pendiente': 'Real anual · interfaz pendiente EP-022',
  'indicadores-pendiente': 'Indicadores · interfaz pendiente EP-023',
  'diagnostico-pendiente': 'Diagnóstico · interfaz pendiente EP-025',
  'inicio-sin-foto': 'Inicio · febrero sin foto',
  'movimientos-5004': 'Movimientos · 5.004 registros, página de 100',
};
const figure = file => {
  const label = file.replace('.png', '').replaceAll('-', ' ');
  return `<figure><a href="${file}"><img loading="lazy" src="${file}" alt="${label}"></a><figcaption><a href="${file}">${label}</a></figcaption></figure>`;
};
const sections = Object.entries(labels).map(([state, title]) => {
  const files = images.filter(file => file.endsWith(`-${state}.png`) || file.endsWith(`-${state}-contenido.png`));
  return `<section><h2>${title}</h2><div class="grid">${files.map(figure).join('\n')}</div></section>`;
}).join('\n');
const imports = images.filter(file => file.startsWith('import-'));
const html = `<!doctype html>
<html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>MA-TSK-217 · Evidencias nativas</title>
<style>body{margin:0;background:#f5f7fa;color:#182b36;font:16px/1.5 system-ui,sans-serif}main{max-width:1440px;margin:auto;padding:24px}a{color:#086779}a:focus-visible{outline:3px solid #7251a0;outline-offset:3px}.notice{padding:20px;background:#fff4db;border:2px solid #806000;border-radius:12px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr));gap:16px}figure{margin:0;padding:12px;background:white;border:1px solid #ccd5dd;border-radius:12px}img{display:block;width:100%;height:300px;object-fit:contain}figcaption{overflow-wrap:anywhere}h2{margin-top:40px}</style>
<main><h1>MA-TSK-217 · Capturas de ejecución nativa</h1>
<div class="notice"><strong>Validación parcial; aceptación visual final pendiente.</strong>
<p>EP-022/023/024/025 y el acceso productivo Openbank siguen pendientes. Las imágenes de sus marcadores hacen visible esa carencia. No representan funcionalidades completas.</p></div>
<p>${images.length} PNG de Windows y Android con datos sintéticos. RenderRepaintBoundary de la app ejecutada nativamente; viewport y texto forzados por el binding. No incluyen marco del SO, teclado ni selector nativo. CSV usa selección de fixture y Drive respuestas sintéticas.</p>
<p><a href="../prototipo/autofinance-v1.html">Prototipo HTML v1 aprobado</a> · <a href="../validacion-integral.md">Cobertura y límites</a> · <a href="windows-manifiesto.json">Manifiesto Windows</a> · <a href="android-manifiesto.json">Manifiesto Android</a></p>
<section><h2>Referencia · prototipo HTML aprobado</h2><p>Estas tres imágenes proceden del navegador; las siguientes proceden de la app nativa.</p><div class="grid">${[
  '../prototipo/capturas/windows-inicio-viewport.png',
  '../prototipo/capturas/android-inicio-viewport.png',
  '../prototipo/capturas/android-texto-200.png',
].map(figure).join('\n')}</div></section>
${sections}
<section><h2>CSV · recorrido existente reutilizado</h2><div class="grid">${imports.map(figure).join('\n')}</div></section>
</main></html>
`;
const destination = path.join(directory, 'index.html');
if (process.argv.includes('--check')) {
  if (readFileSync(destination, 'utf8') !== html) throw new Error('La galería necesita regenerarse.');
} else {
  writeFileSync(destination, html);
}
console.log(`Evidencia verificada: ${images.length} PNG; galería ${process.argv.includes('--check') ? 'reproducible' : 'generada'}. Aceptación final pendiente.`);
