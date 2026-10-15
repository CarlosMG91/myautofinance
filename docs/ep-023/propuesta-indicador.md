# MA-TSK-185 · Suplemento Colchón de emergencia v1

15 de octubre de 2026. **Pendiente de aprobación humana explícita.**

Artefacto: [mockup-colchon-v1.html](mockup-colchon-v1.html).
Revisión en Epic Board: `/mockups/autofinance-ma-tsk-185-v1.html`.
Requiere Epic Board local activo en <http://localhost:4310>.
HTTP 200 y bytes idénticos a la copia retenida, SHA-256:
`563a954739b0dd6d7c3d974ad02b57e9ef613edb64b49c7736e0cfb908ddd225`.

## Referencia y alcance

Consultados mediante GET `/api/data` el tablero My autofinance, MA-EPIC-181,
MA-TSK-185 y sus criterios; T01–T03 constan terminados. Se revisaron EP-001
§6.1 y el contrato entregado de EP-023. La referencia global es EP-026 v1,
aprobada explícitamente en MA-TSK-207 según su [registro](../ep-026/prototipo/aprobacion.md).
El generador verifica el SHA-256 del HTML global aprobado antes de derivar
el suplemento; no modifica sus fuentes ni el kit Flutter.

El [traspaso](../ep-026/prototipo/traspaso.md) identifica cobertura global
para 3,00/0,00 meses, cinco motivos, fichas/meses pendientes, acciones y carga/error.
Esta versión conserva shell, tokens, Roboto, controles y destinos de ese HTML,
añadiendo acceso directo a los siete escenarios, entradas visibles en tarjeta,
textos estables EP-001, pendientes por nombre y explicación de nulos/negativos.
Estas variantes requieren aprobación específica: no se infiere de T04 ni de
pruebas automáticas. Resumen como entrada; precedencia completa en Ver detalle.
No se introducen tablas como vista principal, indicadores extra, umbrales ni consejos.

## Cobertura y recorrido de revisión

Abrir la franja superior «Suplemento Colchón v1» para cambiar escenarios.
Todos los datos son sintéticos y las ediciones solo viven en memoria.

| Criterio | Evidencia revisable |
| --- | --- |
| PC/Android, mes y año, valor en meses con dos decimales | Entrada Indicadores, enero 2026, 3,00 meses; lateral PC y Más/Análisis móvil del prototipo global |
| Entradas y fórmula | Tarjeta: líquidos 9.000,00 €, anual +36.000,00 €, promedio +3.000,00 €, fórmula y explicación de precisión; deuda excluida |
| Cero distinto de ausencia | Escenario Cero calculable: 0,00 meses, texto propio, foto completa e ingresos positivos |
| Foto ausente | Febrero, `foto_ausente`, cuatro fichas pendientes, Registrar foto del mes → captura de febrero 2026 |
| Foto incompleta | Febrero, `foto_incompleta`, Cuenta de ahorro y Cartera pendientes, Corregir foto del mes → captura de febrero 2026 |
| Ingresos incompletos | `ingresos_incompletos`, marzo 2026 pendiente, Completar marzo → captura mensual de marzo 2026; Volver restaura enero y el motivo |
| Ingresos cero/negativos | `ingresos_nulos` / `ingresos_negativos`, explicación y Revisar presupuesto de 2026 → captura mensual existente |
| Textos y precedencia | Ver detalle enumera los cinco códigos y textos exactos EP-001 en orden; el resultado principal presenta un único motivo |
| Carga/error técnico/reintento | Estado de consulta Cargando/Error; sin valor ni motivo financiero; Reintentar recupera el escenario conservado |
| Contexto y accesibilidad | Mes/año visibles; Volver conserva origen; etiquetas, foco visible, Tab/Enter/Escape/Alt+Izquierda heredados, reflujo 320 px y Texto 200 % |

Recorrer las acciones de foto y presupuesto, editar la muestra con controles
existentes y volver para revisar presentación y contexto. Restablecer muestra
recupera enero. En Ver detalle comprobar la explicación de raíz marcada como
ingreso, suma firmada, doce meses explícitos y foto completa de todas las fichas.

## Verificación y límites

- `node --check docs/ep-023/mockup-suplemento.js`: correcto.
- `node docs/ep-023/generar-mockup.mjs --check`: referencia aprobada y reproducción correctas.
- `node docs/ep-023/verificar-mockup.mjs`: siete escenarios, cinco motivos,
  cifras base, cero válido, detalle, destinos/retorno de foto y mes pendiente,
  carga/error/reintento, 35 combinaciones de ancho/estado a 320/360/412/1024/1440,
  texto 200 %, sin errores JavaScript ni solicitudes externas. Compara bytes HTTP.
- Capturas HTML conservadas e inspeccionadas: [PC](capturas/pc.png),
  [Android](capturas/android.png), [texto 200 %](capturas/texto-200.png).
  La barra móvil fija se superpone al punto de scroll en captura de página
  completa; las acciones se alcanzan desplazando la página.

Para repetir, usar `PLAYWRIGHT_MODULE` apuntando a Playwright instalado y
`CHROME_PATH` al ejecutable de Chromium/Chrome; `MOCKUP_URL` admite otra copia
publicada del mismo HTML. El generador no necesita paquetes externos.

No hay cambios Dart/plataforma: no se ejecutan calidad ni builds Flutter.
Las capturas proceden del navegador HTML, no del runner Windows o Android.
No se acredita TalkBack/Narrador, Back nativo, persistencia SQLite, cálculo
financiero de producción ni precisión del JS heredado del prototipo global.
El motor exacto entregado conserva su propietario; este HTML es solo evidencia
de presentación e interacción y no debe copiarse como servicio real.

## Aprobación y entrega

La persona usuaria debe aprobar explícitamente «MA-TSK-185 · suplemento v1»
y su ruta. Después registrar autor, fecha, evidencia literal y hash aprobado.
No se completa el ticket ni se implementan sus tickets posteriores antes de
esa aprobación. El registro global T04 no aprueba automáticamente este suplemento.

Solo se confirman y suben los archivos de esta propuesta en `docs/ep-023`;
se conserva la rama configurada `ticket/ma-tsk-179` y no se incluyen cambios
concurrentes de sincronización, categorías, bandeja ni documentación ajena.
