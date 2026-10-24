# MA-TSK-258 · Restauración anterior tras reinicios

## Diagnóstico demostrado · 2026-10-22

Base investigada: `00ddcb2de12eae1c01870168bdc574dfda4633f0`, rama
configurada `ticket/ma-tsk-193`, Windows NT 10.0.26300.0, Flutter 3.47.0
(`4cf2416426`), Dart 3.13.0. El verificador de `toolchain.json` acepta estas
versiones; el SDK informa canal `[user-branch]`, no se modifica.
`flutter pub get --enforce-lockfile` resuelve sin cambiar el lockfile.

Se consultó `GET http://localhost:4310/api/data`: My autofinance, EP-031,
MA-TSK-258 en ejecución; el ticket del fallo de disco seguía en backlog.
La respuesta local queda en `.tools/ma-tsk-258-board-read.json` (ignorada).
No se modifica el estado administrativo de los tickets ni se cierra EP-031.

Reproducción original, sin modificar producto ni pruebas:

```powershell
flutter test --no-pub --reporter=expanded test/synchronization/local_recovery_journey_test.dart --plain-name 'EP-001: dos manuales, restauración y recuperación de la anterior tras reinicios'
flutter test --no-pub --reporter=expanded test/synchronization/local_recovery_journey_test.dart
```

- Aislado: timeout a los 30 s; el teardown intenta cerrar durante un intercambio
  y recibe `DatabaseFailureCode.restoring`.
- Archivo: seis aprobadas y dos fallidas, 3 min 25 s. Después del timeout el
  primer cuerpo sigue ejecutándose mientras empieza el segundo `setUp`.
  Aparecen `recoveryRequired`, avisos de conexiones simultáneas y errores de
  limpieza. La aserción tardía del primer caso aparece a los 32 s y el segundo
  falla a los 37 s. Logs: `.tools/ma-tsk-258-before-{isolated,file}.log`.
- Sonda diagnóstica temporal con marcas de fases y un plazo suficiente: el
  recorrido original termina en 37,3 s, con todos los datos e integridad
  correctos y limpieza terminada en 37,4 s. Los siete intercambios publican
  `completed`; el sexto termina su mantenimiento después del segundo 30 y
  todavía falta restaurar M2. Log: `.tools/ma-tsk-258-probe.log`.

La causa comprobada está en el arnés: siete restauraciones duraderas con
validación, reaperturas y retención exceden el plazo predeterminado de 30 s.
Un timeout de un Future no cancela su I/O. El `tearDown` intentaba cerrar el
store activo y el siguiente `setUp` reasignaba las variables `late` compartidas
`support` y `store`. Las funciones de soporte y las continuaciones del caso
anterior podían entonces consultar recursos del siguiente caso.

El timeout aislado descarta que otro test sea necesario para originarlo. La
sonda que completa correctamente separa esa espera insuficiente de un bloqueo
funcional. Los estados erróneos posteriores no acreditan corrupción ni pérdida
de datos del producto; tampoco prueban un defecto en el rollback inyectado.

## Corrección y alcance compartido

Solo cambia `test/synchronization/local_recovery_journey_test.dart`:

- Cada caso posee un fixture y un directorio inmutables; sus reinicios cambian
  únicamente el store de ese fixture. No hay variables de recursos compartidas
  entre casos.
- El teardown espera el cuerpo realmente pendiente, también si su observador
  termina antes, y después cierra SQLite y elimina su propio directorio. La
  limpieza es idempotente y los errores de cierre/borrado siguen propagándose.
- El recorrido de disco tiene un plazo finito de tres minutos, como las pruebas
  existentes con procesos. No se añaden pausas fijas ni reintentos de éxito.
- La regresión pausa la instalación antes de publicar `journal-003.json` con
  dos `Completer`. Termina la espera de un observador, solicita limpieza y
  prepara otro fixture mientras la instalación sigue pendiente. Comprueba que
  la limpieza espera, que el acceso externo sigue bloqueado y que el segundo
  fixture conserva sus datos. Después libera la señal, exige `restored`,
  reinicia, compara todas las tablas y comprueba el borrado de ambas carpetas.
- El recorrido original compara todas las tablas (IDs, revisión, procedencia,
  movimientos, presupuestos, categorías, fichas, liquidez y fotos) antes y
  después de cada reapertura. Ejecuta `integrity_check` y `foreign_key_check`,
  comprueba epoch nuevo, contraste pendiente y ausencia de mantenimiento
  pendiente en cada éxito. Conserva las dos manuales restaurables y exige los
  IDs exactos de las tres automáticas más recientes.

No se cambian `LocalDatabaseStore`, `LocalRestoreService`,
`LocalRestoreRecovery`, persistencia nativa, diarios, contratos financieros,
esquema, pantallas ni SDK/dependencias. Para el ticket del fallo de disco se
conservan la inyección `_FullDisk` y todas sus aserciones; solo pasa a usar el
fixture aislado compartido. No requiere una reparación previa de ese ticket.
Los cambios ajenos de subida/estado de sincronización y README se excluyen de
la entrega. Los controles generales y builds se ejecutan en ese checkout
compartido: sus resultados describen su estado efectivo, no una aprobación de
los cambios concurrentes ni una compilación de un checkout limpio del commit.

## Verificación

Los logs `.tools/ma-tsk-258-*.log` son locales e ignorados. Todos los datos
financieros y directorios de ejecución son sintéticos; no se abre la instalación
personal ni se accede a OAuth/Drive.

La validación del sandbox falló inicialmente al resolver antecesores de rutas
temporales Windows; `pub` también encontró red restringida. Las ejecuciones
efectivas usan permisos revisados. Esos fallos de infraestructura se distinguen
del timeout reproducido fuera del sandbox.

Verificaciones del 2026-10-22 y del 2026-10-24, con el mismo código de prueba
(SHA-256 `607e00a0f6311b0a058624bad49445e253e047fec5179d29cd94098294fb9a0e`).
La entrega registra separadamente el resultado de este ticket y los fallos
del control general del checkout compartido.

Comandos de verificación del cambio (sin aumentar el timeout por CLI):

```powershell
# APPDATA y flutter config --build-dir apuntan a carpetas privadas .tools
# para separar compilaciones y evitar los ajustes de la instalación personal.
flutter test --no-pub --reporter=expanded test/synchronization/local_recovery_journey_test.dart --plain-name 'EP-001: dos manuales, restauración y recuperación de la anterior tras reinicios'
flutter test --no-pub --reporter=expanded test/synchronization/local_recovery_journey_test.dart --plain-name 'observador terminado: drena la restauración y aísla el siguiente fixture'
flutter test --no-pub --reporter=expanded test/synchronization/local_recovery_journey_test.dart
flutter test --no-pub --reporter=expanded test/synchronization/local_recovery_journey_test.dart --plain-name 'fallo de disco tras instalar: rollback íntegro y sin contraste nuevo'
flutter test --no-pub --reporter=expanded test/synchronization
./scripts/check-quality.ps1
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
node docs/ep-001/verificar-casos.mjs
git diff --check
```

| Control | Resultado efectivo |
| --- | --- |
| Original aislado, tres ejecuciones consecutivas | 1/1 en cada una: 38, 59 y 86 s |
| Regresión aislada, tres ejecuciones consecutivas del 2026-10-24 | 1/1 en cada una: 15, 16 y 7 s; sin verificaciones concurrentes |
| Archivo completo corregido | 9/9, 4 min 16 s; incluidas las tres terminaciones de proceso |
| Fallo de disco aislado, test original del commit base | 1/1, 8 s el 2026-10-24; sin modificar `_FullDisk` ni restauración |
| Fallo de disco aislado, fixture corregido | 1/1, 9 s el 2026-10-22 |
| Caso I de Drive, aislado (archivo ajeno) | 1/1, 24 s el 2026-10-24; vuelve a agotar 30 s con concurrencia por defecto |
| Suite de sincronización nueva, reloj continuo, concurrencia por defecto | 769 aprobadas y 13 fallidas en 7 min 47 s; **9/9 de este archivo correctas**, sin errores de cleanup propios |
| Análisis general con `--fatal-infos --fatal-warnings` | Sin incidencias, 237,9 s |
| Inicio de `scripts/check-quality.ps1`, 2026-10-24 | Toolchain y lockfile correctos; 515 archivos con formato correcto; análisis sin incidencias en 166,3 s |
| Resultado de `scripts/check-quality.ps1` | Fallido; timeout Android de Presupuesto y error de compilación ajeno descritos debajo. No se obtiene un resumen global completo ni se ejecutan sus variantes APP_ENV |
| Contraste aislado de `import_contract_test.dart` con build nuevo | 15/15; el error de compilación del lanzador general no se reproduce |
| Variantes de arranque ejecutadas separadamente | 4/4: `development`, `test`, `production`, `invalid-synthetic`; logs `.tools/ma-tsk-258-bootstrap-<entorno>.log` |
| Casos financieros EP-001/EP-008 y `git diff --check` | Correctos; referencias repetidas tras la reanudación, log `.tools/ma-tsk-258-reference.log` |
| Windows release, `APP_ENV=test` | Correcto, 278,4 s; salida privada `.tools/ma-tsk-258-native-build/windows/x64/runner/Release/` |
| Android debug, `APP_ENV=test` | Correcto, 57,4 s; `build/app/outputs/flutter-apk/app-debug.apk`, JDK Temurin 17.0.20.1+1 |

Una tercera carga inicial de la regresión no llegó a ejecutar tests: Flutter
no pudo borrar `sqlite3.dll` usada por verificaciones concurrentes en este
checkout, incluso con directorios de build distintos. Se conserva
`.tools/ma-tsk-258-isolated-1-3.log` y se repiten las tres ejecuciones en serie.
No se cambia el producto ni se borra una DLL cargada para sortearlo.

Control negativo de la regresión: una copia diagnóstica ignorada del test,
`.tools/ma-tsk-258-mutant_test.dart`, retira únicamente `await _running` del
teardown. La misma regresión falla con `DatabaseFailureCode.restoring` al
intentar cerrar durante la instalación pausada; salida 1 en 17 s. Log:
`.tools/ma-tsk-258-mutant.log`. La copia usa carpetas sintéticas bajo `.tools`,
limpiadas al terminar el proceso. El código entregado conserva el drenaje.

## Fallos ajenos conservados

La suite nueva completa está en
`.tools/ma-tsk-258-synchronization-final.log`. No se declara calidad global
correcta. Estos trece casos fallan en archivos no modificados por MA-TSK-258:

| Archivo | Casos fallidos |
| --- | --- |
| `drive_two_installations_test.dart` | caso I; descarga network; descarga invalid; descarga cancel; subida interrumpida; edición durante subida; acuse perdido tras publicar; carrera aceptada |
| `local_backup_catalog_test.dart` | siguiente éxito poda exceso; reloj atrasado; desempate por orden 10 > 9 |
| `safe_drive_download_application_test.dart` | no abandonar subida pendiente de otra identidad; T07 descargar y recuperar explícitamente la versión local |

Se observan timeouts y errores posteriores de conexiones/cleanup, además de
aserciones de esos recorridos. El caso I pasa aislado; ello no demuestra por
sí solo la causa de cada uno de los otros fallos. No se suprimen aserciones,
se cambian sus timeouts ni se reparan estos archivos en este ticket. El
recorrido original, la regresión de aislamiento y las interrupciones de
MA-TSK-258 completan la misma suite sin fallos propios.

El control general `.tools/ma-tsk-258-quality.log` aporta además:

- `test/budget/budget_lifecycle_test.dart`, «EP-011 recorrido SQLite de
  archivo: android»: `TimeoutException after 0:00:45.000000`, en
  `budget_lifecycle_journey.dart:462`, seguido de trazas de conexión cerrada.
- El script termina con salida 1 al capturar un error del compilador en
  `test/importing/import_contract_test.dart:468:27`: el switch de
  `ImportConfirmationResult` no cubriría `ImportNothingToImport()`.
  Ese subtipo no aparece en los archivos actuales de `lib` ni `test`, el
  package config apunta a este repositorio y esos fuentes no tienen cambios
  en Git. `flutter test --no-pub --reporter=expanded
  test/importing/import_contract_test.dart` en un build privado nuevo pasa
  sus 15 pruebas (`.tools/ma-tsk-258-import-contract-isolated.log`). El
  error no se reproduce en ese contraste; su origen concreto no queda
  demostrado. No se atribuye a un cambio financiero ni se modifica el
  contrato para silenciarlo.

El último progreso persistido del control general es 363 aprobadas y una
fallida; **no es un resultado final de toda la suite**. El error de compilación
sale como excepción del lanzador, fuera del resumen parcial del log. Por ello
no se declaran aprobadas las pruebas generales no registradas ni se reutiliza
el resultado histórico 2.047/4 como si correspondiera a esta entrega.

## Límites

La primera suite de sincronización se interrumpió por discontinuidad del
entorno: empezó el 2026-10-22 y la sesión se reanudó el 2026-10-24; el reporter
salta de `02:xx` a `2691:xx`. Los timeouts simultáneos posteriores a ese salto
no sirven para validar los plazos. Se conserva el log original
`.tools/ma-tsk-258-synchronization.log` y se detiene con Ctrl+C, sin borrar
ficheros en uso. Antes del salto ya habían fallado por timeout «caso I» y,
después, «descarga network» de `drive_two_installations_test.dart`, además de
un caso de catálogo local; se registran y se contrastan en una ejecución nueva.

Una inyección de excepción o una terminación de proceso no simula todas las
averías de disco ni un corte eléctrico. La regresión por señales modela el
abandono de la espera sin introducir un test intencionalmente fallido en la
suite. Las pruebas SQLite se ejecutan en el host Windows; compilar Android no
acredita un recorrido en teléfono/emulador. No hay nueva aceptación visual ni
se infiere el cierre de los otros dos tickets de EP-031.

## Entrega

Commit de implementación verificada:
`c08b7386e4bffe63f57a628799e995b053e37ced`. Contiene exclusivamente el archivo
de pruebas; este informe se confirma después para registrar ese hash. Ambos
se entregan a la rama configurada `origin/ticket/ma-tsk-193`, sobre la base
`00ddcb2de12eae1c01870168bdc574dfda4633f0`, sin force-push.

Los únicos archivos de MA-TSK-258 son
`test/synchronization/local_recovery_journey_test.dart` y este informe. Los
cambios ajenos de README, subida/estado Drive y archivos no versionados de
otros tickets permanecen fuera de ambos commits. No se cierra EP-031 ni se
afirma calidad global completa a partir de estos resultados.
