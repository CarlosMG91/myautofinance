# MA-TSK-241 · Verificación local del generador

Comprobado el 2026-10-19 en Windows, con Flutter 3.47.0/Dart 3.13.0,
JDK 17.0.20.1, Android SDK/Build Tools 36/36.0.0 y NDK 28.2.13676358.
No se han actualizado SDK, paquetes ni lockfile. Implementación y comandos en
[generador-apk.md](generador-apk.md).

## Resultado propio del ticket

- `node --test scripts/tests/android-delivery.test.mjs scripts/tests/google-oauth-android.test.mjs scripts/tests/android-apk-contract.test.mjs`:
  27 pruebas pasadas, 0 fallos y 1 omitida del comprobador OAuth anterior
  (requiere seleccionar expresamente el APK técnico T02).
- `actionlint .github/workflows/build.yml`: correcto.
- `node scripts/tests/build-android-delivery-fixture.mjs`: salida 0, build
  universal release real y todos los controles sobre el archivo efectivo.
  Clave efímera fuera del repositorio, eliminada al acabar. No se utilizó T02.
- El comando de producción rechazó la configuración actual con
  `Bloqueo externo Android: falta acreditar el proyecto Google común`, antes
  de abrir claves o compilar. No se inventaron IDs ni se deshabilitó el gate.
- Una ejecución durante la implementación compiló pero fue rechazada por
  `INPUT_CHANGED` al cambiar los scripts durante el build; la ejecución válida
  posterior confirma `sourceStable=true`.

## APK de prueba, sin distribución

| Dato | Evidencia |
| --- | --- |
| Entorno/modo | `APP_ENV=test`, `release`, `ci-ephemeral-fixture` |
| Paquete/versión | `com.carlosmg91.myautofinance`, `0.1.0+1` |
| SDK mínimo/compile/target | 24 / 36 / 36 |
| ABIs efectivas | arm64-v8a, armeabi-v7a, x86_64 |
| Firma/debuggable | apksigner correcto; certificado efímero; no debuggable |
| SHA-256 certificado fixture | `879be203df1d5c777a4a56f8562d9e0ec325be1366f5709602357c23c20231d4` |
| SHA-256 APK fixture | `387b2d77fe3d1e805cc977bf3c7f9856afb929369f8ecd9170ae6ebb0408f268` |
| Tamaño | 68 986 851 bytes |
| Bibliotecas | 12: libapp, libflutter, libsqlite3 y libdartjni en cada ABI |
| ZIP / ELF | zipalign `-c -P 16 -v 4` correcto; todos los LOAD al menos `2**14`; RELRO válido |
| Recursos | Manifest, resources.arsc, FontManifest, tres fuentes AfRoboto, DEX/MainActivity y canal nativo Google presentes |
| Commit base | `36249635201425b225efee2202207d4784167061` |
| Entradas SHA-256 | `20effc72bd933c9995e7b43c9cc439128d3f2931844bad4262f9c99f8445ad8a` |

El manifiesto y APK están exclusivamente en la salida local ignorada
`dist-private/android/ci-fixture/<sha256>/`. El árbol estaba dirty, con cambios
propios y concurrentes: el commit base **no** identifica por sí solo todo el
contenido compilado. El hash de entradas registra ese contenido. No se han
incluido cambios concurrentes en la entrega Git del ticket.

La comprobación RELRO distingue el caso de `libflutter.so` arm64, donde RELRO
ocupa su propio LOAD completo: no tiene cola escribible en la página redondeada
y es el caso permitido por Android/Bionic. Las pruebas rechazan expresamente
un LOAD que sí deja datos escribibles dentro de esa protección. No se ha
relajado el control LOAD/ZIP ni cambiado ninguna biblioteca.

## Calidad general y límites

`scripts/check-quality.ps1` verifica las versiones, resuelve el lockfile y pasa
formato (505 archivos, sin cambios) y análisis estático (sin incidencias).
La suite general encuentra dos fallos en
`test/movements/pending_lifecycle_test.dart`, recorridos «Windows tabla» y
«Android tarjetas»: `Bad state: No element`, en
`test/support/pending_lifecycle_journey.dart:82`, al buscar un widget para
`ensureVisible`. Esos módulos no se han modificado en MA-TSK-241. No se declara
verde el control general; sus posteriores comprobaciones de arranque no se
ejecutan al abortar por estos fallos.

El primer intento de resolver dependencias falló por la red del sandbox; el
reintento autorizado con acceso a pub.dev sí resolvió el lockfile. La ejecución
de CI remota queda pendiente del workflow; la ejecución fixture descrita es
local, con el mismo generador, no una ejecución de GitHub Actions.

No se ha generado un candidato production con OAuth, instalado el APK,
comprobado preservación entre versiones ni probado Google real, teléfono ARM64
o ejecución nativa con páginas de 16 KB. Esas evidencias corresponden a
T03/T07/T09. Se mantienen `completeDelivery=false` y `realDriveVerified=false`.
No se publicaron APK, claves, manifiestos de producción ni datos personales.
