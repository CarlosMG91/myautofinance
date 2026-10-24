# MA-TSK-260 · Caso D de Patrimonio en Windows

Verificación del 2026-10-24. Ticket íntegro facilitado por el usuario; no hay
conector Epic Board disponible y no se ha cambiado el estado del tablero.
Base de trabajo: `947add243442b446e824d33c4afd59fbe0826343`, rama configurada
`ticket/ma-tsk-193`. EP-001, EP-004 y la presentación EP-026 v1 se conservan.

## Diagnóstico reproducible

La evidencia original `.tools/openbank-quality.log` se ha leído: el timeout
Windows ocurre en `settle → enter → create`, al buscar Nombre después del
rechazo/cancelación. No acredita pérdida de datos. En esta sesión el Caso D
sin cambios pasó aislado (1 prueba, 1:34) y sus dos variantes pasaron dentro de
Patrimonio. Esa suite original terminó con 85 aprobadas y un fallo diferente:
`wealth_photo_screen_test.dart`, «Ruta conserva febrero, Atrás protegido y
guardado actualiza origen con pendientes», línea 295, texto de pendientes
ausente. También registró `This database has already been closed` en su salida.
No se atribuye ese fallo al Caso D ni se modifica esa prueba.

Se han demostrado dos problemas distintos en la transición:

1. En producto, `AccountCatalogScreen._open` hacía
   `setState(() => _data = data)`. La asignación devuelve el Future y Flutter
   lanza `setState() callback argument returned a Future` en debug. El catch
   presentaba «No se pudo abrir o actualizar la ficha» y ejecutaba el finally
   sin esperar la relectura. Se ha capturado su pila en
   `.tools/260-catalog-diagnostic.log`. La actualización usa ahora un bloque
   síncrono que no devuelve el Future y conserva el `await data` posterior.
2. En el recorrido de prueba, ausencia de indicadores de carga no implica que
   la acción esté habilitada. El catálogo conserva sus filas mientras relee,
   mantiene `_opening` y deshabilita Crear ficha. El clic automatizado podía
   consumirse sin abrir el formulario; después se esperaba Nombre hasta agotar
   el límite. El helper espera ahora la habilitación del botón concreto antes
   de pulsarlo. No cambia los límites ni añade esperas temporales fijas.

La nueva variante «Rechazo, cancelación y nueva alta con catálogo pendiente:
windows» usa las mismas rutas, formularios y SQLite en disco del Caso D.
Un Completer retiene la resolución del servicio de relectura tras descartar
el alta rechazada. Comprueba, antes de liberarlo:

- Una resolución del servicio pendiente, Crear ficha deshabilitado, Nombre
  ausente y ningún `AfStatus` de carga: estado que el helper anterior confundía
  con disponibilidad para pulsar. Se registra también el foco en los timeouts.
- SQLite responde a SELECT y el contenido completo de accounts, periodos,
  fotos, valores, movimientos y revisión coincide con el anterior al rechazo.
  El trigger ABORT ha terminado y el rollback no deja escritura parcial; no se
  afirma que una consulta retenida sea un bloqueo nativo de SQLite.
- La resolución se libera en el siguiente frame explícitamente programado,
  sin temporizador ni duración elegida para provocar la carrera.

Retirando solo la espera de habilitación, la regresión final falla en 18 s
con la misma pila `settle → enter → create` y Nombre ausente
(`.tools/260-regression-red.log`). Con la espera, pasa
(`.tools/260-regression-green.log`). La aserción de ausencia del error del
catálogo también protege la corrección de producto. La instrumentación
temporal para leer excepciones se ha retirado. La reproducción controlada
falla aislada con una carpeta nueva por prueba: no necesita interferencia
entre pruebas ni compartir una conexión para producir el síntoma. La ejecución
histórica concreta no contiene trazas suficientes para reconstruir su agenda
exacta; se conserva esta distinción respecto al mecanismo demostrado.

Tras la liberación se introduce Cuenta principal, se comprueba el campo
habilitado y su foco, se guarda exactamente una ficha y se conserva el retorno
a enero de 2026. Se cierra/reabre la conexión, se comparan todas las tablas,
se consulta la ficha por ID y se comprueban `integrity_check = ok` y ausencia
de infracciones de claves foráneas.

El Caso D completo mantiene sus aserciones de cuentas/ahorro/cartera/deuda,
fotos ausentes/parciales/cero/completas, corrección sin cambiar identidades,
rollback, liquidez histórica, bajas, cancelaciones, reapertura y periodo de
retorno. No se calculan saldos desde movimientos ni se cambian las cifras de
referencia de EP-001. La regresión reutiliza el mismo arranque y limpieza.

## Entorno y comandos

Flutter 3.47.0 (framework `4cf2416426`, canal reportado `[user-branch]`),
Dart 3.13.0; verificador
`scripts/check-toolchain.ps1` correcto. No se actualizan SDK ni lockfile.
Las compilaciones usan Temurin JDK 17.0.20.1+1, Android API 36 (revisión 2),
Build Tools 36.0.0 y la configuración Android existente.
Configuración Flutter por proceso mediante APPDATA temporal y
salidas `.tools/260-*-build`; no se cambia la configuración personal.

El primer intento restringido encontró `PathAccessException` al resolver
`C:\Users\carlo`, anterior a abrir SQLite. Se repitió con permisos nativos,
sin modificar las protecciones de recuperación. Una salida compartida
preexistente tenía sqlite3.dll en uso; se usaron salidas nuevas sin borrar
archivos en uso. El primer `pub get` restringido no alcanzó pub.dev; su
repetición autorizada con `--enforce-lockfile` sí resolvió las dependencias.

Comandos repetibles desde el repositorio, con permisos para resolver las rutas
nativas y una salida de build exclusiva si hay otros procesos Flutter:

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub test/wealth/wealth_lifecycle_test.dart --reporter expanded
flutter test --no-pub test/wealth --reporter expanded
./scripts/check-quality.ps1
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
git diff --check
```

Las repeticiones aisladas ejecutan el archivo completo (Caso D Windows,
Caso D Android y regresión Windows) tres veces consecutivas; las de suite
ejecutan todo `test/wealth` tres veces consecutivas. Los logs ignorados se
conservan en `.tools/260-isolated-{1,2,3}.log` y
`.tools/260-suite-{1,2,3}.log`. El control general queda en
`.tools/260-quality.log`; compilaciones en `.tools/260-build-{windows,android}.log`.

## Resultados y entrega

Implementación: commit `544c21b` (solo catálogo y los dos archivos de prueba).
Las verificaciones se ejecutan con ese contenido de código; el checkout
conserva además los cambios concurrentes preexistentes de sincronización.

| Comprobación | Resultado |
| --- | --- |
| Archivo Caso D, aislado, tres ejecuciones consecutivas | 3/3 en cada una: 4:23, 4:37 y 4:16 |
| Caso D Windows por nombre exacto, tres procesos | Una aprobada en cada uno: 1:08, 1:02 y 1:01 |
| Regresión Windows por nombre exacto, tres procesos | Una aprobada en cada uno: 0:14, 0:13 y 0:13 |
| Suite Patrimonio, ronda 1 | 87 aprobadas, cero fallos, 4:31 |
| Suite Patrimonio, ronda 2 | 84 aprobadas, tres fallos ajenos, 4:40; los tres recorridos de MA-TSK-260 aprobados |
| Suite Patrimonio, ronda 3 | 87 aprobadas, cero fallos, 4:14 |
| Formato global | 515 archivos, cero cambios |
| Análisis global | Sin incidencias, 286,6 s |
| `scripts/check-quality.ps1` | Ejecutado; termina con código 1 por dos pruebas ajenas |
| Suite general | 2.052 aprobadas, dos fallidas, 18:14; Caso D Windows/Android y regresión aprobados |
| Windows release, APP_ENV=test | Correcto, 333,6 s |
| Android debug, APP_ENV=test | Correcto, 61,3 s |
| Arranques development/test/production/invalid-synthetic | Una prueba aprobada por modo |

Los dos Casos D y la regresión pasan así tres veces consecutivas tanto
aislados como dentro de Patrimonio. No se afirma que las tres suites completas
sean verdes: la segunda falla en dos casos de `wealth_composition_test.dart`
(«Un controlador existente consulta la base reemplazada al restaurar», timeout
de 30 s con limpieza/uso después de dispose, y «Catálogo completo y detalle
cerrado conservan identidad e historial», limpieza con archivo en uso) y en
el texto de pendientes de `wealth_photo_screen_test.dart` ya observado antes
del cambio. Se ejecutaron en paralelo verificaciones con salidas distintas;
no se ha determinado la causa de esos otros fallos ni se han modificado.

Artefactos de compilación locales: ejecutable en
`.tools/260-app-build/windows/x64/runner/Release/myautofinance.exe` y APK en
`build/app/outputs/flutter-apk/app-debug.apk`, sin versionar.

Los arranques se verifican por separado porque el fallo general detiene el
script antes de esa fase. `development` pasó en la salida del recorrido; los
otros tres primeros intentos encontraron sqlite3.dll en uso. Se repitieron con
una salida nueva por modo y pasaron los tres: logs
`.tools/260-bootstrap-{test,production,invalid-synthetic}-fresh.log` y
`.tools/260-bootstrap-development.log`. No se borró ni desbloqueó la DLL.

La suite general falla en:

- `budget_lifecycle_test.dart`, «EP-011 recorrido SQLite de archivo: windows»:
  timeout de 45 s en `budgetLifecycleJourney.io`, invocado desde la línea 462.
- `wealth_photo_screen_test.dart`, «Ruta conserva febrero, Atrás protegido y
  guardado actualiza origen con pendientes»: falta el texto
  `Pendientes: Z Deuda sintética`, como en la reproducción de la suite original.

El script se detiene en su línea 19 antes de los cuatro arranques, comprobados
separadamente. No se declara calidad global completa ni se cambian esas pruebas.

Además del aislamiento del archivo completo, se ejecutan por nombre exacto,
en procesos separados, el Caso D Windows y la regresión, tres veces cada uno:

```powershell
flutter test --no-pub test/wealth/wealth_lifecycle_test.dart --plain-name 'Caso D completo en archivo SQLite: windows' --reporter expanded
flutter test --no-pub test/wealth/wealth_lifecycle_test.dart --plain-name 'Rechazo, cancelación y nueva alta con catálogo pendiente: windows' --reporter expanded
```

Logs `.tools/260-windows-exact-{1,2,3}.log` y
`.tools/260-transition-exact-{1,2,3}.log`: las seis ejecuciones terminan con
código 0. Esta comprobación adicional elimina la ambigüedad entre aislar el
archivo de pruebas y aislar cada caso individual.

Destino de entrega: `origin/ticket/ma-tsk-193`, la rama configurada. El commit
de implementación y este informe incluyen únicamente archivos de MA-TSK-260;
no se incluyen cambios concurrentes ni se utiliza force-push.

## Límites

Las pruebas de interacción son widgets ejecutados en el host Windows con
SQLite real en archivos temporales sintéticos. TargetPlatform.android cambia
el comportamiento/adaptación Flutter; no demuestra ejecución en Android real.
No se ha realizado un recorrido con runner nativo, emulador ni dispositivo
físico en este ticket. Las compilaciones tampoco equivalen a aceptación visual
MA-TSK-217. No se toca la instalación financiera personal, Drive/OAuth, reglas
financieras, migraciones ni los dos tickets de recuperación de EP-031.

Los cambios concurrentes preexistentes de sincronización, README y archivos
sin seguimiento quedan fuera de la entrega. No se cierra la épica a partir
de este ticket y se informan los fallos generales aunque no sean de su alcance.
