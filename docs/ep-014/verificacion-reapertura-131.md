# MA-TSK-131 · Reapertura y traspaso a MA-TSK-245

Comprobación del 2026-10-18. **Bloqueado: no se acredita el recorrido Openbank
ni se cumplen los criterios de cierre de MA-TSK-131 o EP-014.**

## Requisitos contrastados

Se consulta `GET http://localhost:4310/api/data`, tablero **My autofinance**,
workspace coincidente, MA-EPIC-123, sus ocho tickets y MA-TSK-245 de EP-029.
MA-TSK-124/125/126/129/130 figuran como `done`, pero las entregas comprobadas
contradicen que estén resueltos sus requisitos funcionales:

| Requisito | Evidencia disponible | Carencia que impide verificar Openbank |
|---|---|---|
| MA-TSK-124 | [Caracterización](caracterizacion-openbank.md), comprobación del 2026-10-18 | Declara ausencia de muestra y formato sin caracterizar. Adjuntos de épica y tickets vacíos; no se facilita ruta privada. |
| MA-TSK-125 | [Lector](lector-openbank.md) e inventario de `lib/features/importing/data` | No hay lector Openbank; solo lector/adaptador CSV, selectores y SHA-256. |
| MA-TSK-126 | [Adaptación](adaptacion-nucleo.md) | No hay adaptador Openbank ni salida del lector que adaptar. |
| MA-TSK-129 | Nota local `fixtures/MA-TSK-129-bloqueo.md` | No hay bytes procesables ni resultados derivados de muestra; esa nota no es un fixture y estaba sin seguimiento al iniciar esta tarea. |
| MA-TSK-130 | [Integración](integracion-recorrido.md), commit `63630e7` | Documenta el bloqueo. En `lib/app/navigation/app_router.dart`, la entrada `openbank` tiene `enabled: false` y muestra «Recorrido pendiente de conectar». |

El inventario `git ls-files --cached --others --exclude-standard`, filtrado por
nombres Openbank, adjuntos y extensiones XLS/XLSX/XLSB/ODS, no localiza muestras
ni fixtures bancarios. No se inspeccionan carpetas privadas externas o archivos
ignorados para inferir que tampoco existan allí. Se solicita al usuario la ruta
privada accesible de la muestra original anonimizada y, si existen fuera del
checkout, las entregas faltantes. **No se han leído bytes de un extracto** ni
deducido formato por extensión. No se inventa un XLS ni se reutiliza MyFinance.
MA-TSK-127/128 y su evidencia se conservan sin cambios.

## Alcance de la regresión ejecutable existente

El [guion compartido](../../test/support/bank_import_wealth_journey.dart), su
[entrada de host](../../test/importing/bank_import_wealth_test.dart) y su
[entrada nativa](../../integration_test/bank_import_wealth_test.dart) prueban
EP-012 sobre SQLite con `ImportSession`/`ImportInterpretation` construidas en
test, bytes arbitrarios y versión `synthetic-contract-131`. No atraviesan un
lector, adaptador o pantalla Openbank. No se presentan como fixtures MA-TSK-129.

El guion comprueba cuenta pendiente y vinculación explícita; tres REAL por
un total de +275,00 €, incluidos dos cargos legítimos iguales de −12,50 € con
ordinales 2/3; originales, cuenta, reapertura y categorización por repositorio;
repetición renombrada cero altas; solapamiento revisado sin eliminación;
rechazo de error, revisión descartada, concurrencia y rollback de fallo tardío
con referencia nueva preparada. Compara todas las tablas en operaciones
rechazadas y las filas/columnas de `wealth_snapshots`, `wealth_values` y
`budgets` tras los cambios aceptados y la reapertura. Incluye foto completa,
incompleta y mes sin foto, dos cuentas, cartera, deuda y saldo cero.

El campo arbitrario «saldo sintético informativo» conservado en originales
**no prueba** el tratamiento de saldos de un archivo Openbank. La cancelación
se modela descartando la revisión, sin interacción con selector/pantalla.
El fallo de escritura se inyecta mediante trigger SQLite, no fallo físico.
La evidencia histórica detallada se conserva en
[verificación integral](verificacion-integral.md).

## Ejecución de esta reapertura

Punto de partida: commit `63630e7`, rama configurada `ticket/ma-tsk-193`, remoto
`origin` del proyecto. El checkout contiene cambios concurrentes de Drive,
README, EP-008/013/015 y la nota de bloqueo de fixtures EP-014; quedan fuera de
los cambios de esta tarea. Las comprobaciones se hacen sobre ese checkout
compartido, sin atribuir a esta tarea sus cambios ni probar una copia aislada.

Flutter 3.47.0, revisión `4cf2416426`, Dart 3.13.0;
`scripts/check-toolchain.ps1` correcto. El SDK informa canal `[user-branch]`;
no se cambia de canal, SDK o lockfile. JDK Temurin 17.0.20.1+1 disponible en
`.tools/jdk17-094/jdk-17.0.20.1+1`; paquetes locales Android Platform 36
(revisión 2), Build-Tools 36.0.0 y NDK 28.2.13676358 comprobados mediante sus
`source.properties`. La configuración Flutter aislada existente
`.tools/ma-tsk-131-flutter-config/.flutter_settings` selecciona ese JDK para
los comandos de compilación, aplicando `APPDATA` solo al proceso.

Resultados de compilación y comprobaciones auxiliares de esta sesión:

| Comprobación | Resultado | Evidencia local ignorada |
|---|---|---|
| Windows release, `APP_ENV=test`, `--no-pub` | Correcto; `build/windows/x64/runner/Release/myautofinance.exe`. CMake usa Visual Studio 18 2026, instalación Insiders x64. | `.tools/ma-tsk-131-reapertura-build-windows.log` |
| Android debug, `APP_ENV=test`, `--no-pub` | Correcto con JDK 17; `build/app/outputs/flutter-apk/app-debug.apk`. No es el APK final de producción de MA-TSK-245. | `.tools/ma-tsk-131-reapertura-build-android.log` |
| Guion patrimonial de host, dentro de la suite | Correcto; cuenta, originales, ordinales, repetición, solapamiento, concurrencia, rollback y fotos idénticas tras reapertura final. | `.tools/ma-tsk-131-reapertura-quality-network.log`, mensajes `MA-TSK-131:` |
| Guion patrimonial Windows nativo, `flutter drive --profile` | Correcto, salida cero y `All tests passed` recibido por el driver VM. Aparece el aviso de plugin `integration_test` no detectado; no se presenta como captura mediante ese plugin. | `.tools/ma-tsk-131-reapertura-native-windows.log` |
| Guion patrimonial Android nativo, `flutter test -d emulator-5554` | Correcto, salida cero y `All tests passed`; emulador existente `sdk_gphone64_x86_64`, API 37, ABI x86_64, compilado con SDK 36/JDK 17. Sin teléfono físico ni selector/pantalla Openbank. | `.tools/ma-tsk-131-reapertura-native-android.log` |
| Casos EP-001, `node docs/ep-001/verificar-casos.mjs` | Correctos: 48 presupuestos/10 reales, enero +1.229,75 €, real anual +2.329,65 €, presupuesto anual +13.200,00 €. | Salida de comando en la sesión. |

En Android debug aparece el aviso Drift de múltiples instancias al abrir la
segunda conexión independiente prevista en el caso concurrente. No se suprime
el aviso; las aserciones de revalidación, rollback y reapertura se completan.
No se inicia ni cierra el emulador preexistente. Ambos recorridos nativos usan
bases temporales sintéticas que el guion elimina al terminar.

La primera ejecución de `scripts/check-quality.ps1` no supera `pub get` por
restricción de red al consultar los avisos de pub.dev. El reintento con acceso
autorizado resuelve las dependencias con `--enforce-lockfile`, sin modificar
`pubspec.lock`; formato: 505 archivos, cero cambios; análisis: sin incidencias.
La suite registra estos fallos, sin cambios de esta tarea en sus archivos:

| Archivo/caso | Fallo observado en la suite |
|---|---|
| `test/drilldowns/report_drilldown_journey_test.dart`, MA-TSK-194 Windows | `Bad state: No element` en `reportDrilldownJourney.tap`, al buscar el elemento por clave de real. |
| `test/movements/pending_lifecycle_test.dart`, Windows tabla y Android tarjetas | `Bad state: No element` en `pendingLifecycleJourney.tap`, al buscar `PopupMenuButton<String>`. Son pruebas de host con tamaños de pantalla distintos, no las ejecuciones nativas anteriores. |
| `test/synchronization/local_backup_catalog_test.dart`, desempate 10 > 9 | Timeout de 30 segundos. |
| `test/synchronization/local_recovery_journey_test.dart` | Cuatro casos: dos manuales/restauración (timeout), fallo tras instalar (`rejected` en vez de `restored`), retención tras cuarta fallida (timeout) y copia truncada (imagen esperada distinta). |

Resultado final de la suite: **2.005 pruebas aprobadas y ocho fallidas**,
24 min 50 s. El script termina con error y no alcanza sus cuatro variantes de
arranque. No se declara calidad global correcta.

Un primer reintento dirigido, mientras seguía la suite, no llegó a ejecutar
pruebas: Flutter no pudo eliminar `sqlite3.dll`, cargada en el directorio
de build compartido. Su log es
`.tools/ma-tsk-131-reapertura-failed-directed.log`. Tras terminar la suite se
repite con concurrencia uno y configuración privada en
`.tools/ma-tsk-131-reapertura-host-config`, con build separado
`.tools/ma-tsk-131-reapertura-host-build`, sin cambiar configuración compartida.

La repetición aislada de los ocho casos termina en **seis aprobados y dos
fallidos**, 2 min 1 s. Se reproducen ambos casos de
`pending_lifecycle_test.dart`, con la misma búsqueda fallida de
`PopupMenuButton<String>`. Los otros seis pasan, sin modificar código ni
pruebas. Ese reintento no acredita una suite completa limpia ni determina la
causa de los fallos no reproducidos. Log:
`.tools/ma-tsk-131-reapertura-failed-isolated.log`.

Las cuatro variantes de arranque se ejecutan aparte, secuencialmente y con la
misma configuración privada: `development`, `test`, `production` e
`invalid-synthetic` pasan, una prueba por variante, salida cero. Logs
`.tools/ma-tsk-131-reapertura-bootstrap-<APP_ENV>.log` y resumen
`.tools/ma-tsk-131-reapertura-bootstrap-results.json`. Estos resultados no
convierten en correcta la ejecución fallida del script completo.
Los logs `.tools/ma-tsk-131-reapertura-*` no contienen muestras bancarias y están
ignorados.

Las pruebas nativas recompilan su propio target y reutilizan la salida APK
debug; esa ruta no identifica un APK de producción ni un artefacto entregado.

Comandos de reproducción desde el workspace con el entorno fijado preparado:

```powershell
flutter --version
./scripts/check-toolchain.ps1
# Incluye pub get --enforce-lockfile, formato, análisis, suite y cuatro APP_ENV.
./scripts/check-quality.ps1
# Repetición de los ocho casos fallidos, después de terminar la suite:
flutter test --no-pub --concurrency=1 --name 'MA-TSK-194 tres informes SQLite: windows|EP-015 completo con SQLite|EP-001: dos manuales|fallo de disco tras instalar|desempate por orden|cuarta fallida conserva exceso|truncated:' test/drilldowns/report_drilldown_journey_test.dart test/movements/pending_lifecycle_test.dart test/synchronization/local_backup_catalog_test.dart test/synchronization/local_recovery_journey_test.dart
foreach ($taskEnvironment in @('development', 'test', 'production', 'invalid-synthetic')) {
    flutter test --no-pub --concurrency=1 "--dart-define=APP_ENV=$taskEnvironment" test/environment_bootstrap_test.dart
}
flutter test --no-pub --concurrency=1 test/importing/bank_import_wealth_test.dart
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
flutter drive --driver=test/support/bank_import_wealth_driver.dart --target=integration_test/bank_import_wealth_test.dart -d windows --profile --no-pub --dart-define=APP_ENV=test
# Emulador de pruebas observado: emulator-5554, API 37, x86_64.
flutter test integration_test/bank_import_wealth_test.dart -d emulator-5554 --no-pub --dart-define=APP_ENV=test
node docs/ep-001/verificar-casos.mjs
```

Los comandos nativos del [informe histórico](verificacion-integral.md) siguen
siendo reproducibles para el **contrato sintético EP-012**, sin que su ejecución
acredite la lectura o el recorrido de Openbank. No se instalan APK de producción
ni se usa una base personal en esta tarea.

## Traspaso a EP-029 · MA-TSK-245

**Entrega funcional Openbank no disponible; este informe no habilita su
verificación final en el APK.** MA-TSK-245 exige expresamente el recorrido real
y no admite un estado `done` sin evidencia. No hay dependencia inversa de
MA-TSK-131 respecto a firma, empaquetado u OAuth; esas tareas pueden avanzar.

Tras recibir la muestra, completar MA-TSK-124/125/126/129/130 y sustituir la
entrada sintética del recorrido por fixtures derivados del contrato observado.
Registrar para cada fixture su ubicación, SHA-256, versión de contrato/lector,
hoja/fila/ordinal, campos originales, fechas, importes, conteos y total esperado.
Ejecutar selección → lectura/adaptación → revisión/cuenta/solapamientos →
confirmación → lote/Sin clasificar → reapertura → categorización en Windows y
Android con SQLite, comparando fotos pobladas antes/después también ante saldos
informativos leídos. Repetir rechazos y rollback sin lotes/referencias parciales.

La entrega deberá identificar commit, versiones, plataforma/dispositivo,
comandos y resultados, evidencias sintéticas y límites. MA-TSK-245 deberá repetir
ese recorrido en el APK exacto de producción instalado e identificar su hash;
un build debug o el guion de contrato no lo sustituye. Este traspaso registra
la carencia y el protocolo pendiente, sin modificar MA-TSK-245 ni estados del
tablero. No se cierra el ticket por documentar el bloqueo.
