# MA-TSK-243 · Resultado del ensayo release

**Ticket sin completar: bloqueo nativo al abrir la instalación nueva.**
La repetición del 2026-10-20 en **API 24/4 KB y API 36/16 KB de emulador**
identifica la misma causa:
el alias del sistema `/data/user/0 → /data/data` es rechazado por
`BackupStorage.safe()` antes de crear o abrir SQLite. El aviso de recuperación
pendiente oculta ese `invalidMetadata`. No se ha modificado la política de
almacenamiento compartida para eludirlo.

No se acredita conservación N → N+1 ni cierre de EP-029. El
[runner y su contrato](actualizacion-release.md) están preparados; el
[resumen estructurado](evidencia-actualizacion.json) diferencia los builds
verificados de los pasos nativos no alcanzados.

## Comprobado el 2026-10-19

- Epic Board consultado: MA-TSK-243 `in-progress`; T05/MA-TSK-241 y
  T06/MA-TSK-242 entregados. Fuentes compiladas: commit
  `d218446928e83eff5d65e73b230b21eae40776a7` más el overlay sintético del ensayo,
  en checkout aislado. El trabajo concurrente de sincronización y prototipos
  del checkout principal no se incluyó en estos APK.
- Flutter 3.47.0/Dart 3.13.0/JDK 17.0.20.1; compile/target 36,
  Build Tools 36.0.0 y NDK 28.2.13676358. `check-toolchain.ps1` correcto.
  Sin cambios de SDK, lockfile, identidad, esquema o fuentes financieras.
- Dos APK **universales release reales**, generados por T05 con firma
  efímera independiente de T02, `APP_ENV=test`, no debuggable:

| APK | Versión | SHA-256 |
| --- | --- | --- |
| N | 0.1.0+24301 | `3aa0157b41648faba2421a57b2359a8f6f8fe76a0bd77ba0401c264bd01a0627` |
| N+1 | 0.1.1+24302 | `226d52cc671db0daa4bc3d01b65783c60402a8fd28c545565238998f41295fba` |

Ambos tienen paquete `com.carlosmg91.myautofinance` y certificado SHA-256
`abe949c03734e7806097da41cb95251e9a428b673f193b19adadb50ce753db47`.
Pasan apksigner, aapt2, ZIP de 16 KB, ELF LOAD/RELRO, payload y estabilidad
de entradas; incluyen 12 bibliotecas en arm64-v8a, armeabi-v7a y x86_64:
engine Flutter release, libapp, SQLite y JNI, además de canales/plugins nativos.
Esto verifica los archivos efectivos, sin atribuirles una actualización exitosa.

## Bloqueo real

Se creó el AVD desechable `Autofinance243`, `emulator-5580`, sin Autofinance
instalada. No se utilizó la instalación debug del emulador habitual
`emulator-5554`. Imagen Android 17/API 37:
`google/sdk_gphone64_x86_64/emu64xa:17/CE2A.260420.019/15611780:user/release-keys`.
Páginas de **4096 bytes**, `primaryCpuAbi=x86_64`; la lista del emulador anuncia
también traducción arm64-v8a, que no acredita un teléfono ARM64.

La instalación de N por `adb install -r` terminó correctamente. PackageManager
confirma versión `0.1.0`, código `24301`, mínimo 24 y target 36.
La Activity release arranca y devuelve el resultado mediante el proveedor
controlado. Sin embargo, la primera llamada a `LocalDatabaseStore.open()` falla
antes de cargar CSV, crear fotos, copias, estado Drive o sesión:

> La base está bloqueada por una restauración o recuperación pendiente.

El stack se detiene en `local_database_store.dart:168`, dentro del `catch`
que transforma cualquier error de `LocalRestoreRecovery.recover()` en
`DatabaseFailureCode.restoring`. Esa clasificación por sí sola **no demuestra**
que hubiera un diario anterior: la instalación era nueva y aún no se había
ejecutado ninguna restauración. Tampoco acredita la causa interna exacta.

Se conserva el resultado raw y los logs en
`.tools/243-native-CFt92L/`, con los APK y manifiestos privados. SHA-256 del
`evidence.json` de esa ejecución:
`1d5e4110f0023bd4afaa6956db62587f52bde9fa94ddfa2fd8bd16686fc8d372`.
La fixture inicial enviaba texto con la codificación HTTP por defecto; la
versión final fuerza UTF-8 para conservar correctamente los acentos del error.

Se detuvo el AVD conservando sus discos e instalación. No se instaló N+1,
no se forzó otra firma, no se desinstaló ni se borraron datos para hacer pasar
el ensayo. La clave efímera se eliminó al terminar; repetir desde cero exige
otro AVD desechable, sin reutilizar esa instalación con una clave nueva.

## Comprobaciones del soporte de prueba

- 48 pruebas Node aprobadas: contrato APK, generador T05, almacenamiento T06
  y tres pruebas del oráculo de actualización. Estas últimas rechazan cambios
  de identidad/revisión, Discrecionalidad/procedencia, archivos Drive, clave y
  ciphertext; permiten únicamente la evolución explícita del catálogo/diario
  durante recuperación, conservando imágenes y estado Drive.
- Formato de la fixture correcto y análisis específico sin incidencias.
- `actionlint` correcto en ambos workflows afectados. La matriz nueva API 24/36
  usa AVD nuevos y claves efímeras; no tiene upload de APK/claves ni firma T02.
  Una definición de workflow no constituye evidencia de ejecución remota.
- `node docs/ep-001/verificar-casos.mjs`: correcto; 48 presupuestos, 10 reales,
  enero +1229,75 EUR, real anual +2329,65 EUR y presupuesto +13200,00 EUR.

El runner contiene las comprobaciones de rechazo de versión/firma y candidatos
incompatibles SDK/ABI, con relectura del estado tras cada rechazo. También
contiene parada/reapertura, reinicio del dispositivo, interrupción de transacción
y restauración. **Esos pasos no se han alcanzado en la ejecución nativa local.**

## Calidad general

`scripts/check-quality.ps1` termina con error: **2006 aprobadas y 7 fallidas**
en 24:44. Versiones, resolución con `--enforce-lockfile`, formato de 505 archivos
y análisis estático son correctos. Fallos de la suite:

| Archivo | Casos |
| --- | --- |
| `test/movements/pending_lifecycle_test.dart` | Windows tabla y Android tarjetas: `StateError: No element` al localizar widgets. |
| `test/synchronization/local_recovery_journey_test.dart` | Dos manuales/restauración/reinicio; fallo de disco tras instalar; cuarta fallida y retención; candidata truncada. Hay timeouts, archivos ocupados y errores secundarios de recuperación/conexión. |
| `test/wealth/wealth_lifecycle_test.dart` | Caso D Windows. |

Estos archivos no cambian en el ticket. La suite se ha ejecutado en el checkout
principal con trabajo concurrente conservado; no se atribuye una causa sin
comprobarla ni se declara aprobado el control global. Log privado completo:
`.tools/243-quality.log`. Los tests de interrupción de procesos existentes sí
se ejecutan dentro de esta suite de host; no se confunden con el recorrido
Android N → N+1 que está bloqueado.

## Pendiente para aceptar el ticket

Diagnosticar y resolver el fallo real de apertura respetando el propietario y
la política de almacenamiento existente; repetir después el recorrido completo
en una instalación desechable. No se ha cambiado el resolver para esquivar el
fallo, simulado SQLite, relajado el control de rutas ni modificado otras épicas.

Al terminar el intento del 2026-10-19 quedaban sin verificar preservación
financiera y de copias/diarios/drive-sync,
descifrado con la misma clave y ciphertext después de actualizar, rechazos
nativos y atomicidad/recuperación entre versiones. En aquel intento API 24 y 36
no estaban instaladas localmente; tampoco había runtime de 16 KB ni teléfono físico ARM64.
La alineación estática de ambos APK sí está comprobada.

Google real, APK production definitivo, teléfono ARM64 y Openbank real siguen
en T09, con el requisito directo MA-TSK-131 de EP-014. No se sustituyen por
cuentas, sesiones, XLS o lectores inventados. No se cambian estados del tablero
ni se declara completo el ticket por disponer de builds y fixtures.

## Repetición 2026-10-20 · API 24

Se utiliza el contrato del ticket facilitado por el usuario. En esta sesión no
hay conector Epic Board ni pestañas accesibles para reconsultar el estado vivo;
no se cambia su estado. Los cambios concurrentes de EP-007 y los prototipos
del checkout principal permanecen fuera de los commits y de los APK del ensayo.

AVD nuevo `Autofinance243Api24_20261020`, `emulator-5584`, Android 7.0/API 24,
ABI efectiva x86_64 (también anuncia x86), páginas medidas de **4096 bytes**.
Fingerprint:
`Android/sdk_google_phone_x86_64/generic_x86_64:7.0/NYC/6696031:userdebug/dev-keys`.
Fuente aislada: `f717d0c373474d33bca3d81dcb8fd9c4b676ae20`.

La primera tentativa detectó que esta imagen no incluye `getconf`; se detuvo
antes de generar claves o instalar APK. El runner ahora mide `KernelPageSize`
desde `/proc/self/smaps` sin root, rechaza ausencia/ambigüedad y exige contrastar
después con `Os.sysconf` dentro de N. Sus pruebas cubren 4/16 KB y los rechazos.

La repetición genera N por T05, universal release `APP_ENV=test`,
`0.1.0+24301`, no debuggable, paquete `com.carlosmg91.myautofinance`:

- APK SHA-256: `b627290c0c98078e9b5a77798e66cda6f56ba6b9e67db3453554e9a3ef32e58c`.
- Certificado efímero SHA-256: `ccfd8263d7dd41ba7ec6c6bbae066ea6617568f0394ecc3d79981a095d9eb0b7`.
- T05 aprueba manifiesto, firma, payload, ZIP/ELF de 16 KB y estabilidad de
  entradas. Incluye 12 bibliotecas (engine release, AOT, SQLite y JNI).
- `adb install -r` tiene éxito. PackageManager instalado confirma versión
  `0.1.0`, código `24301`, mínimo 24, target 36 y ABI x86_64.

La Activity release ejecuta la fixture y devuelve el error de apertura en UTF-8.
El diagnóstico dentro de la propia app observa `/data/user/0` como `link`,
resuelto a `/data/data`; reproduce `invalidMetadata` en
`lib/features/synchronization/data/backup_storage.dart:123`. El store lo
transforma en `DatabaseFailureCode.restoring` en `local_database_store.dart:168`.
No es prueba de un diario pendiente ni de corrupción de SQLite: se rechaza un
antecesor de la ruta de soporte suministrada por Android en una instalación nueva.

Se detiene antes del CSV y de las fotos, copias, estado Drive y sesión cifrada.
No se genera ni instala N+1; conservación, Keystore, rechazos y recuperación
siguen sin acreditar. No se desinstala, borra datos, fuerza downgrade ni cambia
el resolver para hacer pasar la fixture. Se detiene el AVD conservando discos e
instalación; el `finally` del runner elimina su clave efímera externa al repo.

Evidencia privada: `.tools/243-native-3qpJXe/evidence.json`, SHA-256
`02eff55336c0ab2287475aea58b4145a3ef412ab7a121e155d34f4b5fae102a8`.
Los APK, logs completos, snapshots y claves no se publican.

## Repetición 2026-10-20 · API 36 y páginas de 16 KB

AVD nuevo `Autofinance243Api3616K_20261020`, `emulator-5586`, Android 16/API 36,
ABI x86_64 y **16384 bytes medidos por `getconf`**. La ABI arm64-v8a que también
anuncia la imagen es traducción y no acredita un teléfono físico ARM64.
Fingerprint:
`google/sdk_gphone16k_x86_64/emu64xa16k:16/BE2A.250530.026.F3/13894323:userdebug/dev-keys`.
Se instalaron exclusivamente imágenes oficiales de prueba API 24 y 36/16 KB;
Flutter, Dart, JDK, build-tools, plataforma de compilación, NDK y lockfile
permanecen fijados. Los AVD se ejecutaron con una CPU al observar un bloqueo
de arranque SMP en WHPX. El perfil de 16 KB se detuvo temporalmente conservando
sus discos por falta de memoria libre y se reanudó, todavía sin la app instalada,
después de terminar API 24 y la suite general.

T05 genera otro **N** universal release `APP_ENV=test`, `0.1.0+24301`, desde
`f717d0c373474d33bca3d81dcb8fd9c4b676ae20`, con firma efímera propia de este
ensayo independiente:

- APK SHA-256: `5f676f64d4ce01bac6addd59cc89e19dae5aeca6bb098b91fd0da706e1767af3`.
- Certificado SHA-256: `8fbed2ca4c2810a11a431870f4ae5413100425f2843334b8aa1ed4a358f801bb`.
- Mismos seis controles T05 aprobados y 12 bibliotecas nativas en el payload.
- Instalación correcta; PackageManager confirma `0.1.0+24301`, mínimo 24 y
  target 36. La fixture release ejecuta HTTP y `path_provider` sobre este runtime.

La apertura vuelve a fallar **antes del dataset**. El diagnóstico dentro de
la app identifica el mismo enlace `/data/user/0 → /data/data` y el mismo
`invalidMetadata` de `BackupStorage.safe()`. Se acredita ejecución inicial del
APK con 16 KB; SQLite, preservación entre versiones, Keystore y recuperación
siguen bloqueados. No se genera N+1 ni se atribuyen los dos N de estos ensayos
independientes a una pareja de actualización válida.

Evidencia privada: `.tools/243-native-Kc4Qlf/evidence.json`, SHA-256
`08f584a149b0fb4ce6ba66f519aa3f7aa838de33c27d6b2df95a2386b3e1e0e9`.
Se elimina la clave efímera mediante `finally` y se detiene el AVD conservando
discos e instalación. La repetición de N→N+1 necesita corregir el bloqueo en
su módulo propietario y usar perfiles nuevos; no se puede reutilizar estas
instalaciones con otra clave. API 36/4 KB y los recorridos completos de API 24
y API 36/16 KB siguen pendientes. El resumen JSON v2 registra ambos intentos,
sus hashes y diagnósticos; conserva la referencia al intento del 2026-10-19.

## Calidad de la repetición 2026-10-20

- **50 pruebas Node aprobadas**: contrato APK, T05, T06 y cinco casos del
  oráculo/medición de páginas de T07. Se exige conservar también cada diario
  y archivo de soporte previo durante recuperación; solo pueden cambiar los
  dos slots de catálogo.
- Prueba Flutter del transporte GET/POST: aprobada, conserva acentos y € en
  JSON UTF-8. Formato específico y `actionlint` de la matriz: correctos.
- Casos financieros EP-001: correctos, sin cambios de fórmulas ni de lector.
- `scripts/check-quality.ps1`: versiones, lockfile, formato de 506 archivos y
  análisis sin incidencias; suite **1974 aprobadas y 40 fallidas** en 32:47.
  El script se detiene antes de repetir la matriz de arranque `APP_ENV`.

Hay fallos/errores secundarios en los recorridos de presupuesto, desgloses,
navegación histórica, pendientes, patrimonio y sincronización (dos
instalaciones, catálogo, restauración, recuperación y descarga segura).
Estos archivos no se modifican en T07. La suite se ejecutó en el checkout
principal con trabajo concurrente conservado, junto a preparación nativa;
se observó presión de memoria y no se atribuye una causa a todos los fallos
sin aislarla. No se declara aprobado el control global. Log completo privado:
`.tools/243-retry-quality.log`.

La matriz CI queda preparada para API 24/4 KB, API 36/4 KB y API 36/16 KB;
comprueba las medidas efectivas y muestra hashes/versiones en logs. No sube
APK ni claves. Su configuración y el push no acreditan una ejecución remota.
