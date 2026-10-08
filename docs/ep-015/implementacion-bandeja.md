# MA-TSK-135 · Bandeja Flutter de importados pendientes

## Aprobación y alcance

Se consultó `GET http://localhost:4310/api/data`, tablero **My autofinance**,
workspace de este repositorio, el 2026-10-08. MA-TSK-133 y MA-TSK-134 figuran
`done`; MA-TSK-135 contiene los criterios facilitados por el usuario.
El suplemento v1 de MA-TSK-133 tiene `approvedAt: 2026-10-08T16:09:36.380Z`
y discusión de **Tú**: «Propuesta visual aceptada:
http://localhost:4310/mockups/autofinance-ma-tsk-133-v1.html».
Las etiquetas «pendiente» del artefacto original describen su presentación,
anterior a esa aprobación. Se conservan los archivos ajenos a este ticket.

La pantalla usa la [consulta y operación de MA-TSK-134](consulta-asignacion-pendientes.md),
los componentes de lista/detalle de EP-010 y el selector/alta de EP-008.
No se cambia esquema ni lockfile. No se añaden acciones de borrado, lectores,
automatismos, presupuestos ni fotos.

## Composición y entrega a MA-TSK-136

- `LocalBackupSession.pendingMovements()` resuelve la conexión activa por visita
  y confirmación. `createPendingMovementSource` inyecta el servicio de pendientes,
  las cuentas (también históricas), etiquetas de lotes EP-004 y la invalidación.
- `AppRoutes.pendingMovements` identifica `/pendientes-categorizacion`.
  La ruta admite `?lote=<UUID>`, sin imponer el mes del origen. Rechaza UUID,
  parámetros o rutas de consulta inválidos antes de consultar o escribir.
- `PendingMovementOrigin(route: ..., label: ...)` permite conservar el destino
  de retorno. Abrir detalle utiliza `/movimientos/<UUID>` y el formulario ya
  existente; volver relee y conserva los filtros, el scroll y el foco de acción.
- `PendingMovementRoute.onBatch` y `PendingMovementScreen.onBatch` son callbacks
  opcionales para el enlace «Ver lote». Los enlaces reales de Gestión,
  resultado/historial, comprobación de existencia del lote y conservación del
  periodo del origen pertenecen a **MA-TSK-136**. Este ticket entrega la pantalla
  y su composición, sin modificar esos menús ni duplicar navegación de importación.

`MovementRecordList` extrae la tabla/tarjetas de EP-010 y se usa también desde
Movimientos, manteniendo sus columnas y proporciones. Bandeja presenta fecha
de valor, concepto/UUID, cuenta, lote/ordinal e importe firmado. Usa tarjetas
bajo 840 px o con texto ampliado y conserva los cinco destinos principales.

## Comportamiento

Por defecto consulta todos los periodos, 100 filas por página, orden fecha
descendente/UUID ascendente y contador SQL de todos los pendientes filtrados.
Lote, cuenta, fechas civiles y concepto se intersectan. «Hasta» es inclusivo:
se convierte al día civil siguiente en UTC, sin zonas horarias ni desbordamiento
para 9999-12-31. Fechas vacías dejan abiertos los extremos. Editar un filtro
limpia inmediatamente la selección y bloquea asignaciones hasta aplicarlo;
fechas inválidas mantienen los resultados anteriores identificados como sin aplicar.

Casillas y «Seleccionar página visible» capturan solo UUID visibles.
Cambiar página limpia selección. El selector existente distingue nombres por
ruta, permite los tres niveles activos y vuelve desde el alta conservando su
borrador. Elegir categoría no escribe movimientos: «Guardar categoría» en la
confirmación explícita revisa cantidad, ruta y UUID, también para un único real.
Cancelar/Esc/Atrás no escribe. Selector, confirmación y persistencia bloquean
un segundo envío y la navegación de la pantalla inferior.

Éxito se anuncia solo después de persistir; limpia selección y cursores,
relee desde la primera página y conserva filtros/scroll. La lectura posterior
puede fallar sin confundir ese fallo con la escritura ya confirmada: entonces
no se publica un contador antiguo. Un error de escritura conserva selección
y permite reintentar manualmente.

`MovementFailure.requiresRefresh`, opcional y falso por defecto, identifica
los conflictos de elegibilidad de la operación de pendientes, sin comparar
mensajes traducidos. La transacción existente sigue revalidando todos los UUID,
categoría y base; sus conflictos marcan este flag. Las operaciones generales
de Movimientos mantienen su semántica. Un conflicto conserva los UUID para
revisión y exige «Actualizar pendientes» y una selección nueva. Una conexión
o dataset distinto descarta selección/cursor al releer. No se sobrescriben
categorías ajenas ni se realizan reintentos automáticos.

Las etiquetas, signos, casillas con nombre/UUID y avisos vivos permiten revisar
alcance, carga, fallo y éxito. Los controles siguen las medidas de la app.
Los diálogos mantienen foco contenido y cancelación conservadora; el retorno
desde detalle/lote conserva el foco del disparador si continúa disponible.

## Verificación

`test/movements/pending_movement_screen_test.dart` añade 25 casos con SQLite
real y datos sintéticos: consulta/contador, UUID/página, filtros Unicode,
cancelación, persistencia, conflicto por categoría/borrado/destino archivado,
rollback por fallo de escritura, doble envío y conexión sustituida; prueba
también selector, alta cancelada/guardada, detalle y retorno. Comprueba tabla/
tarjetas a 320/360/412/839/840/1024/1440 px y texto al 200 %, fechas inclusivas,
0001/9999, filtros inválidos, vacío, semántica y cancelación con Esc.

La suite dirigida de 41 pruebas (bandeja, lista compartida, arquitectura
y recorrido Presupuesto) pasó con `--concurrency=1`. El recorrido Presupuesto
se incluyó porque la primera ejecución global terminó con 1.343 aprobadas y
un timeout de 45 segundos en `budget_lifecycle_test.dart`, caso Windows,
durante la reapertura de SQLite. No se modificó ese guion ajeno; su recorrido
Windows y Android pasó después en la suite dirigida. Las compilaciones no se
ejecutan en paralelo con pruebas que bloquean la DLL SQLite. Un intento de
captura mientras corría la suite global fue bloqueado por esa DLL en uso;
se repitió correctamente una vez terminada la suite.

Se inspeccionaron capturas de widgets con el tema y navegación reales:
[tabla PC](flutter-app-1440-1.png), [tarjetas Android](flutter-app-412-1.png)
y [texto al 200 %](flutter-app-412-2.png). Se corrigieron la alineación vertical
de navegación y la altura desigual de los filtros, conservando las opciones
completas y mostrando tooltip del valor seleccionado. Capturas reproducibles
en este entorno Windows:

```powershell
flutter test --no-pub --concurrency=1 --dart-define=CAPTURE_PENDING=true `
  test/movements/pending_movement_screen_test.dart `
  --plain-name 'Composición real con navegación'
```

Las capturas requieren Segoe UI de Windows y el archivo de iconos del SDK
local; la suite normal no depende de esas rutas ni genera imágenes.
Los dos builds usan Flutter 3.47.0 / Dart 3.13.0, sin actualizar SDK/lockfile.
Android usa JDK 17.0.20.1 y configuración aislada por proceso mediante APPDATA
en `.tools/ma-tsk-135-flutter-config`; la configuración global conserva su JDK.
El SDK local informa canal `[user-branch]`, como las entregas anteriores.

Verificación final del 2026-10-08:

- `scripts/check-quality.ps1` completo con `--concurrency=1` en sus llamadas a
  `flutter test`, mediante función local de PowerShell, sin editar el script:
  287 archivos con formato correcto, análisis sin incidencias, **1.347 pruebas
  aprobadas** y las cuatro variantes `development`/`test`/`production`/
  `invalid-synthetic` aprobadas. La ejecución serializada evita competencia
  entre los recorridos de archivos; el timeout inicial no se reprodujo.
- `node docs/ep-001/verificar-casos.mjs`: correcto; cifras y signos conservados.
- `git diff --check`: correcto; contratos de esquema, SDK y lockfile intactos.
- Los builds Windows release y Android debug terminaron correctamente sobre
  la versión final con `--no-pub --dart-define=APP_ENV=test`; sus salidas permanecen fuera
  del commit. Solo se confirman archivos de MA-TSK-135, excluyendo el trabajo
  concurrente de sincronización, README, mockups y fixtures.

No se acredita ejecución de la bandeja en Windows nativo ni dispositivo
Android: `adb devices` no mostró dispositivos conectados. Las pruebas de host
validan widgets, navegación y SQLite; builds validan compilación de los dos
destinos. Lector de pantalla, teclado/tacto físicos y Android Back real siguen
sin verificar. La integración de accesos de Gestión/lotes corresponde a T136.
