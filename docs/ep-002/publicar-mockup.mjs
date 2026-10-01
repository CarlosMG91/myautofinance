import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const root = new URL('./', import.meta.url);
const read = name => readFileSync(new URL(name, root), 'utf8');
let html = read('prototipo/index.html');
html = html.replace('<title>Autofinance · Prototipo</title>', '<title>Autofinance · Propuesta final MA-TSK-019</title>');
html = html.replace('<link rel="stylesheet" href="style.css">', `<style>${read('prototipo/style.css')}</style>`);
html = html.replace('<details class="review">', `<details class="review" open><summary>Propuesta final · revisión y aprobación</summary>
<p><strong>MA-TSK-019 · Versión 1 · 1 de octubre de 2026.</strong> Cinco destinos estables: Estado, Patrimonio, Presupuesto, Real e Indicadores. El periodo se conserva al navegar.</p>
<p>Windows: tablas compactas con cifras alineadas y matriz anual desplazable. Android: tarjetas con etiquetas completas y navegación inferior; adaptación por debajo de 840 px. Paleta neutra y azul para acciones, signos y textos además del color, foco visible y controles móviles de 48 px.</p>
<p>Los presupuestos y reales tienen detalles separados. Las fotos manuales incompletas muestran «sin dato»; el cero registrado se distingue de la ausencia. Drive solo ofrece operaciones explícitas y confirmaciones simuladas.</p>
<p><strong>Para revisar:</strong> abrir las cinco vistas en enero y febrero de 2026; abrir Ocio (dos Café), completar la foto de febrero, preparar presupuesto 2027 y probar los errores de CSV y Drive desde Gestión. «Escenarios de revisión» permite restablecer los datos.</p>
<p><strong>Limitaciones:</strong> pruebas lógicas aprobadas; revisión visual en navegador, teclado real y Android físico pendiente por falta de superficies conectadas. CSV y Drive son escenarios predefinidos, sin persistencia ni servicios reales. La gestión de categorías es una representación simplificada. Esta propuesta conserva las limitaciones anotadas en MA-TSK-018.</p>
<p><strong>Aprobación pendiente:</strong> revisar este artefacto y aprobar explícitamente MA-TSK-019 en Epic Board, o solicitar cambios allí. La aprobación corresponde a la persona usuaria. No implementar pantallas Flutter antes de esa aprobación.</p></details><details class="review">`);
html = html.replace('MA-TSK-017 · Mockup pendiente de aprobación MA-TSK-019', 'MA-TSK-019 · Propuesta final v1 · aprobación humana pendiente');
for (const name of ['data', 'model', 'app']) html = html.replace(`<script src="${name}.js"></script>`, `<script>${read(`prototipo/${name}.js`).replaceAll('</script', '<\\/script')}</script>`);
const target = new URL('mockup-final.html', root);
writeFileSync(target, html, 'utf8');
console.log(`Mockup autónomo generado: ${fileURLToPath(target)}`);
