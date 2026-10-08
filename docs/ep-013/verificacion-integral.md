# MA-TSK-122 · Recorrido CSV y repetición segura

Ticket y dependencias consultados el 2026-10-08 mediante lectura de
`http://localhost:4310/api/data`, tablero **My autofinance**, con workspace
coincidente. MA-TSK-120/121 constan completados. Se mantiene el contrato
original de EP-001, el esquema y los servicios de EP-012; no se modifica el
estado del tablero ni código de otras épicas.

## Entrega

El [recorrido compartido](../../test/support/csv_import_journey.dart) usa
archivos físicos sintéticos y el adaptador `NativeLocalCsvSelector`. Un canal
exclusivo de prueba sustituye al diálogo/proveedor nativo y lee los archivos
sin cambiar sus bytes. El controlador, SHA-256 en isolate, lector, adaptador
histórico, previsualización, confirmación, repositorios e historial son los
productivos. Cada caso recibe una carpeta temporal y una base SQLite propia.
La base personal y los archivos del usuario no se abren.

La [batería VM](../../test/importing/csv_import_journey_test.dart) contrasta el
bundle con los 25 archivos exactos del checkout: plantilla EP-001 y 24
fixtures de MA-TSK-121. El [runner nativo](../../integration_test/csv_import_journey_test.dart)
ejecuta los mismos nueve escenarios en Windows/Android. El
[generador del bundle](../../scripts/generate-csv-test-bundle.mjs) permite
llevar esos bytes al dispositivo sin añadir assets ni paquetes a la app.

Se corrigen defectos del generador de fixtures de EP-013 detectados al pasarlos
por el lector real: los campos con separadores/comillas/saltos deben estar
entrecomillados y las comillas duplicadas; la muestra renombrada debe repetir
exactamente el válido LF. `--check` ahora compara sin reescribir archivos ni
manifiesto, de modo que detecta alteraciones. No cambian cifras de EP-001.

## Cobertura

| Caso | Comprobaciones |
|---|---|
| Plantilla anual | 48 presupuestos y 10 reales; aprobación expresa de cuenta y árbol de tres niveles, marca de ingreso únicamente en Ingresos. Ninguna escritura en la revisión. Presupuesto CSV −1320000 / interno +1320000 céntimos; REAL CSV e interno +232965. |
| Reapertura | Todas las tablas duraderas idénticas; únicamente el estado TEMP `local_mutation` se excluye entre conexiones. Enero real +122975, febrero +109990, anual +232965; presupuesto mensual +110000 y anual +1320000. Sin fotos patrimoniales creadas. |
| Procedencia y metadatos | Ordinales 2–59, nueve originales por fila, UUID de destino enlazado, hash/nombre/origen/versiones/fecha/conteos. Cada importe guardado coincide con el interno interpretado. Dos Café conservan identidades distintas y Discrecional. |
| Huella y repetición | Mismos bytes renombrados: Ya importado, sin escrituras. BOM y saltos distintos: otra huella y revisión completa; los presupuestos existentes bloquean. Variantes REAL necesitan revisar todos los avisos y conservan todas las filas. |
| 24 fixtures | Casos válidos con conteos y totales firmados, cero presupuestario y tipo/espacios. Formato/UTF-8/calendario/jerarquía/cuenta/cero REAL inválidos y conflictos nodo/mes o ancestro/descendiente no guardan nada. Se comparan todas las tablas, revisión y estado TEMP. |
| Multilínea | Registros 2/3 persistidos aunque ocupen líneas físicas 2–4. Fecha errónea en registro 3 informa campo fecha y línea física 4; no admite filas parciales. Original con comillas, separador y salto conservado. |
| Selección | Cancelación, acceso denegado, lectura fallida y documento ausente conservan revisión/decisiones. Reemplazo rechazado conserva sesión; recarga aceptada descarta planes. Cambiar el archivo externo no cambia la instantánea ya leída. |
| Corrección y borrado | Reales y partidas modificados/borrados conservan originales y conteos del lote. Repetir bytes no recrea destinos ni deshace correcciones. Historial de reales se comprueba también tras reabrir. |
| Atomicidad | ABORT al insertar metadatos, tras referencias y 58 registros: rollback de todas las tablas y revisión. Retirar fallo permite reintento; doble confirmación crea un solo lote. |
| Concurrencia | Conexión independiente importa REAL después de previsualizar: nuevo aviso bloquea hasta revisión explícita. Presupuesto concurrente y referencia archivada invalidan confirmación, sin crear la cuenta/categoría preparada. |
| Ambigüedad | Dos rutas coincidentes exigen UUID expreso. Vincular a la rama de salida mantiene la marca heredada, sin inferir ingreso del signo ni elegir la otra rama. |

Las pruebas previas del núcleo y de CSV complementan el recorrido con resultados
tardíos, salidas/consentimiento, huella recalculada, límites int64, ventanas y
tarjetas Android, accesibilidad automatizada, migraciones y cursores. No se
reimplementan reglas del núcleo para hacer pasar la batería.

## Reproducción

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
node docs/ep-013/fixtures/generar-fixtures.mjs --check
node scripts/generate-csv-test-bundle.mjs --check
node docs/ep-001/verificar-casos.mjs
flutter test --no-pub test/importing/csv_import_journey_test.dart
./scripts/check-quality.ps1

flutter drive --profile --driver=test/support/import_native_driver.dart --target=integration_test/csv_import_journey_test.dart -d windows --no-pub --dart-define=APP_ENV=test

# Adaptar rutas/ID a la instalación local, con JDK 17.
$env:JAVA_HOME = (Resolve-Path '.tools/jdk17-094/jdk-17.0.20.1+1').Path
$env:GRADLE_OPTS = "-Dorg.gradle.java.home=$env:JAVA_HOME"
flutter drive --driver=test/support/import_native_driver.dart --target=integration_test/csv_import_journey_test.dart -d emulator-5554 --no-pub --dart-define=APP_ENV=test

flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

## Evidencia y límites

La entrega se prepara en un worktree aislado basado en `ca3e911` (MA-TSK-120),
incorporando el commit entregado `ca539aa` de MA-TSK-121. El checkout compartido
tiene cambios Drive y diseño concurrentes, que quedan fuera de esta entrega.
El árbol confirmado de partida contiene consumidores Drive cuyo proveedor
MA-TSK-064 sigue sin confirmar: faltan `drive_upload_factory.dart`,
`drive_upload.dart` y extensiones de estado/transferencia. El análisis global
de esa base falla; no es una regresión CSV y no se modifica otra épica para
ocultarlo. La verificación sobre el checkout integrado se identifica aparte.
Git conserva los bytes físicos de los fixtures CSV de EP-013 (`-text`) y
entrega la plantilla EP-001 con LF, igual que su contenido confirmado. Esto
evita que `core.autocrlf` cambie las huellas o desactualice el bundle en CI;
no cambia registros, importes ni reglas financieras del contrato.

Comprobado con Flutter 3.47.0 / Dart 3.13.0, verificador del toolchain y
resolución del lockfile sin actualizar SDK ni dependencias:

- Generador de 24 fixtures, bundle de 25 archivos y casos financieros EP-001:
  correctos. Formato lib/test/integration_test: correcto. Análisis del módulo
  importing y de todos los archivos Dart nuevos: sin incidencias.
- Batería final del arnés: **10 tests correctos** (contraste binario y nueve
  escenarios). Windows nativo profile por Flutter Driver: los nueve escenarios
  correctos y resultado final del driver correcto. El runner añade tearDownAll
  al conteo y avisa de detección de integration_test en escritorio; el driver
  obtiene el resultado y termina con código cero. No se acredita Windows debug.
- `check-quality.ps1` de la rama aislada: versiones/dependencias/formato
  correctos; análisis bloqueado por **84 incidencias de dependencias Drive**
  de la base confirmada. El script no llega a la batería ni al arranque.
- `check-quality.ps1` del checkout compartido con sus dependencias concurrentes:
  formato y análisis correctos; **1277 pruebas correctas y 11 fallos**.
  Incluye timeouts en historial de importaciones y recorridos de Presupuesto,
  Movimientos, recuperación y catálogo local. Durante la ejecución quedaban
  unos 550 MB de RAM libres; se detuvo el emulador iniciado por este ticket
  para continuar secuencialmente. Esto no convierte los fallos en aprobaciones
  ni acredita calidad global. No se modifican pruebas de otras épicas.
- Builds requeridos del checkout integrado, Windows release y APK debug con
  APP_ENV=test: **correctos**. Su resultado depende del código Drive concurrente
  disponible en ese checkout y no acredita un build limpio de la rama aislada.
  Android utiliza API 36, Build-Tools 36.0.0, NDK 28.2.13676358 y JDK 17;
  el contexto del daemon Gradle confirma javaVersion=17. JBR 25 sigue configurado
  globalmente; JAVA_HOME/GRADLE_OPTS se fijan sólo para cada ejecución.

- Regresión secuencial de importing y arquitectura en el checkout integrado:
  **252 pruebas correctas**, incluidos los dos casos de historial que tuvieron
  timeout en la batería general. Arranque development/test/production/valor
  inválido sintético: las cuatro variantes correctas, ejecutadas expresamente
  porque el script general se detiene antes.

El primer intento Android compiló el arnés, pero se detuvo antes de ejecutar
para liberar memoria. El siguiente descubrió que el arnés no había resuelto
el alias del directorio de soporte Android: la protección de recuperación
rechazó la ruta antes de abrir SQLite. Se corrige únicamente el runner,
resolviendo la ruta canónica como las otras pruebas nativas del proyecto,
y se garantiza limpieza de la carpeta temporal incluso si falla la apertura.
Estos intentos no se consideran recorridos aprobados. El reintento final con
ruta canónica ejecuta **los nueve escenarios correctamente en Android debug**,
con resultado correcto del driver y código cero. Se usa el emulador disponible
Medium Phone **API 37, x86_64**, sin ventana; no se acredita dispositivo API 36
ni teléfono físico. El APK se compila con las versiones fijadas por el proyecto.

Logs locales `.tools/ma-tsk-122-*`, excluidos de Git. Doctor advierte canal
local `[user-branch]`, Visual Studio Insiders y licencias Android pendientes;
no se alteran configuraciones globales. El worktree nuevo usa junctions a las
cachés de plugins existentes al no disponer de permiso para crear symlinks.

El diálogo del sistema no se automatiza: no se acredita apertura interactiva
de IFileOpenDialog/ACTION_OPEN_DOCUMENT ni fallos reales de proveedores. El
canal sustituido prueba el transporte Dart y los errores clasificados. Las
reaperturas cierran la conexión y abren otra en el mismo proceso, sin simular
corte eléctrico ni terminación forzosa. No se acredita teléfono físico,
Narrador/TalkBack ni carga de datos personales.
