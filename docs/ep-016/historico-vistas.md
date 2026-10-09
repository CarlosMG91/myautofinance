# MA-TSK-143 · Histórico de las vistas entregadas

Ticket y requisito MA-TSK-142 consultados en la API local de Epic Board,
tablero **My autofinance**, el 2026-10-09. MA-TSK-142 consta completado y
MA-TSK-141 registra la aceptación humana del mockup de periodos.

Se reutilizan el [contrato de sesión](periodo-sesion.md), los
[controles comunes](integracion-navegacion.md), la
[entrega EP-002](../ep-002/entrega-flutter.md) y las reglas/casos de
[EP-001](../ep-001/especificacion.md), sin nuevos cálculos financieros.

## Consultas y navegación

- Gestión abre Movimientos con el mes común actualmente elegido, también
  desde Patrimonio y Presupuesto mensual. Un listado sin periodo explícito
  sigue la sesión. Los enlaces con mes o rango y los filtros aplicados en
  el listado tienen prioridad local; no cambian el periodo de las pestañas.
- Movimientos reutiliza `readPage`: fecha de valor, límite superior exclusivo
  y subtotal firmado de toda la consulta. Un periodo vacío devuelve cero y
  ninguna fila. Las etiquetas mantienen cuentas cerradas y ramas archivadas.
- Presupuesto mensual reutiliza `MonthlyBudgetQuery`: ausencia de partida y
  cero registrado siguen siendo estados distintos; el histórico archivado
  permanece incluido. La consulta no crea partidas ni propone un año nuevo.
- Patrimonio reutiliza `readYear` y elige la foto exacta del día 1 del mes.
  Un mes ausente o incompleto permanece «Sin dato». Las doce fotos se muestran
  individualmente, sin arrastrar otra foto ni producir una suma anual.

Cambiar periodo reinicia posición/foco, selección y cursores de movimientos.
Los consumidores capturan el periodo de cada consulta y descartan respuestas
anteriores. Presupuesto elimina sus cifras al iniciar una nueva lectura;
Patrimonio oculta el contenido anterior mientras espera el nuevo futuro.
Un error presenta el fallo del periodo consultado y permite reintentar;
no etiqueta como actuales los datos de un mes anterior.

Los detalles conservan la instancia y consulta de origen, con filtros,
selección/página, scroll y foco. Presupuesto y Patrimonio publican la posición
en el contexto de sesión; Movimientos captura su contexto local para el editor.
El retorno restaura el scroll tras reconstruir las filas, con nodos de foco
estables. Los cambios de periodo invalidan también las restauraciones tardías.
La protección de borradores existente sigue autorizando la salida.

Guardar un movimiento fuera del rango original, aunque sea en el mismo mes,
informa del mes guardado y ofrece **Ver mes**. Esa acción abre una consulta
mensual local; volver recupera el rango de origen. Guardar una partida en otro
mes también conserva el origen; **Ver mes** abre ese presupuesto mensual y
el retorno restaura el anterior. No se cambia el origen durante el guardado.

La adaptación vive en `app` y se inyecta por constructor. Ninguna funcionalidad
importa `app`; no se añaden persistencia de preferencias, importadores,
servicios de sincronización ni informes pendientes.

## Verificación

`test/historical_views_test.dart` usa SQLite en memoria y datos sintéticos:
ausente/incompleto/cero, futuro sin escrituras, histórico cerrado/archivado,
default común y prioridad local, selección/página ante una lectura tardía,
errores sin cifras previas, guardados fuera de rango/mes, cancelación de
borrador y retorno con scroll/foco. Patrimonio se comprueba a 400 y 1440 px.

La suite general incluye las regresiones de EP-009/010/011, navegación,
controles y arquitectura. El guion de Movimientos espera también la escritura
de un lote mientras el listado es la ruta actual; los diálogos siguen pudiendo
operarse sin esperar a que termine el lote que están confirmando.

Verificación local del 2026-10-09:

- Flutter 3.47.0 y Dart 3.13.0 comprobados mediante `flutter --version` y
  `check-toolchain.ps1`; `flutter pub get --enforce-lockfile` correcto y
  lockfile sin cambios.
- `scripts/check-quality.ps1`, con concurrencia 2 en las pruebas mediante una
  función PowerShell local, sin modificar el script versionado: formato de
  304 archivos sin cambios y análisis sin incidencias. La suite completa
  terminó con **1420 pruebas correctas y un fallo**: timeout de 45 segundos
  al cerrar SQLite en el recorrido de presupuesto Windows. Por tanto,
  **el script completo no terminó verde**. La incidencia de cierre ya está
  documentada en [MA-TSK-140](periodo-sesion.md); no se declara corregida.
- Repetición secuencial de los dos recorridos de presupuesto y los doce casos
  de histórico: **14 pruebas correctas**, sin reproducir el timeout.
- Recorrido Android de Movimientos comprobado aisladamente tras ajustar la
  espera del guion; los dos recorridos también pasan en la suite general.
- Arranque comprobado por separado en development, test, production e
  invalid-synthetic: todos correctos, incluido el fallo seguro esperado.
- `git diff --check` correcto. Logs en `.tools/`, ignorado:
  `ma-tsk-143-quality-verified.log`, `ma-tsk-143-isolated-final.log`,
  `ma-tsk-143-lifecycle-retry.log` y `ma-tsk-143-env-*.log`.

La evidencia de widgets no acredita ejecución
nativa Windows/Android ni el recorrido integral de MA-TSK-146. No se modifican
proyectos de plataforma ni se implementan los contratos de informes pendientes
de MA-TSK-144.

Los archivos de sincronización, README y prototipos concurrentes quedan fuera
del commit. Se conserva la rama configurada `ticket/ma-tsk-113` y su `origin`.
