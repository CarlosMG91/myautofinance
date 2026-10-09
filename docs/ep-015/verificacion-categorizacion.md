# MA-TSK-138 · Verificación integral de categorización

Ticket contrastado el 2026-10-09 mediante `GET http://localhost:4310/api/data`,
tablero **My autofinance**: MA-TSK-136 y MA-TSK-137 figuran `done` y el alcance
de MA-TSK-138 coincide con el encargo. Se continúa el trabajo de pruebas del
ticket que había quedado sin confirmar en el checkout.

## Escenarios y preservación

El fixture resuelve las identidades simbólicas de MA-TSK-137 a UUID reales.
Importa bytes JSON sintéticos mediante `SyntheticImportAdapter` y los servicios
comunes de preview, confirmación e historial de EP-012. No invoca lectores
EP-013/014 ni selectores de archivos, Drive o bases personales.

| Criterio | Evidencia automatizada |
|---|---|
| Filtros, contador y paginación | `pending_reference_test.dart`: siete consultas y páginas de dos UUID, fechas y desempate por UUID; contador completo en cada página; no omite ni repite identidades. |
| Selección visible | Solo captura UUID de la página; intenta añadir manuales y UUID importados ocultos sin ampliar la selección; avanzar/retroceder limpia selección. |
| Gestión y lote contextual | `pending_lifecycle_test.dart` y guion compartido: acceso global desde Real con un periodo antiguo; historial abre solo el UUID de lote; retorno conserva ruta, estado de origen y contador actual. |
| Asignación y cancelación | Selector y confirmación reales con cantidad, categoría y UUID; cancelar conserva toda la imagen SQLite y revisión; guardar individual/lote retira pendientes, limpia selección y conserva filtros. Editar un filtro limpia selección inmediatamente. |
| Persistencia y procedencia | Cierra y abre otra sesión sobre el mismo archivo; comprueba pendientes restantes y lote vacío, abre procedencia e información original desde el historial y el detalle EP-010. |
| Concurrencia | Segunda conexión al mismo archivo categoriza/elimina un seleccionado o archiva el destino; la confirmación rechaza todo y conserva exactamente la imagen posterior al cambio ajeno, incluidos revisión y contexto. |
| Rollback | Trigger temporal aborta la actualización del segundo UUID después del primero; imagen y revisión permanecen iguales. El reintento explícito tras retirar el fallo tiene éxito. |
| Restauración | Sustituye la base por su copia consistente y reabre la conexión; la solicitud antigua no escribe y exige consulta y selección nuevas. |
| Duplicados legítimos | Dos filas con cuenta, fecha, concepto, importe y discrecionalidad idénticos reciben UUID y ordinales distintos; categorizar una deja la otra pendiente. |
| Repetición exacta | Repite los mismos bytes con otro nombre y confirma por EP-012: `ImportAlreadyImported`, mismo lote y ninguna diferencia en la imagen persistida; el resultado permite volver a la bandeja vacía. También repite el archivo de duplicados tras categorizar uno. |

La comparación recorre todas las tablas persistidas, incluidas importación,
campos originales repetidos, huella, cuentas, presupuestos y fotos. Para una
asignación solo permite cambiar `category_id` y `updated_at` en los UUID
autorizados. Comprueba aparte que la revisión de base aumenta una vez por
operación exitosa. Las cancelaciones, rechazos y repeticiones comparan también
el estado de base sin excluir campos. Los manuales y demás importados se
conservan íntegros.

El guion está disponible tanto en pruebas de host (1440 px/Windows y
412 px/Android) como en `integration_test/pending_categorization_test.dart`.
Para repetir la ejecución nativa en una instalación con las herramientas fijadas:

```powershell
flutter drive -d windows --profile --no-pub --dart-define=APP_ENV=test `
  --driver=test/support/pending_native_driver.dart `
  --target=integration_test/pending_categorization_test.dart
# Android: sustituir windows por el ID del dispositivo y profile por debug.
```

## Verificación y límites

La aceptación dirigida final aprueba **9 pruebas**. La suite dirigida de
regresiones aprueba los 82 casos existentes de EP-010/015; en esa ejecución
anterior los dos nuevos recorridos aún fallaban al confirmar la reimportación
sintética. Se corrigió el guion para esperar también `sending` y resolver las
referencias/revisar los solapamientos antes de confirmar explícitamente el
archivo. No se cambian servicios ni pantallas de producción ni sus timeouts.
Un intento de lanzar otra prueba durante esa suite no pudo reemplazar la DLL
SQLite en uso; las ejecuciones posteriores se realizan secuencialmente.

Los avisos debug de Drift aparecen al abrir deliberadamente conexiones
independientes al mismo archivo. Cada una tiene su propio executor y se cierra;
no se ocultan estos avisos.

Resultados finales del 2026-10-09:

- `flutter --version`, `check-toolchain.ps1` y `pub get --enforce-lockfile`:
  Flutter **3.47.0**, Dart **3.13.0**, sin cambios de SDK o lockfile.
- `scripts/check-quality.ps1`, con `--concurrency=1` añadido por una función
  local de PowerShell, sin editar el script: **293 archivos** sin cambios de
  formato y análisis sin incidencias. La suite global terminó con **1.361
  aprobadas y 1 fallida**, incluidos los nueve casos de MA-TSK-138 aprobados.
  No se presenta el script completo como aprobado.
- El único fallo global fue `wealth_photo_screen_test.dart`, «Ruta conserva
  febrero, Atrás protegido y guardado actualiza origen con pendientes»: no
  encontró «Foto completa» después de guardar/volver y su desmontaje registró
  una operación sobre la conexión ya cerrada. Al repetir **todo ese archivo**,
  sus **15 pruebas pasaron** sin cambios. No se establece una causa definitiva
  ni se afirma que otra ejecución global esté garantizada.
- Las cuatro variantes de arranque, no alcanzadas por el script tras fallar
  la suite, se ejecutaron por separado: `development`, `test`, `production` e
  `invalid-synthetic`, **una prueba aprobada en cada variante**.
- Windows nativo **profile**: el guion compartido terminó correctamente en
  55 segundos, con resultado `All tests passed` recibido por Flutter Driver y
  código cero. El runner emitió «integration_test plugin was not detected»;
  se conserva el aviso y se distingue del resultado recibido por el driver.
- `flutter build windows --release --no-pub --dart-define=APP_ENV=test`:
  correcto (12,3 s), desde `lib/main.dart`.
- `flutter build apk --debug --no-pub --dart-define=APP_ENV=test`:
  correcto (43,3 s), desde `lib/main.dart`, con JDK **17.0.20.1** y APPDATA
  aislado por proceso en `.tools/ma-tsk-138-flutter-config`. No cambia la
  configuración global. El SDK fijado define compile/target API **36** y
  NDK **28.2.13676358**; doctor detecta Build-Tools **36.0.0**.
- `node docs/ep-001/verificar-casos.mjs` y `git diff --cached --check`:
  correctos, cifras y signos financieros conservados.

Doctor informa canal local `[user-branch]`, algunas licencias Android pendientes
y Visual Studio Community **2026 Insiders 18.11.12224.323**, que es el compilador
local empleado. Los builds correctos no acreditan un doctor sin advertencias
ni la compilación con Visual Studio 2022 de CI. No se acepta ninguna licencia
ni se cambia el SDK para eliminar esos avisos.

No se realizó ejecución nativa en teléfono o emulador Android: `flutter devices`
solo detectó Windows y navegadores. Las tarjetas Android se verifican en host;
el APK acredita compilación. Tampoco se acreditan una revisión manual con
teclado/tacto físicos, lector de pantalla, archivos bancarios reales o CI remota.

Logs locales sin versionar: `.tools/ma-tsk-138-resume-acceptance.log`,
`.tools/ma-tsk-138-resume-regression.log`, `.tools/ma-tsk-138-resume-quality.log`,
`.tools/ma-tsk-138-resume-wealth-repeat.log`,
`.tools/ma-tsk-138-resume-env-<entorno>.log`,
`.tools/ma-tsk-138-resume-native-windows.log`,
`.tools/ma-tsk-138-resume-build-windows.log`,
`.tools/ma-tsk-138-resume-build-android.log` y `.tools/ma-tsk-138-resume-doctor.log`.

## Entrega y aislamiento

La rama configurada es `ticket/ma-tsk-113`, remoto `origin`. La entrega del
ticket incluye únicamente sus pruebas, fixture, guion compartido, runner
nativo y este informe. Quedan fuera README, sincronización/Drive, los mockups,
fixtures EP-013 y el documento de MA-TSK-137 que ya estaban sin confirmar.
Calidad y builds se ejecutan sobre el checkout compartido; no acreditan CI
remota ni la entrega de esos otros cambios. SDK, lockfile, caches, logs,
artefactos y datos de prueba no se versionan.
