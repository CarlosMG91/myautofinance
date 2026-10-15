# MA-TSK-191 · Filtros y contexto de desgloses · suplemento v1

Propuesta del 2026-10-15, **pendiente de aprobación humana específica**.
No completa la aprobación del ticket ni inicia implementaciones posteriores.

Artefacto autónomo: [mockup-desgloses.html](mockup-desgloses.html).
Publicación en Epic Board: `/mockups/autofinance-ma-tsk-191-v1.html`.
SHA-256 del HTML: `de104ea8aa52d4adbe2881c715286969f66268d7ceca944a38281bff943c1a4a`.

## Referencia y límites

Se consultaron MA-TSK-191, MA-TSK-207 y los enlaces MA-TSK-162/170/178
mediante `GET http://localhost:4310/api/data`. Los tres enlaces constan
entregados. T04 figura completado con aprobación explícita del usuario:
«Propuesta visual aceptada: /mockups/autofinance-integral-v1.html» y
`approvedAt=2026-10-12T14:56:25.247Z`.

El suplemento reutiliza los estilos completos, fuentes Roboto y tokens del
HTML EP-026 v1 aprobado, sin modificarlo. Su disposición lateral/inferior,
tarjetas, controles, signos y mensajes siguen esa referencia y el kit T05.
Los cinco destinos globales se muestran como referencia; el recorrido de
este artefacto está limitado a origen → lista → detalle y retorno.
El informe se representa mediante un fragmento de contexto, no mediante
una nueva propuesta de informe ni una réplica de sus matrices.

Se leyeron EP-001 §2/§5, el traspaso de T04, los contratos de enlaces de
EP-019/021/022, la consulta de partidas MA-TSK-190 y los filtros EP-010.
El futuro desarrollo debe consumir esos enlaces y las listas/detalles
existentes. El JavaScript es exclusivamente una simulación con céntimos
enteros y registros sintéticos, sin servicios, SQLite, persistencia ni editor.
No añade fórmulas financieras, exportación, sincronización o acciones masivas.

La aprobación global fija apariencia y navegación, pero no concede aprobación
específica a estas variantes: filtros locales modificados, resultado paginado,
restablecimiento inválido y distinción entre cambios de datos y lectura fallida.
La aceptación de MA-TSK-191 debe citar este suplemento y su versión/ruta.

## Recorrido de revisión

Abrir la franja superior para elegir entradas y estados. La primera pantalla
ya presenta un desglose, con su origen siempre visible.

1. **Estado / Ocio:** −30,00 €, tres registros, incluidos dos Café distintos.
   Filtrar Cuenta diaria deja dos y −10,00 €. Se indica «Nuevo ámbito local»;
   la cifra al abrir sigue visible. «Restablecer filtros del informe» recupera
   los tres registros y −30,00 €. Buscar `cafe` encuentra ambos Café.
2. **Estado / presupuesto mensual:** enero, Alimentación, rama completa,
   −100,00 €. **Presupuesto anual:** −390,00 €, cuatro partidas. No aparecen
   cuenta, búsqueda de concepto ni «Sin clasificar». Probar mes, año y rango
   enero–febrero (−180,00 €); marzo contiene solo la partida directa −120,00 €.
   Los meses inclusivos se adaptan al contrato de consulta en la integración.
3. **Real anual / Alimentación:** −192,00 € de rama y −12,00 € solo directos.
   Categoría, alcance, cuenta y concepto son filtros locales, sin cambiar el
   informe de origen. «Todas las categorías» incluye reales sin clasificar.
4. **Ahorro neto cero:** −500,00/+500,00 €, dos cuentas y dos registros.
   **Estado / Salud vacío:** ningún registro, subtotal cero y origen conservado.
   **Sin clasificar:** +4,00 €, disponible exclusivamente en Movimientos.
5. **205 movimientos:** páginas de 100/100/5. Contador 205 y subtotal −205,00 €
   permanecen globales. Desplazar la lista, abrir un registro y volver conserva
   filtros, página, posición y foco del registro.
6. **Volver al informe:** conserva mes enfocado, rama abierta y posición del
   fragmento. Abrir su cifra y regresar restaura el foco de esa cifra.
   Escape / Alt+Izquierda hacen detalle → lista → informe. Contraer una rama
   es una acción separada de abrir su cifra. No hay navegación posterior
   implementada ni promesa de Back nativo a partir de esta simulación HTML.
7. **Simular cambio de datos:** cambia un importe de la muestra y reinicia
   la paginación. La lista indica que la cifra al abrir puede diferir; volver
   muestra el informe actualizado. Restablecer recupera filtros, no datos
   históricos. Abrir de nuevo captura la cifra actual como nuevo origen.
8. **Lectura fallida / Cargando:** no muestran contador ni subtotal válidos.
   Reintentar conserva filtros y origen. **Categoría eliminada:** impide
   restablecer un ámbito que dejó de existir y ofrece volver al informe.
   «Restablecer muestra» revierte todas las simulaciones.

## Cobertura y verificación

| Criterio | Evidencia revisable |
| --- | --- |
| Tipo y ámbito heredado | Tarjeta de origen: informe, periodo, categoría, rama/directos, cifra y número de registros |
| Cuenta solo REAL | Cuenta en filtros, origen y detalle real; ausente en partidas |
| Partidas sin Sin clasificar | Opción inexistente en su selector; categoría directa visible en detalle |
| Filtros locales y subtotal global | Nuevo ámbito explícito, referencia original conservada y fixture de 205 registros |
| Restablecer ámbito válido | Recupera filtros iniciales; no disponible cuando la categoría dejó de existir |
| Vacío, cero y duplicados | Tres entradas diferenciadas; identificadores individuales y apertura de cada registro |
| Detalle → lista | Conserva página, filtros, scroll de lista y foco |
| Lista → informe | Fragmento con periodo, mes enfocado, rama, scroll y foco de cifra; relectura tras cambio |
| Error frente a datos modificados | Estados separados, error sin agregados y aviso explícito de datos actuales |
| PC / Android / accesibilidad | Etiquetas, foco visible, controles de 48 px, signos y textos además de color; reflujo y texto ampliado |
| Tablas en detalle avanzado | Este suplemento usa listas existentes y tarjetas; no introduce matrices como entrada |
| Aprobación explícita | **Pendiente**, no inferida de tests ni de T04 |

Comprobaciones ejecutadas:

```powershell
node --check docs/ep-024/suplemento.js
node docs/ep-024/generar-mockup.mjs --check
node docs/ep-024/verificar-mockup.mjs
$env:MOCKUP_URL='http://localhost:4310/mockups/autofinance-ma-tsk-191-v1.html'
node docs/ep-024/verificar-mockup.mjs
git diff --check -- docs/ep-024
```

Resultado: ámbitos, filtros, duplicados, partidas/reales, vacío/cero, paginación,
restablecimiento, validación de intervalo, retorno/foco/scroll, carga/error y
cambios correctos, sin errores JavaScript. Comprobados anchos 1440, 1024, 412,
360 y 320 px y texto 200 % a 320 px, sin desbordamiento horizontal de página.
En texto ampliado, los selectores usan etiquetas breves (Rama/Directos,
Todas/Diaria/Ahorro), el ámbito mantiene los nombres completos y los meses
se introducen como AAAA-MM para evitar recortes del control nativo del navegador.

Capturas en [capturas](capturas/), inspeccionadas visualmente: **HTML en Chrome
headless**, no capturas de Flutter, goldens ni runner Windows/Android.
La navegación global mostrada es contexto visual; la aprobación de T04 sigue
siendo la fuente para las pantallas completas.

No se cambia Flutter ni plataformas, SDK o lockfile; no se ejecutan análisis,
pruebas Flutter o builds para esta entrega HTML. Narrador/TalkBack, Back del
sistema, fechas/controles/foco/escalado nativos, parsers reales y relectura
SQLite tras escrituras requieren los tickets de integración. Las pruebas de
esta propuesta no acreditan esas integraciones ni la aceptación final EP-026.

Solo se incluyen archivos propios de este suplemento; `consulta-partidas.md`
y los cambios concurrentes de sincronización y otras propuestas quedan fuera.
