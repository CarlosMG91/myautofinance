import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const directory = path.join(path.dirname(fileURLToPath(import.meta.url)), 'flutter-capturas');
const names = ['resumen', 'detalle', 'foto-ausente', 'foto-corregida', 'cero', 'restaurado',
  ...['calculable', 'foto-ausente', 'foto-incompleta', 'cero', 'ingresos-nulos', 'ingresos-negativos', 'ingresos-incompletos']
    .map(name => `320-200-${name}`)];
const manifests = [];
if (!fs.readFileSync(path.join(directory, 'android-back.txt'), 'utf8').includes('-> adb KEYCODE_BACK enviado')) {
  throw new Error('Falta el registro de Android Back enviado desde el host.');
}
for (const platform of ['windows', 'android']) {
  const runtime = JSON.parse(fs.readFileSync(path.join(directory, `${platform}-origen.json`), 'utf8'));
  if (runtime.platform !== platform || !runtime.syntheticDataOnly ||
      runtime.origin !== 'Native Flutter RenderRepaintBoundary' || !runtime.compactCapturesScrollToCard) {
    throw new Error(`Falta procedencia nativa/sintética verificable: ${platform}`);
  }
  const images = names.map(name => {
    const file = `${platform}-${name}.png`;
    const bytes = fs.readFileSync(path.join(directory, file));
    const width = bytes.readUInt32BE(16), height = bytes.readUInt32BE(20);
    if (bytes.readUInt32BE(0) !== 0x89504e47 || height !== 1000 ||
        width !== (name.startsWith('320-') ? 320 : platform === 'windows' ? 1440 : 412)) {
      throw new Error(`PNG o tamaño inesperado: ${file}`);
    }
    return { file, width, height, sha256: createHash('sha256').update(bytes).digest('hex') };
  });
  if (new Set(images.slice(6).map(image => image.sha256)).size !== 7) {
    throw new Error(`Las siete capturas compactas no distinguen sus estados: ${platform}`);
  }
  manifests.push({ runtime, images });
}
const manifest = `${JSON.stringify(manifests, null, 2)}\n`;
const html = `<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>MA-TSK-186 · Evidencia Flutter nativa</title><style>body{font:16px system-ui;margin:32px;color:#203136;background:#f6f5f1}main{max-width:1200px;margin:auto}section{display:flex;flex-wrap:wrap;gap:24px}figure{margin:0;width:340px}img{display:block;max-width:100%;height:auto;border:1px solid #c9d3d5}figcaption{margin:12px 0 28px}a{color:#176460}</style>
<main><h1>Indicadores · MA-TSK-186</h1><p>Capturas del runner Flutter Windows y Android con SQLite sintético. No proceden del HTML. Superficie forzada a 1440/412/320 × 1000; texto 200 % en los siete estados compactos. Estos se desplazan hasta la tarjeta para mostrar el resultado por debajo de los controles del shell. Pulsar una imagen abre su tamaño original.</p><p><a href="../vista-indicadores.md">Informe y límites de verificación</a> · <a href="manifiesto.json">Origen, dimensiones y SHA-256</a>. La aceptación visual final MA-TSK-217 es independiente.</p>
${manifests.map(({ runtime, images }) => `<h2>${runtime.platform === 'windows' ? 'Windows' : 'Android'}</h2><section>${images.map(image => `<figure><a href="${image.file}"><img loading="lazy" src="${image.file}" alt="${image.file}"></a><figcaption>${image.file}</figcaption></figure>`).join('')}</section>`).join('')}</main></html>\n`;
for (const [file, content] of [['manifiesto.json', manifest], ['index.html', html]]) {
  const target = path.join(directory, file);
  if (process.argv.includes('--check')) {
    if (fs.readFileSync(target, 'utf8').replace(/\r\n/g, '\n') !== content) {
      throw new Error(`Evidencia desactualizada: ${file}`);
    }
  } else {
    fs.writeFileSync(target, content);
  }
}
console.log('OK: 26 capturas nativas, siete estados distintos por plataforma, origen y tamaños verificados.');
