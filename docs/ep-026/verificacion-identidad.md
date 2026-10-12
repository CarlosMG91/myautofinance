# MA-TSK-206 · Verificación de identidad

Fecha: **2026-10-12**. Ticket/criterios leídos de Epic Board por API local,
tablero My autofinance. Rama configurada: `ticket/ma-tsk-113`.
Entrega exclusivamente en `docs/ep-026/identidad-visual.md`,
`docs/ep-026/identidad/` y este informe. No incorpora los cambios concurrentes
de README, sincronización u otros mockups.

## Cobertura y evidencia

| Criterio | Evidencia revisable |
| --- | --- |
| Identidad propia clara/moderna | Paleta marfil/petróleo, tokens normativos, jerarquía tipográfica y cifras protagonistas; guía y galería. |
| Siete ejemplos | Resumen, categoría, movimiento, cuenta, formulario, aviso y tabla avanzada en HTML renderizado. |
| Recursos compatibles sin red | Tres Roboto locales con Apache 2.0, créditos/hashes; SVG originales. Solicitudes externas bloqueadas en comprobador y apertura directa `file://` verificada. |
| EUR, céntimos, signos y estados | Ejemplos EP-001; cero/ausencia separados; salida neutra; diferencia Favorable/Desfavorable etiquetada; sin presupuesto no se presenta como partida cero. |
| Barras/series accesibles | Cuatro casos de barras con eje firmado común y tabla; serie con unidades/periodo y huecos explícitos, dos puntos aislados enero/abril. |
| Distribución patrimonial segura | Completa, incompleta, activos cero, magnitud inválida y total incoherente; deuda separada, sin gráfico parcial ni división por cero. |
| Límites del producto | No motores, fórmulas, objetivos, score, oscuro, servicios remotos o assets de terceros copiados; no cambia contrato financiero ni navegación T02. |
| Referencias públicas | URL, fecha y evidencia observada por fuente en la guía; lectura pública de texto/descripciones, sin revisión autenticada de apps. |

## Reproducción

Con Node y Playwright disponible (no cambia dependencias Flutter):

```powershell
node docs/ep-026/identidad/generar-tokens.mjs --check
node docs/ep-026/identidad/verificar-identidad.mjs
```

El comprobador admite `PLAYWRIGHT_MODULE` para una instalación existente y
`CHROME_PATH` para el Chromium/Chrome local; si no se indican usa el paquete
`playwright` y su navegador. En este entorno se usó Node 22.20.0, Playwright
1.56.1 ya instalado en `.tools/ma-tsk-141-browser/node_modules/playwright` y
Chrome local. No requiere guardar capturas o assets de páginas de referencia.
Levanta un servidor de pruebas solo en loopback/puerto efímero y lo cierra.

## Resultados

- **19 pares de contraste correctos**: texto principal 14,02:1 sobre blanco;
  secundario 6,36:1; botón 6,96:1; estados ≥6,44:1; borde funcional 3,93:1.
- CSS generado coincide con tokens, hashes y licencia de fuentes correctos.
- Comprobador financiero existente `docs/ep-001/verificar-casos.mjs`: **OK**,
  48 presupuestos/10 reales, enero +1.229,75 €, real anual +2.329,65 € y
  presupuesto anual +13.200,00 €. Sin modificar el contrato/fixtures.
- Galería: **OK**; tres pesos locales, ningún recurso remoto, ningún error
  JavaScript; escenarios de barras, distribución y huecos comprobados.
- Formulario sintético: error vinculado al campo y foco, corrección sin
  persistencia y restablecimiento. Tab/Enter y foco de 3 px comprobados.
- Sin overflow de página a 320/360/412/840/1024/1440 px. Texto cuerpo 32 px
  al 200 % y sin overflow a 320/412/1024/1440; alternativas gráficas visibles.
  El scroll horizontal de la tabla íntegra es intencional y queda contenido.
- Reducción de movimiento: sin animaciones/scroll animado.
- Flutter 3.47.0 / Dart 3.13.0 y `check-toolchain.ps1`: correctos. El script
  `check-quality.ps1` inicialmente se detuvo en pub.dev por red restringida;
  reintento con red para resolver dependencias fijadas, sin cambio de lockfile.
  **Resultado final correcto**: formato de 376 archivos sin cambios, análisis
  sin incidencias, **1.640 pruebas** correctas y las cuatro variantes de
  arranque development/test/production/invalid-synthetic correctas. Se ejecutó
  sobre el checkout compartido; no atribuye los cambios concurrentes a T03.
- `git diff --check` de los archivos propios: sin errores. SDK, pubspec y
  lockfile no modificados por este ticket.

Logs locales ignorados `.tools/ma-tsk-206-identidad-final.log` y
`.tools/ma-tsk-206-quality-red.log`; el informe contiene los resultados
portables, sin paths de herramientas personales ni datos reales.

## Revisión visual real del HTML

Se inspeccionaron capturas renderizadas de página completa Windows/Android,
resumen Windows, gráficos Windows y texto ampliado. Fondo/acento y jerarquía
son coherentes; signo/céntimos legibles; negativos van a la izquierda de cero;
meses ausentes quedan sin líneas; deuda queda fuera de las barras de activos.
Son evidencias de la **galería de diseño**, no de ejecución nativa.

- [Resumen Windows 1440×1000](identidad/capturas/windows-resumen.png).
- [Gráficos Windows](identidad/capturas/windows-graficos.png).
- [Resumen Android 412×915](identidad/capturas/android-resumen.png).
- [Texto 200 % a 412×915](identidad/capturas/texto-200-resumen.png).
- Páginas completas: [Windows](identidad/capturas/windows.png),
  [Android](identidad/capturas/android.png),
  [texto ampliado](identidad/capturas/texto-200.png).

No se ejecutaron builds ni nueva UI nativa: no hay cambios en Flutter,
plataformas o dependencias de aplicación. TalkBack/Narrador, escala nativa,
kit completo y recorridos financieros de pantallas rediseñadas esperan T04/T05
y los tickets de implementación. La aprobación explícita del prototipo global
MA-TSK-207 sigue pendiente; esta entrega no la sustituye.
