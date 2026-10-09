# MA-TSK-142 · Controles comunes en la navegación principal

## Fuentes y aprobación

Ticket y requisitos consultados en la API local de Epic Board, tablero
**My autofinance**, el 2026-10-09. MA-TSK-140 y MA-TSK-141 constan `done`.
La discusión humana de MA-TSK-141 registra «Propuesta visual aceptada:
/mockups/autofinance-ma-tsk-141-v1.html». Esa aceptación supera el estado
histórico pendiente de [la propuesta retenida](propuesta-periodos.md).
Se usan el [contrato de sesión](periodo-sesion.md), la
[entrega EP-002](../ep-002/entrega-flutter.md) y EP-001.

## Integración

`PeriodControls`, compuesto en app, ofrece Año, Mes / Mes enfocado,
Ir al periodo, Mes / Año anterior y siguiente, y Mes actual. Los años
0001–9999 no dependen de registros disponibles. Elegir un mes aplica esa
selección explícita de inmediato al año consultado, tras proteger el borrador,
y prevalece sobre la memoria anual. Ir al periodo aplica el año introducido con las
reglas mensuales/anuales de `NavigationSession`. Mes actual consulta el reloj
inyectado de Europe/Madrid y conserva el destino.

Los cinco destinos reciben la misma sesión. Patrimonio y Presupuesto mensual
reciben el componente por constructor, sustituyendo sus selectores visibles.
Los widgets aislados conservan sus controles previos para sus consumidores sin
sesión; en la aplicación hay un solo selector. El presupuesto entregado por
EP-011 continúa siendo mensual. Real y Presupuesto todavía técnicos reciben
año de consulta y mes enfocado; Estado e Indicadores reciben mes. Sus mensajes
identifican el periodo validado sin fabricar cifras de informes pendientes.

La navegación principal sustituye las pestañas sin formar una pila de retorno.
Se conservan rutas públicas, validación anterior a consultas y argumentos
internos. Las secundarias continúan usando push/pop y el observador de sesión.
Desde los destinos técnicos, Gestión y los enlaces a movimientos serializan
el contexto actual, aunque el periodo haya cambiado desde la apertura de la
ruta. Se conservan todas las entradas de Gestión existentes.

En Presupuesto, el callback de cambio ejecuta la protección de borrador
existente antes de publicar el periodo: Seguir editando, Escape y cierre del
diálogo conservan la celda; Descartar cambios permite consultar el nuevo mes.
Las pestañas y formularios conservan sus protecciones previas. Visitar meses
pasados/futuros solo consulta; no activa guardados ni crea registros.

Al cruzar 840 px, el contenido mantiene su posición en el árbol de widgets,
conservando ruta, entradas de los controles y borrador. Los controles envuelven
y permiten operar a 320 px y con texto 200 %. No se añaden preferencias,
persistencia de navegación, sincronización ni nuevas reglas financieras.

Los filtros, selección de movimientos, resultados tardíos y publicación de
scroll/foco de cada consumidor pertenecen a MA-TSK-143. La conexión mínima
de los controles con las dos vistas entregadas no sustituye ese ticket.
Los informes futuros y su traspaso pertenecen a MA-TSK-144; aquí no se
implementan ni se simulan como datos reales.

## Evidencia

`test/period_controls_test.dart` comprueba con widgets reales:

- Inicio en Madrid junto al cruce de fecha UTC y diciembre/enero.
- Selección directa, años históricos/futuros, límites e invalidación segura.
- Cinco pestañas sin pila, memoria anual y mes enfocado independiente.
- Mes actual conservando destino, cambio de tamaño, teclado y texto 200 %.
- Patrimonio y Presupuesto mensual con un único selector y lecturas SQLite.
- Ausencia patrimonial y presupuesto ausente, sin modificar revisión SQLite.
- Seguir editando y Descartar cambios ante cambio de periodo/pestaña.
- Borrador y entrada de año conservados al cambiar de tamaño.
- Entradas de Gestión y retorno al periodo seleccionado antes del detalle.

Se adaptan las pruebas del título de Indicadores para distinguirlo de su nueva
etiqueta de navegación y el retorno de copias para incluir el periodo de sesión.
Las pruebas previas de sesión, rutas, arquitectura y
módulos siguen formando parte de la verificación.

Verificación local del 2026-10-09:

- Flutter 3.47.0 / Dart 3.13.0 comprobados; resolución con
  `flutter pub get --enforce-lockfile` sin modificar el lockfile.
- Nueve pruebas nuevas de controles correctas. Reejecución secuencial de los
  módulos afectados (controles, Gestión, copias y patrimonio): 70 correctas.
- La primera suite completa detectó expectativas antiguas de título/retorno y
  selección diferida del mes; se corrigieron para respetar el mockup aprobado.
  También falló la actualización de una foto, incidencia ya registrada en
  MA-TSK-140. No se reprodujo en la reejecución secuencial; no se declara
  corregida esa intermitencia de almacenamiento.
- La ejecución final de `scripts/check-quality.ps1` limita Flutter test a dos
  procesos mediante una función PowerShell local que añade `--concurrency=2`.
  Terminó correctamente: formato de 303 archivos sin cambios, análisis sin
  incidencias, 1409 pruebas correctas y arranque correcto en development, test,
  production e invalid-synthetic (fallo seguro esperado). No se modifica el
  script versionado. `git diff --check` también correcto.
  Los logs permanecen en `.tools/`,
  ignorado (`ma-tsk-142-quality-verified.log` y `ma-tsk-142-regressions-final.log`).

No se han modificado proyectos de plataforma ni ejecutado builds o recorridos
nativos Windows/Android. La evidencia de widgets no acredita ejecución física,
lector de pantalla o Android Back nativo. La verificación de informes pendientes
y el recorrido integral de EP-016 no se declaran completados por este ticket.

Los cambios concurrentes de sincronización, README y prototipos quedan fuera
del commit. Se conserva la rama configurada `ticket/ma-tsk-113` y `origin`.
