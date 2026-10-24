# MA-TSK-259 · Reversión tras fallo de disco al instalar

## Diagnóstico y alcance · 2026-10-24

Base: `7f366a6d73f3ffa44b1eba6e79a288dd002a57be`, rama configurada
`ticket/ma-tsk-193`. Windows NT 10.0.26300.0, Flutter 3.47.0 (`4cf2416426`),
Dart 3.13.0.
El SDK informa canal `[user-branch]`; no se cambia el SDK, el lockfile,
el esquema, las reglas financieras ni las pantallas.

Se consultó `GET http://localhost:4310/api/data`: My autofinance,
MA-EPIC-257/MA-TSK-259 en ejecución, MA-TSK-258 entregado y MA-TSK-260 pendiente.
Instantánea local ignorada: `.tools/ma-tsk-259-board.json`. No se modifica
el estado administrativo del tablero ni se declara cerrada la épica.

El log histórico `.tools/openbank-quality.log`, líneas 3423–3435, recoge
`recoveryRequired` en lugar de `rolledBack` y, después, `errno = 32` al borrar
el directorio. Antes aparecen el timeout del recorrido de siete restauraciones,
su cierre durante el intercambio y continuaciones tardías de ese cuerpo.
La excepción de limpieza es secundaria: no demuestra pérdida de datos.

La causa del arnés es compartida con MA-TSK-258: el timeout del observador no
cancela el I/O; las variables `late support/store` originales cambiaban al
preparar el caso siguiente. El store y las funciones de soporte pendientes
podían entonces abrir la carpeta de ese nuevo caso. La corrección de esa causa
(fixture por caso y drenaje del cuerpo antes de cerrar/borrar) ya forma parte
de la base de este ticket. Se conserva y se comprueba específicamente con la
inyección de disco; no se cambia el resultado del producto para ocultar el fallo.

Contrastes sin instrumentación:

- Caso original aislado en la base actual: 1/1, 5 s, antes de editar pruebas.
  Log `.tools/ma-tsk-259-before-authorized.log`.
- Copia del archivo de `00ddcb2`, anterior a la reparación del arnés: los dos
  recorridos originales seguidos pasan 2/2 en 28 s (primero 23 s). Se usa
  `--name 'EP-001:|fallo de disco'`; solo se adapta el import relativo porque
  la copia está en `.tools`. Log `.tools/ma-tsk-259-baseline-pair.log`.
  Esta ejecución no vuelve a alcanzar el timeout de 30 s del log histórico.
  No se afirma que el síntoma ocurra en cada ejecución ni que el aislamiento
  por sí solo pruebe la causa.

Control causal repetible, con la regresión nueva y señales `Completer`:

1. Pausar el movimiento de `journal-003.json` antes de lanzar la misma excepción
   `_FullDisk`. Terminar la espera de un observador y preparar otro fixture.
2. En una copia diagnóstica, reintroducir únicamente un resolvedor de soporte
   compartido reasignable entre fixtures: la operación de disco devuelve
   **`recoveryRequired`**, donde la regresión exige `rolledBack`. Se reproduce
   el síntoma sin tocar el servicio de restauración ni esperar a un timeout.
   `.tools/ma-tsk-259-shared-mutant.log`, salida 1, 3 s.
3. En otra copia diagnóstica, retirar únicamente `await _running` del teardown:
   falla el cierre con `DatabaseFailureCode.restoring` durante la instalación.
   `.tools/ma-tsk-259-drain-mutant.log`, salida 1, 6 s.
4. Con el código entregado, el mismo orden controlado termina con rollback,
   reinicio, lectura, restauración normal y borrado; el siguiente fixture
   conserva todas sus tablas. No hay esperas fijas ni cambios de timeout.

Las copias diagnósticas son archivos ignorados bajo `.tools`, con bases
sintéticas privadas. No se incorporan a la suite ni al commit. El control
negativo separa la interferencia entre fixtures del comportamiento de un disco
que siguiera fallando durante la recuperación. No acredita todas las posibles
averías físicas ni una pérdida real de datos personales.

## Comprobaciones incorporadas

Solo cambia `test/synchronization/local_recovery_journey_test.dart`, sobre la
versión entregada por MA-TSK-258:

- `_FullDisk` conserva el destino, excepción y comportamiento de fallo único.
  Añade una observación opcional antes de lanzar para inspeccionar o pausar
  la fase exacta, sin abrir otro store ni usar servicios de producción falsos.
- Al fallar, los diarios publicados son `protected → isolating → installing`.
  La candidata ya está instalada y contiene la imagen manual original; la
  anterior aislada contiene todas las tablas de la imagen modificada. No queda
  candidata en staging ni se ha publicado `journal-003.json`.
- El resultado debe ser `rolledBack` con respaldo válido. El diario archivado
  añade `rollingBack → rolledBack`, sin `installed`, `validated` ni `completed`;
  la candidata fallida sigue conservada en diagnósticos. Se comprueban ambas
  imágenes con conexiones SQLite de solo lectura cerradas en `finally`.
- Se compara la activa completa antes y después del reinicio: tablas, IDs,
  linaje, revisión, procedencia, movimientos, presupuesto, fichas, fotos y
  liquidez histórica. `integrity_check = ok` y `foreign_key_check` vacío.
- Con contraste previo resuelto, se exige `required = false`, señal fiable
  y conservación exacta del epoch. La manual conserva los hashes de todos sus
  archivos. El respaldo publicado existe, está validado y se restaura y lee
  efectivamente antes de reintentar la manual y comprobar su imagen original.
- El caso de cuarta restauración fallida compara el contraste previo pendiente
  y su epoch no nulo antes/después del fallo y del reinicio. Exige los mismos
  IDs anteriores más el respaldo nuevo, y conserva byte a byte los archivos
  de todas las copias anteriores. Solo el éxito siguiente puede podar a tres.
- La regresión nueva termina al observador mientras la inyección está pausada,
  solicita limpieza y prepara un fixture distinto. La limpieza debe esperar
  hasta completar fallo → rollback → reinicio → lectura → reintento satisfactorio.
  Comprueba el borrado real y que el otro fixture conserva sus datos.
- El envoltorio de los recorridos comprueba expresamente que el directorio
  temporal se elimina después de terminar el cuerpo. El teardown idempotente
  continúa registrado también para las aserciones fallidas.

No cambian `LocalRestoreService`, `LocalDatabaseStore`, recuperación al inicio,
diarios, contratos ni persistencia nativa. `recoveryRequired` conserva su
comportamiento conservador si no puede comprobarse una imagen anterior utilizable;
las regresiones de restauración incluyen el rollback imposible y el bloqueo
de acceso. Los cambios concurrentes de subida/estado Drive y README se excluyen.

## Verificación

Todos los comandos usan datos sintéticos y el directorio de soporte inyectado;
no se abre la instalación personal ni OAuth/Drive. `APPDATA` y el build de Flutter
se aíslan en `.tools/ma-tsk-259-config` y `.tools/ma-tsk-259-build`.
Las pruebas se ejecutan en serie por invocación, sin lanzadores Flutter
simultáneos que compitan por la DLL SQLite. La concurrencia interna de cada
suite conserva su valor por defecto.

El primer intento del sandbox falla antes de sembrar SQLite, al resolver las
rutas temporales nativas, y `pub` falla por red restringida. No reproduce el
fallo del ticket. La ejecución efectiva con permisos revisados resuelve
`flutter pub get --enforce-lockfile` y reproduce la inyección; no cambia el
lockfile. Los logs son `.tools/ma-tsk-259-*.log`, ignorados.

Un primer lanzador PowerShell local leyó sin UTF-8 los nombres acentuados de
los filtros de tres repeticiones: salida 79, «No tests match», sin ejecutar
ninguna prueba. No se cuentan como resultados de la inyección. Se conserva
su log y se repiten los filtros con un prefijo ASCII inequívoco; no se cambia
el nombre ni el cuerpo del test para resolver esa incidencia del lanzador.

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub --reporter=expanded test/synchronization/local_recovery_journey_test.dart --plain-name 'fallo de disco tras instalar: rollback íntegro y sin contraste nuevo'
# Filtro ASCII usado en las tres repeticiones finales: selecciona solo ese caso.
flutter test --no-pub --reporter=expanded test/synchronization/local_recovery_journey_test.dart --name '^fallo de disco tras instalar:'
flutter test --no-pub --reporter=expanded test/synchronization/local_recovery_journey_test.dart --plain-name 'fallo de disco con observador terminado: drena rollback antes de limpiar'
flutter test --no-pub --reporter=expanded test/synchronization/local_recovery_journey_test.dart test/synchronization/local_restore_test.dart
flutter test --no-pub --reporter=expanded test/synchronization
./scripts/check-quality.ps1
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
node docs/ep-001/verificar-casos.mjs
git diff --check
```

Código final de la prueba, SHA-256:
`5930cdf574b9f07f9e9ab8e2b03189672fcdd20b3363d814694d80f9c8546fad`.

| Control | Resultado |
| --- | --- |
| Inyección original ampliada, tres ejecuciones aisladas finales consecutivas | **1/1 en cada una**, 11, 12 y 10 s; logs `.tools/ma-tsk-259-verified-original-{1,2,3}.log`, con el código final identificado arriba |
| Regresión nueva aislada, tres ejecuciones | 1/1 en cada una, 7 s las tres |
| Archivo de recorridos y `local_restore_test.dart` juntos | 53/53, 2 min 33 s; restauración normal, rollback imposible y procesos interrumpidos incluidos |
| Suite de sincronización, concurrencia por defecto | **783/783**, 3 min 30 s; archivo de recorridos completo 10/10, sin errores de limpieza |
| `scripts/check-quality.ps1`: toolchain, lockfile, formato y análisis | Versiones correctas, dependencias fijadas resueltas, 515 archivos sin cambios de formato; análisis sin incidencias en 125,5 s |
| `scripts/check-quality.ps1`: batería general | **2.048 aprobadas, cinco fallidas**, 25 min 37 s; las diez del archivo de recuperación pasan sin errores propios de limpieza. Salida 1 por los casos ajenos descritos debajo |
| Variantes de arranque ejecutadas separadamente | 4/4: `development`, `test`, `production`, `invalid-synthetic` |
| Windows release, `APP_ENV=test` | Correcto, 161,3 s; `.tools/ma-tsk-259-build/windows/x64/runner/Release/myautofinance.exe` |
| Android debug, `APP_ENV=test` | Correcto, 88 s; `build/app/outputs/flutter-apk/app-debug.apk`, JDK 17 |
| Referencias financieras EP-001/EP-008 y `git diff --check` | Correctos; sin cambios de SDK, contratos, esquema ni lockfile |

Las compilaciones del checkout compartido no validan ni entregan los cambios
ajenos. Las pruebas SQLite del host Windows
y un APK compilado no acreditan el recorrido en un dispositivo Android ni una
aceptación visual.

`flutter doctor -v` registra Visual Studio Community 2026 Insiders
18.11.12224.323 y Windows SDK 10.0.26100.0; JDK Temurin
17.0.20.1+1 y Android Build-Tools 36.0.0. También detecta una plataforma API 37
adicional instalada. No se cambia la configuración API/NDK del proyecto ni se
usa ese emulador para una prueba de este ticket. Doctor mantiene dos avisos:
el canal `[user-branch]` existente y licencias Android adicionales no aceptadas.
Se conservan SDK y canal; no se ejecuta la aceptación de licencias.

## Incidencias ajenas del control general

En `.tools/ma-tsk-259-quality.log`, `test/budget/budget_lifecycle_test.dart`
falla en «EP-011 recorrido SQLite de archivo: windows» y «…: android».
Ambos registran `TimeoutException after 0:00:45.000000`, con origen en
`budget_lifecycle_journey.dart:462` y trazas de conexión cerrada al terminar.
Son archivos sin cambios en esta entrega; no se determina aquí la causa de
esos timeouts ni se cambian sus aserciones o plazos. Ese resultado impide
declarar calidad global correcta aunque la suite de sincronización sea verde.

El mismo control general registra además dos casos de
`test/synchronization/drive_two_installations_test.dart`, sin cambios propios:

- «caso I»: timeout de 30 s, limpieza con archivo en uso (`errno = 32`) y una
  aserción tardía de comparación de tablas del mismo caso.
- «descarga network conserva todas las tablas y permite reintento manual»:
  `Channel was closed before receiving a response`.

Ambos pasan dentro de la suite de sincronización independiente 783/783 de esta
entrega. Se registra la diferencia entre ambas ejecuciones; no se considera
demostrada aquí la causa de cada error de Drive ni se modifica ese arnés.

El quinto caso fallido del control general es
`test/synchronization/local_backup_catalog_test.dart`, «desempate por orden
10 > 9 y no por cadenas»: timeout de 30 s y error secundario de limpieza con
archivo en uso. También pasa en la suite de sincronización independiente.
No se cambia ese archivo ni se atribuye su timeout a una pérdida financiera.

El resumen completo de la batería, no un progreso parcial, es 2.048/5.
El script no ejecuta sus variantes de arranque tras esa salida 1; se ejecutan
separadamente. No se oculta ningún fallo ni se declara calidad global aprobada.
El Caso D de Patrimonio Windows pasa en esta ejecución; no se infiere el cierre
de MA-TSK-260 ni la aceptación de EP-031 a partir de ese resultado aislado.

## Entrega

Commit del código verificado:
`c2bcf1c8d75d24bcda1fc0dc37d991493b5793ff`, sobre
`7f366a6d73f3ffa44b1eba6e79a288dd002a57be`. Contiene exclusivamente
`test/synchronization/local_recovery_journey_test.dart`. Este informe se
incorpora en un commit posterior para registrar ese hash.

Destino de ambos commits: la rama configurada `origin/ticket/ma-tsk-193`,
sin force-push. Los únicos archivos propios del ticket son ese test y
`docs/ep-031/ma-tsk-259.md`. README, subida/estado Drive, archivos no
versionados de otros tickets, SDK, compilaciones y logs locales quedan fuera
de la entrega. No se modifica el tablero ni se cierra EP-031.
