# MA-TSK-095 · Verificación del recorrido

Fecha: 2026-10-05. Solo datos sintéticos y SQLite real en archivo temporal.
No se utiliza la base de la instalación. El mismo guion
`test/support/movement_lifecycle_journey.dart` se ejecuta desde
`test/movements/movement_lifecycle_test.dart` y
`integration_test/movement_management_test.dart`.

## Cobertura comprobable

| Operación | Comprobación del guion compartido |
|---|---|
| Alta | Dos registros manuales con todos los campos visibles idénticos y UUID distintos; dos filas importadas idénticas con ordinales 2 y 3 |
| Edición | Fecha, importe firmado, cuenta y discrecionalidad; revisión única; conserva concepto, UUID y origen |
| Búsqueda | `CAFÉ`/`Café`, `arbol`/`Árbol`; buscar discrecionalidad no devuelve filas |
| Filtros | Periodo marzo excluye abril; intersección cuenta/categoría, rama con nieta, directos y NULL |
| Subtotal | Marzo inicial +2050, altas +1450, corrección −250; Café +800, Árbol −450, rama +350, Sin clasificar −600 |
| Paginación | Tamaño 2, cursor exclusivo sin repeticiones, subtotal −250 en ambas páginas; selección de página no toca registros ocultos |
| Categorizar/quitar | Selector compartido y lote explícito; comparación de todas las columnas salvo categoría y timestamp |
| Borrado | Cancelación individual/lote compara imagen completa incluida revisión; confirmación individual y de dos seleccionados; subtotal −900 tras borrar los dos manuales |
| Fallos | Trigger SQLite rechaza la segunda escritura de categorizar/quitar/borrar, después de una primera fila modificable; imagen completa y revisión idénticas, selección retenida, sin éxito anunciado |
| Selección obsoleta | Borrar un UUID tras capturar la selección rechaza el lote completo; relectura descarta únicamente el UUID ausente |
| Referencias históricas | Editar conserva categoría archivada; nueva asignación archivada se rechaza; cuenta cerrada vigente en marzo y no en abril; rechazo en formulario y dominio |
| Procedencia | UUID/importRowId/batchId/ordinal conservados tras edición y lote; borrar retiene dos import_rows y un lote |
| Repetición | EP-004 rechaza la misma huella tras editar, borrar y reabrir, aun con otro nombre; imagen y revisión intactas, sin resurrección |
| Independencia | Presupuesto y foto manual con dos valores se comparan completos al final y tras reapertura |
| Navegación | Gestión abre marzo, informe transmite periodo/cuenta/categoría/directos/concepto; detalle vuelve a lista, lista vuelve a ruta de Real con contexto |
| Reapertura | Cierre de conexión/sesión y sesión nueva sobre el mismo archivo; comparación completa de tablas y revisión, relectura de interfaz con subtotal −450 |

La paginación de tamaño 2 usa una ruta de prueba con la pantalla, controlador y
fuente SQLite de producción; se pulsan Página siguiente/anterior y Seleccionar
página visible. Las búsquedas, filtros, altas, edición,
selector y confirmaciones se accionan en widgets de producto. Los triggers y
la desaparición externa de un UUID son exclusivamente inyecciones de prueba.
La fixture de importación llama a `SqliteImportBatchRepository`, sin construir
un importador ni analizar un extracto. El host alterna TargetPlatform y anchos
1440/412: demuestra ambas disposiciones, no equivale a ejecución Android nativa.

## Reproducción

Añadir `.tools/flutter/bin` al PATH en esta máquina, sin actualizar el SDK:

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub test/movements/movement_lifecycle_test.dart -r expanded
./scripts/check-quality.ps1
flutter build windows --release --no-pub --dart-define=APP_ENV=test
# JDK 17 local de esta máquina, solo para el proceso actual:
$env:JAVA_HOME = (Resolve-Path '.tools/jdk17-094/jdk-17.0.20.1+1').Path
$env:GRADLE_OPTS = "-Dorg.gradle.java.home=$env:JAVA_HOME"
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
flutter drive --profile --no-pub -d windows --target=integration_test/movement_management_test.dart --driver=test/support/category_native_driver.dart --dart-define=APP_ENV=test --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false
# Con Android conectado:
flutter test integration_test/movement_management_test.dart -d <android-id> --no-pub --dart-define=APP_ENV=test
node docs/ep-001/verificar-casos.mjs
node docs/ep-010/verificar-mockup.mjs
```

El driver genérico existente se reutiliza para Windows. La entrada de texto
de prueba se registra también en el runner nativo; no verifica el IME físico.
El guion usa path_provider para la carpeta sintética nativa y resuelve su ruta
física antes de abrir la sesión, conservando la política de protección local.

## Resultados y límites

Flutter 3.47.0 / Dart 3.13.0 y check-toolchain correctos. El SDK local declara
canal `[user-branch]`; no se cambia a stable ni se actualiza. Resolución con
`--enforce-lockfile` correcta, sin modificar pubspec.lock ni toolchain.json.
El sandbox bloqueó inicialmente acceso de red a pub.dev y resolución de rutas
temporales; las ejecuciones autorizadas fuera de ese aislamiento funcionan.

- Recorrido host: **2 pruebas correctas**, Windows 1440 y Android 412.
- `check-quality.ps1`: **correcto**, formato sin cambios, análisis sin incidencias,
  **1002 pruebas correctas** y cuatro variantes de arranque correctas
  (`development`, `test`, `production`, `invalid-synthetic`). Registro de la
  ejecución de entrega: `.tools/095-quality-reviewed.log`, salida 0.
- Windows release APP_ENV=test: **correcto**, ejecutable generado.
- Android debug APP_ENV=test: **correcto**, APK generado. Gradle usa JDK 17
  mediante JAVA_HOME/GRADLE_OPTS locales; el lanzador que selecciona Flutter
  procede del Java 25 incluido en Android Studio. No cambia configuración global.
  La recompilación de entrega termina con salida 0
  (`095-build-android-reviewed.log`). `gradlew --version` confirma launcher y
  daemon JDK 17 cuando se invoca directamente (`095-gradle-reviewed.log`).
- EP-001: OK, conserva 48 presupuestos, 10 reales, enero +1229,75 EUR,
  real anual +2329,65 EUR y presupuesto anual +13200,00 EUR.
- Modelo del mockup MA-TSK-091: OK; esa comprobación no demuestra layout nativo.

Windows nativo profile: recorrido completo final correcto, incluidos los
botones de paginación, driver con salida 0 (`095-native-windows-reviewed.log`,
duración del recorrido 3 min 42 s). Windows release se recompiló después con
salida 0 (`095-build-windows-reviewed.log`).
Android nativo debug: recorrido completo final correcto, incluidos esos
botones, con salida 0 (`095-native-android-reviewed.log`, duración 5 min 50 s)
en el AVD temporal `Medium_Phone_API_37.0`, x86_64 API 37, `emulator-5580`.
No es un teléfono físico.
Se arrancó sin ventana, sin audio, sin guardar snapshot y con `-read-only`,
para no persistir la instalación de prueba en el AVD personal. Se cierra al
terminar. No había dispositivo Android conectado inicialmente.
Tras cerrar el AVD, se regeneró el APK de la aplicación con salida 0
(`095-build-android-app-final.log`), porque el runner de integración utiliza
la misma ruta `app-debug.apk`. La salida final corresponde al entrypoint
normal, también con APP_ENV=test.

La primera pasada de check-quality pasó formato y análisis, pero terminó con
992 pruebas correctas y 10 fallidas durante builds e integración simultáneos.
Dos fallos del nuevo guion leían `page` antes de acabar el refresco asíncrono;
se corrigen bombeando frames antes de comprobar reposo y esperando la relectura
tras altas/borrado. Los demás corresponden a recorridos previos de Drive,
recuperación local y patrimonio: timeouts de 30 segundos y errores posteriores.
No se modifican esos módulos ni pruebas. Una segunda pasada dejó 1001 pruebas
correctas y un fallo de búsqueda del nuevo recorrido Android. El guion final
espera la relectura antes de introducir texto, comprueba que los controles
estén habilitados y comprueba el texto introducido; ejecuta la pulsación fuera
del reloj simulado, como el recorrido existente de categorías. La ejecución
final de calidad indicada arriba pasó sin builds ni emulador simultáneos.
La calidad se ejecuta sobre el checkout compartido, que contiene cambios
concurrentes de EP-007/008 excluidos de la publicación de EP-010. El número
total de pruebas describe ese checkout; no acredita una ejecución CI ni una
verificación independiente de un checkout limpio del commit publicado.

Doctor detecta Visual Studio Community 2026 Insiders (18.11.12224.323) y
Windows SDK 10.0.26100.0; no es la instalación VS2022 recomendada por EP-003.
Android tiene SDK/Build-Tools 36.0.0 y un AVD API 37.0. La compilación conserva
los valores de proyecto/lockfile fijados; no se actualizan paquetes para probar.
No se verifican lector de pantalla, teclado/IME físico, teléfono real, Drive,
CSV/XLS ni UI de informes futuros.

Logs locales sin versionar: `.tools/095-journey-reviewed.log`,
`.tools/095-quality-reviewed.log`, `.tools/095-build-windows-reviewed.log`,
`.tools/095-build-android-reviewed.log`, `.tools/095-build-android-app-final.log`,
`.tools/095-gradle-reviewed.log`,
`.tools/095-native-windows-reviewed.log`, `.tools/095-native-android-reviewed.log`,
`.tools/095-emulator-reviewed.log`, `.tools/095-emulator-reviewed-error.log` y
`.tools/095-doctor-native.log`. Las pasadas anteriores fallidas se conservan
en `.tools/095-quality.log`, `.tools/095-quality-final.log` y
`.tools/095-quality-delivery.log`. No contienen evidencia de éxito remoto CI;
la publicación del código no equivale a una ejecución CI correcta.

## Revisión de entrega posterior · 2026-10-05

El checkout ya contenía la implementación completa en `749380b`. Se auditó el
guion compartido frente a MA-TSK-095 y se contrastaron los logs nativos anteriores:
Windows profile y Android debug terminaron correctamente. Esas ejecuciones nativas
no se repitieron en esta revisión; sigue pendiente la prueba en teléfono físico.

Se ejecutaron de nuevo, secuencialmente, con salida 0:

- `check-quality.ps1`: 206 archivos sin cambios de formato, análisis sin
  incidencias, **1002 pruebas correctas** y las cuatro variantes de arranque.
  Log local: `.tools/095-quality-recheck.log`.
- Windows release APP_ENV=test: ejecutable generado en 14,5 segundos.
  Log local: `.tools/095-build-windows-recheck.log`.
- Android debug APP_ENV=test: APK de la aplicación generado en 13,9 segundos,
  con el mismo JDK 17 local mediante JAVA_HOME/GRADLE_OPTS.
  Log local: `.tools/095-build-android-recheck.log`.
- Comprobadores EP-001 y mockup EP-010 correctos; `git diff --check` correcto.

Toolchain y lockfile permanecen intactos. La calidad y builds corresponden al
checkout compartido con los cambios concurrentes descritos arriba. No se acredita
CI remota. La primera resolución de paquetes dentro del sandbox falló por acceso
a pub.dev; `check-quality.ps1` resolvió con `--enforce-lockfile` en la ejecución
autorizada fuera del sandbox.

La consulta directa del remoto confirmó `749380b` en
`refs/heads/ticket/ma-tsk-071`: los cambios funcionales y artefactos pendientes de
EP-010 ya estaban publicados. Esta revisión solo añade esta evidencia de entrega;
los cambios concurrentes de README, EP-007 y EP-008 quedan fuera de su commit.
