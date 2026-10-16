# MA-TSK-220 · Exportación CSV desde una revisión consistente

Se implementa T02 contra el contrato v1 de MA-TSK-219. El ticket íntegro y la
épica se han consultado en el mensaje del usuario; no hay conector Epic Board
disponible y no se acredita una actualización del tablero.

## Integración

`createDataExporter(store: store)` en `lib/app/data_export_factory.dart`
compone el puerto público `DataExporter`, el servicio `CsvDataExporter` y
`SqliteDataExportSource`. Los puertos y resultados pertenecen al dominio de
`synchronization` y se exportan desde su entrada pública. No se añaden módulos,
dependencias entre funcionalidades, motores financieros ni dependencias pub.

El consumidor llama `prepare(filter: ..., cancellation: ...)` únicamente ante
la acción de exportar. `DataExportFilter.all()` selecciona todo el histórico;
`DataExportFilter.months(from: '2026-01-01', through: '2026-03-01')` valida meses
completos e inclusivos. No hereda paginación ni filtros de las pantallas.

El resultado `PreparedDataExport` expone `zipPath`, `state` y `exportId` después
de verificar el ZIP. Es un temporal privado, no un archivo guardado por la
persona usuaria. T04/T06 deben guardarlo mediante su flujo nativo y ejecutar
`dispose()` en `finally` tras guardar, cancelar o fallar. No mostrar «guardado»
por el mero retorno de `prepare`. `dispose` permite una segunda llamada.
La cancelación produce `DataExportFailure(cancelled)` sin devolver resultado.
Los errores públicos contienen únicamente un código, sin conceptos, valores,
SQL ni rutas de datos.

## Captura y fidelidad

Cada operación solicita exactamente una imagen nueva a
`LocalBackupSource.createConsistentBackup`, implementada por `LocalDatabaseStore`.
No añade otro VACUUM, lee la activa después de capturar ni registra una copia
en el catálogo privado. Solo adopta la ruta de snapshot EP-004, sin enlaces ni
WAL/SHM/journal. Abre en solo lectura, reutiliza `validateExistingDatabase`,
contrasta identidad/revisión con `database_state` y contrasta esquema y
`application_id` con la política del código; no fija una versión histórica.

Todas las filas y metadatos proceden de esa misma imagen. El manifiesto conserva
su identidad incluso si otra generación pasa a ser la activa antes de leerla.
La fecha UTC se registra al terminar la captura validada. Tras crear/verificar
el ZIP se cierra y elimina la imagen temporal; no se elimina recursivamente su
padre ni se modifica una copia privada.

Las consultas leen tablas fuente con cursor, orden binario estable y LEFT JOIN
de procedencia. Cada UUID aparece una vez; dos registros de contenido idéntico
siguen siendo dos filas. Se filtran movimientos por fecha de valor y
presupuestos/cabeceras por mes, incluyendo todos los valores de las cabeceras
seleccionadas. El límite superior usa el mes textual, sin calcular el año 10000.
Los tres CSV de contexto conservan todos los registros y límites originales.

Las categorías resuelven raíz y rutas JSON hasta tres niveles. Los estados de
foto cuentan cuentas vigentes, valores y pendientes sobre datos persistidos;
no calculan saldos ni subtotales patrimoniales, no generan cabeceras ausentes
ni rellenan ceros. Los importes usan BigInt desde el INTEGER de céntimos,
incluido el mínimo int64. Presupuesto conserva signo interno. Null, vacío,
comillas, Unicode y saltos internos siguen el dialecto normativo.

`export_dictionary_v1.dart` incorpora el texto exacto del diccionario para que
funcione también empaquetado en Android, sin depender de `docs/` en ejecución.
Una prueba contrasta sus bytes exportados con el documento normativo. Si cambia
el contrato, debe regenerarse esa copia y revisarse la versión, no cambiar
columnas silenciosamente.

## Recursos, ZIP y limpieza

Se procesa una fila a la vez y se escribe con operaciones de archivo esperadas;
SQLite limita caché a 2 MiB y permite ordenación temporal en disco. El cursor
cede al bucle de eventos cada 128 filas y comprueba cancelación por fila; lectura,
empaquetado y verificación de archivos comprueban cancelación por bloque.
La primitiva previa de snapshot/validación no es interrumpible internamente;
si se cancela durante ella, al retornar se libera la captura sin publicar.

Límites del servicio inyectables: 1 GiB para el ZIP final y 10 millones de filas
en total por defecto. Se comprueban también los bytes al serializar. Superarlos
es un error explícito, no truncamiento ni aplicación de un límite de interfaz.
ZIP clásico método STORE, sin contraseña ni compresión y sin ZIP64: el límite
configurable no supera `0xffffffff`. Se evita incorporar una dependencia o un
cambio incidental de lockfile. En disco coexisten la imagen, los archivos de
staging y el ZIP; el consumidor debe prever ese espacio temporal.

El ZIP contiene exactamente siete CSV, diccionario, LEEME y manifiesto. Después
de cerrarlo y vaciarlo se reabre: se comprueban cabeceras locales, directorio
central, inventario, tamaño final sin bytes sobrantes, tamaños individuales,
CRC32, SHA-256 y conteos CSV lógicos sensibles a comillas. No se cuentan saltos
interiores como filas. El manifiesto no se lista ni se auto-hashea.
Un cambio entre descripción y empaquetado se rechaza.

Cada operación crea su propio directorio temporal y solo elimina sus archivos
inmediatos. No hace barridos de temporales, no borra archivos ajenos, no toca
catálogo de copias ni datos/sesión/Drive. Ante error o cancelación no devuelve
un ZIP listo ni sustituye destinos previos. No añade registro de datos personales.

## Verificación

- Flutter 3.47.0 / Dart 3.13.0 y `scripts/check-toolchain.ps1` correctos.
- Resolución offline estricta del lockfile correcta tras el fallo de red inicial.
  El control de calidad posterior resuelve también online con lockfile estricto;
  no se actualizan SDK, dependencias ni lockfile.
- `scripts/check-quality.ps1`: formato de 487 archivos sin cambios y análisis
  sin incidencias. Suite final en 12:41: **1.971 pruebas superadas y cuatro
  fallidas** en archivos ajenos:
  `test/budget/budget_lifecycle_test.dart` (Windows, timeout de 45 segundos),
  `test/drilldowns/report_drilldown_journey_test.dart` (Windows, `Bad state: No
  element` en `ensureVisible`) y los dos casos de
  `test/movements/pending_lifecycle_test.dart` (Windows/Android). No se cambian
  esos recorridos ni se declara verde el control general. Al fallar la suite,
  el script no llega a las cuatro variantes APP_ENV finales.
- Pruebas específicas: **11 pruebas del exportador correctas** también en una
  extracción del índice Git, sin cambios concurrentes, y **2 de arquitectura**
  correctas en el checkout compartido. Pruebas SQLite reales con fixture sintética
  de T01, siete CSV
  idénticos byte a byte, revisión/ordinal/importes int64 extremos, signos,
  ausencia/parcial/cero, contexto, filtros, base vacía, diciembre 9999,
  reemplazo de generación tras capturar, 4.102 movimientos con 4.097 duplicados
  legítimos, cancelación, límites, fallo, limpieza y ruta activa rechazada.
  Dos exportaciones simultáneas permiten cancelar una sin borrar el ZIP de la otra.
- ZIP generado por el servicio abierto mediante `System.IO.Compression.ZipFile`
  de .NET, independiente del escritor: diez entradas y los nueve tamaños/hashes
  del manifiesto correctos. Para reproducir la generación sintética se puede
  ejecutar la prueba con `AF_EXPORT_SYNTHETIC_ZIP` apuntando a una ruta temporal
  nueva; nunca apunta a una base o archivo de usuario.
  Un lector Node independiente contrasta además los diez CRC32, las referencias
  del directorio central y el registro final ZIP, junto con los nueve hashes.
- `node docs/ep-027/verificar-contrato.mjs`: correcto.
- El sandbox denegaba resolver el antecesor `C:\Users\carlo` en las protecciones
  existentes de copias; las pruebas se ejecutan con elevación de sandbox. No se
  debilita esa protección ni se modifica su implementación.
- Análisis del checkout compartido sin incidencias. El análisis completo de la
  extracción del índice encuentra **95 incidencias** de Drive en archivos ajenos
  al ticket: `drive_upload.dart`/`drive_upload_factory.dart` y miembros de estado
  ausentes en HEAD, presentes únicamente en los cambios concurrentes. No se
  incorporan para hacer pasar ese análisis ni se declara verde la aplicación
  completa del índice. La resolución en la extracción también advierte que los
  enlaces de plugins Windows requieren Developer Mode; las pruebas específicas
  posteriores con `--no-pub` sí compilan y pasan.
  El análisis específico de los siete archivos propios Dart en esa extracción
  final termina sin incidencias. No depende de incluir las piezas Drive ausentes.

La UI, el guardado nativo, la copia SQLite portable y su guía pertenecen a otros
tickets. No se modifican plataformas ni se acredita arranque de la aplicación
real Windows/Android: la verificación integrada y lectura independiente desde
la app quedan para T08 al cierre de épica, como exige T01. La comprobación .NET
anterior sí corresponde al ZIP real producido por este servicio sobre SQLite
sintética; no es una captura del prototipo ni una prueba de guardado nativo.

Se conservan los cambios concurrentes de sincronización y otros tickets fuera
del commit. Se usa la rama local configurada `ticket/ma-tsk-193`, sin cambiar
de rama ni forzar subida.
