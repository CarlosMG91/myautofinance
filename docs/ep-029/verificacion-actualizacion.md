# MA-TSK-243 · Resultado del ensayo release

**Ticket sin completar: bloqueo nativo al abrir la instalación nueva.**
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

## Pendiente para aceptar el ticket

Diagnosticar y resolver el fallo real de apertura respetando el propietario y
la política de almacenamiento existente; repetir después el recorrido completo
en una instalación desechable. No se ha cambiado el resolver para esquivar el
fallo, simulado SQLite, relajado el control de rutas ni modificado otras épicas.

Quedan sin verificar preservación financiera y de copias/diarios/drive-sync,
descifrado con la misma clave y ciphertext después de actualizar, rechazos
nativos y atomicidad/recuperación entre versiones. API 24 y 36 no están
instaladas localmente; tampoco hay runtime de 16 KB ni teléfono físico ARM64.
La alineación estática de ambos APK sí está comprobada.

Google real, APK production definitivo, teléfono ARM64 y Openbank real siguen
en T09, con el requisito directo MA-TSK-131 de EP-014. No se sustituyen por
cuentas, sesiones, XLS o lectores inventados. No se cambian estados del tablero
ni se declara completo el ticket por disponer de builds y fixtures.
