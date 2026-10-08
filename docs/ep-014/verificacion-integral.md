# MA-TSK-131 · Verificación parcial y protección patrimonial

**Estado: bloqueado para Openbank; no completa MA-TSK-131 ni cierra EP-014.**
Comprobación del 2026-10-08.

## Evidencia de los requisitos

Se consultó `GET http://localhost:4310/api/data`, tablero **My autofinance**,
workspace coincidente, MA-EPIC-123 y MA-TSK-124/125/129/130/131. Los requisitos
figuran como `done`, pero MA-TSK-129 declara en su resultado que no creó fixtures
por falta de muestra; MA-TSK-130 declara que no implementó el recorrido por
falta de lector y adaptador. Los adjuntos están vacíos y la petición no aporta
una ruta privada accesible. Se ha solicitado al usuario la ubicación de la
muestra y, si existen externamente, las entregas faltantes.

La [caracterización](caracterizacion-openbank.md), el [lector](lector-openbank.md),
la [adaptación](adaptacion-nucleo.md) y la
[integración](integracion-recorrido.md) documentan esos bloqueos. No se ha leído
un extracto Openbank, observado su contenedor, hojas o columnas ni inventado
fixtures fieles a un formato desconocido. La extensión XLS y los ejemplos del
mockup no caracterizan el archivo. La aprobación visual ya consta en el tablero;
no resuelve la falta de muestra, lector y recorrido productivo.

## Prueba ejecutable del contrato común

Se retoman los tres archivos preparados por una ejecución anterior de este
mismo ticket, comprobada en su registro local de sesión, y se refuerza el caso:

- [Guion compartido](../../test/support/bank_import_wealth_journey.dart): usa
  `createImportServices`, repositorios reales y SQLite en archivo desechable.
- [Prueba de host](../../test/importing/bank_import_wealth_test.dart): ejecuta
  el guion sin interfaz ni selector bancario.
- [Prueba nativa](../../integration_test/bank_import_wealth_test.dart): ejecuta
  el mismo guion en Windows/Android con directorio temporal canónico de la
  aplicación. Resuelve enlaces internos de Android antes de abrir SQLite.
- [Driver](../../test/support/bank_import_wealth_driver.dart): permite ejecutar
  el guion Windows en profile y recoge su resultado a través del servicio VM.

La entrada es `ImportSession`/`ImportInterpretation` construida en test, origen
`bankXls`, bytes arbitrarios y versión `synthetic-contract-131`. **No hay lector
ni adaptación Openbank en esta prueba.** Un campo arbitrario llamado «saldo
sintético informativo» verifica que conservar un original no escribe patrimonio;
no prueba cómo el lector real identificará o excluirá saldos del extracto.
No se añade ningún servicio simulado al producto ni se cambia su interfaz.

Se pueblan dos cuentas (incluido saldo cero), una cartera y una deuda, con foto
completa de enero, incompleta de febrero y ausencia en marzo. Se conserva también
un presupuesto previo de −400,00 €. El guion compara todas las columnas y filas
de `wealth_snapshots`, `wealth_values` y `budgets` contra la imagen inicial,
incluidos identificadores, fechas y metadatos; no se limita a comparar totales.
Ante operaciones rechazadas compara **todas** las tablas persistentes y
`local_mutation`, detectando referencias, lotes, originales o revisión parciales.

| Caso | Evidencia que proporciona el guion común | Límite para Openbank |
|---|---|---|
| Cuenta y confirmación | Cuenta global pendiente bloquea; vinculación explícita al UUID permite confirmar. Tres REAL suman +275,00 €, categoría nula y cuenta de destino correcta. | No verifica detección de cuenta en el extracto ni su selección mediante interfaz Openbank. |
| Originales y ordinal | Dos cargos iguales de −12,50 € se conservan como registros distintos, ordinales 2/3; abono de +300,00 € en ordinal 4. Fecha 2026-01-05 y lista ordenada de campos, incluidos nombres repetidos y valor vacío. | No verifica fechas, signos, hoja/fila o texto interpretados desde un archivo bancario. |
| Reapertura y categorización | Cierre/reapertura de SQLite conserva procedencia e identidades; categorización posterior por repositorio cambia el REAL y conserva categoría original nula. | No recorre el editor ni los enlaces de la pantalla Openbank. |
| Mismos bytes renombrados | SHA-256 idéntico produce `ImportAlreadyImported`; imagen completa sin cambios después de categorizar. | Los bytes no son un XLS caracterizado. |
| Archivos distintos solapados | Huella distinta exige revisión de todas las coincidencias; confirmar conserva el existente y añade el nuevo. | No prueba el lector de dos extractos solapados. |
| Error y cancelación | Error de interpretación bloquea el lote entero. Revisar y descartar, también con cuenta nueva preparada, no escribe. Error con ese plan tampoco crea referencias. | La cancelación se modela sin llamar al confirmador; no prueba botones o selector. |
| Cambio concurrente | Segunda conexión confirma una coincidencia después de revisar; revisión obsoleta se rechaza sin cambios. Nueva revisión y aceptación explícita permiten alta. | Verifica la revalidación común, no interfaz bancaria. |
| Fallo de escritura | Trigger temporal falla al insertar metadatos después de cuenta y dos REAL; rollback deja todas las tablas idénticas. Retirar trigger permite reintentar. | Fallo SQLite inyectado; no simula fallo físico de disco. |
| Fotos patrimoniales | Imagen protegida idéntica tras importación, categorización, repetición, solapamiento, concurrencia, fallo/reintento y reapertura final. | Sigue pendiente demostrarlo con saldos informativos de un Openbank realmente leído. |

## Verificación y límites

Resultados locales del 2026-10-08:

- Flutter 3.47.0 / Dart 3.13.0 y `scripts/check-toolchain.ps1`: correctos.
  El SDK local informa canal `[user-branch]`; no se cambia SDK ni lockfile.
- Guion reforzado de host: correcto con `--no-pub --concurrency=1`. El sandbox
  impide el bloqueo de ficheros de recuperación; la ejecución con permisos
  nativos pasa. No se elimina ni sustituye la protección del almacén.
- `scripts/check-quality.ps1`, primera ejecución: dependencias fijadas,
  formato (277 archivos) y análisis correctos; suite con 1.299 aprobadas y
  tres fallos en `drive_two_installations_test.dart` y
  `local_recovery_journey_test.dart` (timeouts y errores posteriores de
  recuperación). Las cuatro variantes de arranque no se ejecutaron en ese
  intento. El guion se reforzó después; su versión final se comprueba aparte.
  Reintento del script completo con `--concurrency=1` en sus llamadas a
  `flutter test`, mediante función PowerShell local, sin editar el script:
  formato (278 archivos) y análisis correctos, 1.301 pruebas aprobadas y un
  fallo en `wealth_photo_screen_test.dart`, caso «Ruta conserva febrero,
  Atrás protegido y guardado actualiza origen con pendientes»: no encontró
  el texto de deuda pendiente después de guardar. Los tres fallos iniciales
  no se reprodujeron en este reintento. La prueba propia pasa en ambas suites.
  El archivo patrimonial completo, ejecutado después por separado con una
  sola prueba concurrente, pasa sus 15 pruebas. Las cuatro variantes de
  arranque `development`/`test`/`production`/`invalid-synthetic` se ejecutaron
  aparte y pasan. **No se acredita una ejecución completa limpia del script
  de calidad.** No se modifican las pruebas o pantallas ajenas donde se
  observaron estos fallos; los reintentos aislados no borran esa evidencia.
- `flutter build windows --release --no-pub --dart-define=APP_ENV=test`:
  correcto; EXE release generado.
- `flutter build apk --debug --no-pub --dart-define=APP_ENV=test`: correcto;
  APK generado con JDK 17.0.20.1, Platform 36, Build-Tools 36.0.0 y NDK
  28.2.13676358 disponibles. Configuración Flutter aislada bajo `.tools`,
  aplicada solo al proceso, para seleccionar JDK 17 sin cambiar la
  configuración compartida que usa el JDK 25 de Android Studio.
- Windows nativo: guion correcto mediante `flutter drive --profile`.
  `flutter test -d windows` en debug no pudo enlazar `_CrtDbgReport` con
  Visual Studio Community 2026 Insiders 18.11.12224.323. El primer intento
  también detectó un import faltante en los mensajes de diagnóstico del
  guion, corregido antes de la ejecución correcta. Profile mostró el aviso
  de plugin `integration_test` no detectado; el driver VM recibió el resultado
  `allTestsPassed`, las aserciones se ejecutaron y el proceso terminó con cero.
- Android nativo: guion correcto mediante `flutter test -d emulator-5554`,
  en emulador x86_64 API 37 existente, compilando con SDK 36/JDK 17. El primer
  intento se rechazó antes de importar por la ruta con enlaces internos;
  la versión final usa el directorio temporal canónico y pasa. No se prueba
  teléfono físico, selector nativo ni interfaz Openbank. Se cerró el emulador
  iniciado para este ticket al finalizar.
- `flutter doctor -v` confirma JDK 17 en la configuración aislada, pero
  conserva avisos por canal local y algunas licencias Android; no se afirma
  un diagnóstico limpio ni se aceptan licencias durante esta entrega.
- `node docs/ep-001/verificar-casos.mjs`: correcto, resultados financieros
  de referencia conservados.

Comandos de reproducción del guion (preparar antes el entorno fijado):

```powershell
flutter test --no-pub --concurrency=1 test/importing/bank_import_wealth_test.dart
flutter drive --driver=test/support/bank_import_wealth_driver.dart --target=integration_test/bank_import_wealth_test.dart -d windows --profile --no-pub --dart-define=APP_ENV=test
# Sustituir <id-android> por un dispositivo o emulador disponible.
flutter test integration_test/bank_import_wealth_test.dart -d <id-android> --no-pub --dart-define=APP_ENV=test
```

Los logs locales se guardan en `.tools/ma-tsk-131-*` (ignorados); no contienen
extractos ni bases personales. Los builds usan el checkout compartido, que
incluye modificaciones concurrentes de Drive. El commit de este ticket contiene
solo pruebas y este informe; no acredita calidad de una copia aislada de esos
cambios ajenos ni verificación del formato o la interfaz Openbank.

## Condición para completar el ticket

Obtener la muestra original anonimizada fuera de Git y completar
MA-TSK-124/125/126/129/130. Ejecutar entonces el recorrido real
selección → lectura → revisión → confirmación → historial → reapertura →
categorización en ambas plataformas con fixtures sintéticos fieles al contrato
observado. Repetir los casos de la tabla, incluyendo rechazo de estructura
desconocida y comparación de fotos ante saldos informativos del archivo.

Esta entrega no acredita aceptación funcional de Openbank ni cierre de épica.
No se altera el estado administrativo de los tickets ni se confirman cambios
concurrentes de Drive, README, EP-008 o fixtures CSV de EP-013.
