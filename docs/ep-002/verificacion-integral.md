# MA-TSK-018 · Verificación integral del prototipo

Fecha: 2026-10-01. Referencia: prototipo de MA-TSK-017, contrato aprobado EP-001 y guiones de MA-TSK-014. Solo datos sintéticos. **Estado: verificación lógica ejecutada y revisión estática realizada; aceptación integral pendiente por falta de navegador conectado.** No solicitar todavía aprobación de MA-TSK-019 ni implementar pantallas Flutter.

El ticket y la regla de cierre se consultaron en el contenido proporcionado en la conversación. No hay herramienta Epic Board disponible para contrastar o actualizar su estado. El inventario de control del equipo devolvió `apps: []` y `browsers: []`; no se pudo abrir el prototipo ni obtener capturas. No se han ejecutado pruebas visuales en Windows ni Android, ni se ha validado tacto físico. La revisión estática de CSS no acredita un tamaño de pantalla ejecutado.

## Comprobaciones ejecutadas

Desde la raíz:

```text
node docs/ep-001/verificar-casos.mjs
node docs/ep-002/prototipo/verificar.mjs
node docs/ep-002/prototipo/verificar-integral.mjs
node --check docs/ep-002/prototipo/app.js
git diff --check
```

Resultado: OK. Los comprobadores del prototipo ejecutan JavaScript y sus manejadores mediante un DOM simulado. No implementan el motor de layout, validación nativa de formularios, navegación de Tab, Esc, lector de pantalla ni eventos táctiles. No hay módulo Flutter que analizar o probar.

| Recorrido | Resultado comprobado en el modelo/manejadores |
|---|---|
| Cinco vistas y periodo | Generación de contenido para Estado, Patrimonio, Presupuesto, Real e Indicadores; cambio de mes. |
| CSV de referencia | Cada registro sintético coincide con fecha, concepto, ruta, cuenta, discrecionalidad e importe CSV; presupuesto invierte signo y real lo conserva. 48 partidas y 10 reales; los dos Café siguen separados y suman −20,00 €. |
| Estado y matrices | Enero +1.229,75 €, previsto +1.100,00 €, diferencia +129,75 €; febrero +1.099,90 €, diferencia −0,10 €. Anual real +2.329,65 €, previsto +13.200,00 €. La rama Alimentación conserva −350,25 € en los tres niveles sin volver a sumar las hojas. |
| Foto e indicador | Enero neto 14.000,00 € y 3,00 meses; febrero ausente y parcial: sin dato. Completar con ahorro cero: neto 11.900,00 € y 2,07 meses. Corregir principal a 6.300,00 €: neto 12.000,00 €, enero intacto. Foto negativa rechazada. Ingresos incompletos, nulos y negativos producen sus motivos; liquidez cero produce 0,00 meses. |
| Propuesta 2027 | Enero Alimentación −360,00 €, febrero −430,00 €, marzo cero explícito. Cancelar e importe inválido no guardan. Editar a −370,00 € y desglosar retira el padre, conserva agregado y 2026. Guardar requiere segunda confirmación. Conflicto Vivienda/Alquiler bloqueado. |
| Clasificación, caso J | Total +1.224,75 €, sin clasificar +4,00 €; directo corregido a +4,00 €. Cancelar no cambia datos. Clasificar abono +7,00 € deja −3,00 € sin clasificar, conserva total y foto. |
| Importación simulada | Base vacía → revisión → confirmar: 58 registros. Repetición: cero altas. Fecha inválida, referencias pendientes y solapamiento bloquean botón; previsualizar y cancelar no escriben. |
| Drive simulado | Subida normal y primera subida sin copia; descarga sin copia; divergencia, versión desconocida, cambio durante publicación, respuesta perdida, conexión y autenticación no anuncian éxito ni cambian datos. Descarga cancelada y fallos de validación/respaldo/apertura conservan estado. Descarga confirmada recupera copia publicada; restaurar devuelve datos locales previos. No hay transferencia real. |
| Foco | Referencia del disparador conservada al encadenar lista/editor; búsqueda del botón regenerado al restaurar foco. Comprobación lógica, pendiente de navegador. |

## Fallos corregidos

| Incidencia | Cambio y evidencia |
|---|---|
| El directo de «Sin clasificar» comparaba con un nombre de categoría inexistente y mostraba 0,00 € | Comparar con ruta vacía. Regresión del caso J comprueba +4,00 €. |
| El detalle de presupuesto de «Sin clasificar» ofrecía crear partida | Retirar esa acción: es grupo de informe, no categoría. Regresión comprueba ausencia del botón. |
| Diálogos encadenados sustituían el origen de foco por un botón del diálogo que después desaparecía | Capturar origen solo al abrir; restaurar por identificador/acción tras regenerar. Navegación también conserva referencia de foco. Prueba lógica del retorno al disparador. |
| El importe aceptaba valores fuera de la precisión exacta de céntimos de JavaScript | Rechazar enteros no seguros. Regresión con importe enorme; cero real e importes mal formados no guardan. |
| Controles de ancho intrínseco podían exceder el diálogo estrecho | Limitar ancho y permitir contracción; conservar checkbox con ancho propio. Revisión de código; resultado visual pendiente. |
| El contenedor anual no era enfocable para desplazarlo con teclado | Añadir `tabindex`, región etiquetada y foco visible. Revisión de código; desplazamiento real pendiente. |
| Los desplegables móviles tenían área pequeña | Aumentar área de `summary` a 48 px en el modo móvil. Pendiente medir en navegador. |

## Lista visual y de interacción pendiente

Ejecutar los siete recorridos del [README del prototipo](prototipo/README.md) en **cada tamaño**. Anotar navegador, tamaño efectivo, fecha, resultado e incidencias; guardar capturas sintéticas de las cinco vistas y formularios. La tabla registra el estado real de esta sesión, sin convertir una inspección de código en prueba visual.

| Superficie / tamaño CSS | Tablas o tarjetas previstas | Legibilidad y cifras completas | Recorridos interactivos | Teclado / tacto |
|---|---|---|---|---|
| PC 1440×900 | Tablas | Pendiente | Pendiente | Pendiente teclado |
| PC 1024×768 | Tablas con desplazamiento anual interno | Pendiente | Pendiente | Pendiente teclado |
| Android 412×915 | Tarjetas y navegación inferior | Pendiente | Pendiente | Pendiente tacto |
| Android 360×800 | Tarjetas y navegación inferior | Pendiente | Pendiente | Pendiente tacto |
| Estrecha 320×800 | Tarjetas y formularios contraídos | Pendiente | Pendiente | Pendiente |
| PC a zoom 200 % y Android con texto ampliado | Adaptación al ancho efectivo | Pendiente | Pendiente | Pendiente |

- Comprobar ausencia de recorte, solapamientos con barra inferior y desplazamiento horizontal del documento; solo la matriz PC debe necesitar desplazamiento interno.
- Leer signos, dos decimales, rutas largas, «sin presupuesto», cero explícito, «sin dato» y motivos. Verificar datos de la tabla anterior en ambas presentaciones.
- Recorrer con Tab/Mayús+Tab, activar con Intro/Espacio, desplazar matriz con teclado, cerrar con Esc; comprobar foco visible, contención modal y retorno al disparador después de cancelar y guardar.
- Medir objetivos táctiles, abrir/cerrar doce meses y ramas, usar formularios con teclado virtual y desplazarse hasta guardar/cancelar. Probar en Android real además de emulación.
- Probar errores y reintentos desde interfaz, incluido cancelar propuesta, edición, importación y descarga con cambios locales; verificar vista y periodo de retorno.

## Incidencias de alcance anotadas antes de aprobación

Además del bloqueo visual, el prototipo tiene simplificaciones observables en el código respecto a MA-TSK-014. Permanecen anotadas para resolver o aceptar expresamente en la revisión humana; no son funcionalidades verificadas:

1. Gestión sustituye la vista principal y carece de una acción explícita de retorno al origen. La barra permite ir a otra vista; conserva año/mes. Los diálogos secundarios sí cierran al destino que los abrió.
2. Categorías es una lista de consulta: no simula altas, validación de cuarto nivel ni regreso al selector con un nodo nuevo. Patrimonio usa cuatro fichas fijas: altas/bajas y vigencia del caso D no están simuladas.
3. CSV usa escenarios cerrados y un resumen, sin selector de archivos, tabla completa de filas/ordinales, resolución interactiva de referencias ni decisión de continuar un solapamiento. XLS permanece anunciado como pendiente, sin recorrido ilustrativo X1/X2.
4. Propuesta presenta 60 campos en una columna en ambas superficies; no tiene tabla compacta PC, resumen comparativo completo de sustituciones ni aviso de signo inusual. No se ha medido su facilidad de uso.
5. Drive opera en memoria y utiliza fecha fija. No simula progreso, una transferencia realmente interrumpida ni publicación remota efectuada con respuesta perdida; no acredita SQLite, concurrencia real o recuperación entre dispositivos.

Para cerrar MA-TSK-018 falta ejecutar y registrar la matriz visual/interactiva, y resolver o acordar las incidencias pendientes. La aprobación humana sigue siendo MA-TSK-019; este informe no la concede.
