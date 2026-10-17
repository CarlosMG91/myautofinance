# MA-TSK-224 · Exportación desde Gestión

## Alcance y aprobación

Se consultaron My autofinance, MA-EPIC-218 y MA-TSK-224 mediante la API local
de Epic Board (`GET /api/data`). MA-TSK-223 figura completado, con
`approvedAt=2026-10-17T06:33:09.417Z` y la decisión humana «Propuesta visual
aceptada: /mockups/autofinance-exportacion-v1.html». El suplemento aprobado
es el [prototipo v1](prototipo/README.md), HTML SHA-256
`f97a9e92897898ecf32c5fd15f6c2c757c54aa7e4133f95e274f73f2c580db12`.
El README del prototipo conserva el estado inicial de entrega de la propuesta.
El [suplemento de rutas](catalogo-navegacion.json) registra las dos entradas
bajo Gestión. La prueba de cobertura de rutas incorpora este suplemento sin
reescribir el catálogo visual aprobado de EP-026.

Gestión ofrece dos entradas: **Exportar datos** y **Exportar copia completa**.
La primera permite todo el histórico o meses `AAAA-MM` inclusivos. La segunda
siempre exporta toda la base financiera y deshabilita el periodo. El resumen
explica contexto completo, signos, fotos manuales y contenido del ZIP.

## Composición y ciclo de vida

`LocalBackupSession.exports` y `createExportController` conectan los
exportadores CSV/SQLite existentes con `NativeExportSaver` por constructor.
`AutofinanceApp.exports` permite inyectarlos en las pruebas. No se añaden
dependencias pub, motor de snapshot, consultas financieras en widgets ni
operaciones sobre Drive, restauración o catálogo privado de copias.

El controlador captura la selección al iniciar y bloquea cambios y operaciones
duplicadas hasta terminar. Cada intento genera un ZIP nuevo; no se conserva
un ZIP para otro rango, modo o reintento. Los exportadores siguen validando
la imagen, su contenido y el archivo. `PreparedDataExport.createdAtUtc`
expone la misma fecha y precisión del manifiesto, junto con su revisión real.
La pantalla no consulta la revisión actual para describir un ZIP anterior.

Fases que permite conocer el contrato: preparación (captura, generación y
verificación) y selector/guardado del sistema. No se presentan porcentajes ni
una fase de escritura inferida: el puerto nativo resuelve únicamente al acabar
el selector o la escritura. El progreso permanece indeterminado.

Cancelar preparación activa el token del exportador. Back/Escape y la
navegación solicitan confirmación para descartar un borrador. Si el selector o
la escritura ya están en curso, solicitar salir mantiene la pantalla hasta
recibir el resultado real; puede acabar guardado. El resultado se muestra antes
de volver al origen. La guía conserva la selección y vuelve al recorrido.

El temporal permanece vivo durante todo el guardado y se libera en `finally`
en éxito, cancelación, error y desmontaje de la pantalla. Un error de limpieza
se informa por separado sin ocultar un guardado confirmado. No se borra ningún
destino desde la pantalla o controlador.

Solo `ExportSaved` muestra éxito. Se muestra el nombre final cuando el sistema
lo facilita: nombre de la ruta Windows o `DISPLAY_NAME` opcional del proveedor
Android. En otro caso se identifica el nombre como propuesto, sin prometer que
sea el definitivo. Una URI Android se presenta como ubicación del sistema;
si falta ubicación se indica expresamente, sin inventar una carpeta. Los
conflictos y documentos posiblemente incompletos conservan la selección y
requieren una acción explícita de reintento con nuevo destino/nombre.

La guía integrada explica lectura CSV segura y consulta SQLite independiente
en una carpeta Windows nueva, también desde copias Android. Los comandos y la
herramienta de validación/extracción de T07, y la aceptación integral de T08,
conservan sus propietarios. Esta entrega no cierra la épica.

## Verificación reproducible

```powershell
./scripts/check-quality.ps1
flutter test --no-pub test/synchronization/export_controller_test.dart test/synchronization/export_screen_test.dart test/synchronization/native_export_saver_test.dart test/synchronization/data_export_test.dart test/synchronization/portable_backup_export_test.dart test/navigation_test.dart test/architecture_test.dart
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

Recorrido nativo interactivo con instalación temporal, servicios reales y
datos sintéticos de EP-001:

```powershell
flutter drive --debug --no-pub -d windows --target=integration_test/export_flow_test.dart --driver=test_driver/export_flow.dart --dart-define=APP_ENV=test --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false
# Repetir sustituyendo windows por el identificador del emulador Android.
```

El operador cancela el primer selector, guarda el CSV de enero y guarda la copia
completa en destinos nuevos. El recorrido comprueba contenido anunciado,
revisión sin cambios, selección conservada, guía y retorno. La evidencia local
sintética queda ignorada bajo `.tools/224-evidence`; no se incluyen ZIP ni bases
en el repositorio. Las pruebas de widgets cubren 320 px, texto 200 %, objetivos
táctiles y estados sin ubicación, con cancelación, errores, reintento y Back
durante escritura. No equivalen a una evaluación humana con lector de pantalla.

## Resultado de ejecución

- Flutter 3.47.0 / Dart 3.13.0 y `check-toolchain.ps1`: correctos. Resolución
  con `pub get --enforce-lockfile` correcta fuera del sandbox, sin cambios de
  lockfile. Dentro del sandbox falló la consulta de advisories de pub.dev.
- Análisis completo estricto: sin incidencias. Formato de lib/test/integration
  y `git diff --check`: correctos.
- **59 pruebas pertinentes correctas**: controlador, UI, puerto nativo,
  exportadores CSV/SQLite, navegación y arquitectura. La ejecución SQLite
  dentro del sandbox fallaba en la comprobación de rutas de recuperación;
  la repetición fuera de él pasó sin modificar el código de persistencia.
  El suplemento de rutas pasó además **ocho pruebas** del contrato de navegación.
- Builds de producto Windows release y Android debug, `APP_ENV=test`: correctos.
  Android usa JDK 17. La primera carpeta Windows conservó el prefijo de
  instalación por defecto tras un intento restringido fallido; una carpeta
  nueva y exclusiva produjo el build correcto.
- Android emulado: recorrido integrado correcto con selectores reales,
  cancelación y selección conservada, CSV de enero, copia total, revisión 19
  sin cambios, guía y retorno. El nombre final procede de Downloads.
- Lectura independiente del ZIP Android extraído por ADB sin root: Python
  `zipfile`, `csv`, `hashlib` y `sqlite3`, fuera de Autofinance. CRC, inventario,
  tamaños y SHA-256 correctos. CSV de enero: seis movimientos, incluyendo
  `-350.25` EUR. SQLite en carpeta nueva y modo solo lectura: integridad y
  claves correctas, diez movimientos (cuatro en febrero) y 48 presupuestos.
  Demuestra que la copia completa no hereda el rango CSV.
- El primer recorrido Windows guardó el CSV, pero el sondeo de accesibilidad
  activó errores `accessibility_bridge` del árbol nativo Flutter y desapareció
  el servicio del runner antes de completar el recorrido. No se acredita como
  prueba pasada. La repetición usa observación visual sin activar ese sondeo.

- Repetición Windows sin sondeo de accesibilidad nativa: **recorrido completo
  correcto**. Inspección visual del formulario, cancelación, resultado CSV y
  copia completa en el runner Flutter real; no son capturas del HTML.
- Lectura independiente Windows: mismo contenido financiero esperado que en
  Android (seis movimientos en el CSV de enero; diez movimientos y 48
  presupuestos en SQLite), con integridad, claves, tamaños y hashes correctos.
  Los ZIP proceden de distintas capturas y tienen identidades/fechas propias.
- La [evidencia resumida](evidencia-integracion-app.json) conserva solo metadatos
  de pruebas sintéticas. No incluye rutas personales ni documentos exportados.

- `check-quality.ps1`: versiones, lockfile, formato y análisis correctos;
  batería general con **2.007 correctas y cinco fallidas**. Una era la cobertura
  de las nuevas rutas: corregida con el suplemento y sus ocho pruebas correctas.
  Dos eran timeouts/archivos bloqueados de `local_recovery_journey_test.dart`
  bajo carga; la repetición en serie pasó sus **ocho casos completos** sin
  modificar persistencia ni pruebas de recuperación. Quedan las dos variantes
  Windows/Android de `pending_lifecycle_test.dart`, ya documentadas en la
  [entrega de T04](guardado-nativo.md). No se cambia código de EP-015.
  **No se presenta la batería general como verde**, ni se ha repetido entera
  después del suplemento de rutas.
- Algunas repeticiones no llegaron a ejecutar tests porque Flutter no podía
  actualizar un `sqlite3.dll` de build anterior. Se usaron carpetas de build
  nuevas por ejecución, conservando SDK, paquetes y lockfile.
- Arranques separados con development, test, production e invalid-synthetic:
  **los cuatro correctos**. Windows release y APK debug se regeneraron con el
  código final después de las pruebas nativas.

No se acredita un dispositivo Android físico, proveedor remoto, lector de
pantalla humano ni cierre T07/T08. El fallo observado en el sondeo de
accesibilidad nativa Windows queda registrado como limitación de verificación;
las pruebas de widgets no sustituyen esa evaluación.
