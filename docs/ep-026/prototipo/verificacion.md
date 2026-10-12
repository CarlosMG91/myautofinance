# Verificación · MA-TSK-207 · v1

Fecha: **2026-10-12**. Artefacto propuesto, **pendiente de aprobación humana**.
Rama configurada del checkout: `ticket/ma-tsk-113`; remoto `origin` de este
proyecto. La entrega propia se limita a `docs/ep-026/prototipo/`. README,
sincronización y mockups de otras épicas ya tenían cambios concurrentes.

## Artefacto revisado y publicación

- HTML autónomo: `autofinance-v1.html`.
- Publicación: `/mockups/autofinance-integral-v1.html` en Epic Board.
- SHA-256, idéntico en repositorio y publicación:
  `5f000e2db4ebac1c0678899c5f18ad2351e8aeedae202deb038cfe66158ed4f6`.
- HTTP **200** y apertura renderizada sin errores JavaScript. Recorrido
  publicado Inicio → Análisis → Real anual comprobado en navegador.
- `generar.mjs --check`: salida reproducible, sin diferencias entre fuentes
  y artefacto. Recursos incluidos, ninguna solicitud a terceros.

## Cobertura y comprobaciones

| Criterio | Resultado observado |
| --- | --- |
| T02/T03 | Cinco destinos, lateral PC/inferior Android, Gestión, Más con acceso directo a Real/Indicadores; mes/año visibles; tema claro y tokens/fuentes originales de T03. |
| Inicio y Estado | EP-001: enero real +1.229,75, previsto +1.100,00, diferencia +129,75; foto neta 14.000 independiente. Ocio abre ambos Café. Febrero no arrastra foto. |
| Presupuesto | 48 partidas y +13.200 anual, matriz de doce meses/total y tres niveles; alta padre conflictiva rechazada; propuesta Alimentación −360, edición/desglose −370 y sustitución de 2027 conservan 2026. |
| Real anual / desgloses | Año completo +2.329,65, matriz/cards, expansión independiente, directo/rama, Sin clasificar, subtotal y contador filtrados, restablecer ámbito original y volver. Neto cero de transferencia abre dos registros; cuenta solo para reales. |
| Patrimonio / indicador | Foto incompleta + valores cero válidos: febrero neto 11.900, colchón 2,07. Liquidez fechada de cartera: febrero 16.700 líquidos; enero permanece 9.000. Cinco motivos estables, fichas/meses pendientes y cero calculable. |
| Movimientos / categorías | Alta con signo, borrador preservado al cancelar salida, discrecionalidad/procedencia, selección individual/lote y rechazo íntegro al cambiar datos; catálogo rechaza cuarto nivel y conserva histórico al archivar. |
| Importación | Previsualización, normalización, referencia explícita, errores sin confirmación, revisión de solapamientos, muestra XLS, lote/procedencia, éxito +2 reales y repetición con 0 altas. No cambia fotos. |
| Drive / recuperación | Acciones manuales/confirmación, divergencia conserva datos, descarga inválida conserva local, copia completa previa, entrada sin base activa y restauración antes de abrir informes. |
| Diagnóstico | Ejecución/cancelación, severidad, detalle/origen, lectura fallida, resultado obsoleto y repetición explícita. Las dos filas idénticas del mismo CSV no generan por sí solas hallazgo de duplicado. No escribe datos ni limpia cambios locales. |
| Adaptación | **310** combinaciones: 31 destinos × 5 tamaños × 2 escalas. 1024×768, 1440×900, 360×800, 412×915 y 320×800; texto 100/200 %. Sin overflow de página ni controles/importes recortados según geometría del navegador. Matrices con scroll contenido intencional. |
| Accesibilidad HTML | Foco visible, etiquetas, estados anunciados, teclado Tab/Enter/Escape/retorno y protección de borradores, reducción de movimiento, alternativa textual visible a cada gráfico. SVG se omite cuando no cabe escala legible. Contraste hereda los tokens ya medidos de T03. |

El comprobador ejercita transiciones y invariantes de la muestra en memoria;
no prueba transacciones SQLite, validación real de archivos o llamadas Drive.
Los hallazgos del diagnóstico representan estados de presentación, no reglas
implementadas de EP-025. El detalle de cobertura/reutilización de suplementos
está en `traspaso.md`; ninguno se declara aprobado automáticamente.

## Calidad del repositorio

- Flutter **3.47.0**, Dart **3.13.0** y `check-toolchain.ps1`: correctos.
- `check-quality.ps1`: primer intento detenido por acceso de red a pub.dev;
  reintento con red, resolución fijada sin cambiar SDK/lockfile.
- Resultado: **376 archivos** formateados sin cambios, análisis sin
  incidencias, **1.640 pruebas** correctas, más las cuatro variantes de arranque
  development/test/production/invalid-synthetic.
- `docs/ep-001/verificar-casos.mjs`: correcto; contrato y fixtures intactos.
- Tokens CSS de T03 coinciden con JSON; sintaxis JS y generación correctas.
- Ningún cambio propio en `lib`, plataformas, `pubspec.lock` o toolchain.
  Calidad ejecutada sobre checkout compartido; no atribuye a T04 código ajeno.

No se ejecutaron builds nuevos: esta entrega no cambia plataformas ni la
aplicación Flutter. T05–T14 verificarán UI nativa, TalkBack/Narrador, Back
Android, escala del sistema, integración y builds Windows/Android según sus
tickets. La aprobación humana del diseño y el cierre de T04 siguen pendientes.

## Capturas renderizadas revisadas

Son capturas reales del **prototipo HTML en Chrome**, no de la app nativa.
Se inspeccionaron Inicio PC/Android, el detalle Real, diagnóstico y texto
200 %; se corrigieron navegación móvil, reflujo, corte de palabras, subtotales
y tamaño de textos de gráficos. Páginas completas y capturas de viewport se
conservan junto al artefacto.

- [Windows 1440×900](capturas/windows-inicio-viewport.png) ·
  [página completa](capturas/windows-inicio.png).
- [Windows 1024×768](capturas/windows-1024-viewport.png).
- [Real anual Windows](capturas/windows-real-viewport.png).
- [Android 412×915](capturas/android-inicio-viewport.png) ·
  [página completa](capturas/android-inicio.png).
- [Movimientos Android 360×800](capturas/android-360-viewport.png).
- [Tarjetas Real Android](capturas/android-real.png).
- [Diagnóstico Android](capturas/android-diagnostico.png).
- [320 px / texto 200 %](capturas/android-texto-200.png).

Reproducción mediante `verificar.mjs` con Node 22.20.0, Playwright 1.56.1
existente y Chrome local. Logs de calidad locales en `.tools/`, ignorados.
