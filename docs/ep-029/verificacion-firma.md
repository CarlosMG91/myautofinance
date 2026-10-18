# MA-TSK-238 · Verificación de firma privada

Comprobaciones locales del 2026-10-18. La [guía de custodia](firma-distribucion.md)
contiene rutas por variables de usuario, comandos y recuperación; el
[PEM público](../../packaging/android/distribution-certificate.pem) permite
contrastar la identidad sin acceder al material privado.

## Firma y recuperación reales

Se ha creado una única clave RSA 4096 / SHA256withRSA con JDK 17, fuera del
repositorio. PKCS#12 cifrado y credenciales DPAPI CurrentUser en carpeta de ACL
privada. Respaldo portátil AES-256-CBC + HMAC-SHA256 y llave aleatoria separada,
también privados. No se imprime ni versiona contraseña, alias o llave.

`Create`, `Check` y `Recover` han probado la clave real: restauración del
respaldo en un temporal nuevo, apertura del PKCS#12 y firma de una petición de
certificado con la clave privada recuperada. La recuperación conserva SHA-1
`6a1557043d8b3f9fce356a2532aae09f81cd93f3` y SHA-256
`d6e624f1402fcc0df84cda5373a0b2a89321bd62cb2340a8d69a4a3e663b1951`.
El comando `Recover` también ha generado material DPAPI nuevo en un destino
temporal independiente, que se ha eliminado tras verificarlo. Los originales
y el respaldo permanecen intactos; los builds nunca invocan `Create`.

No se ha probado otro dispositivo/usuario Windows ni se ha trasladado la copia
a un soporte independiente. La copia local separada no cubre pérdida del disco.
La llave de recuperación debe custodiarse separada del respaldo cifrado.

## Origen del APK técnico

Base Git: `a7074a9809c4870c4b4561f135371e1adaaaf727`, rama configurada
`ticket/ma-tsk-193`. El primer intento usa `git archive HEAD` y solo superpone
los cambios propios de firma. Gradle configura correctamente, pero Dart falla:
HEAD importa `drive_upload.dart` y `drive_upload_factory.dart`, todavía ausentes
en Git. Es una dependencia previa de sincronización; no se modifica su motor.

Para obtener **solo la prueba técnica de firma**, se copia `lib/` del árbol de
trabajo actual al snapshot aislado `.tools/238-checkout/`. Incluye los cambios
concurrentes preexistentes de sincronización y sus archivos nuevos necesarios;
se conserva inventario privado de rutas relativas/hashes en
`.tools/ma-tsk-238-technical-source-inventory.json`. Estos cambios ajenos no
forman parte del commit del ticket. El APK resultante no se identifica como
una entrega final reproducida exclusivamente desde un commit limpio.

Flutter 3.47.0 / Dart 3.13.0 comprobados mediante `flutter --version` y
`check-toolchain.ps1`. `pub get --enforce-lockfile` sin modificar el lockfile.
JDK 17.0.20.1, SDK/Build-Tools 36.0.0 y NDK 28.2.13676358 existentes. El NDK
se conserva según el contrato; este ticket no acredita compatibilidad 16 KB.
Configuración Flutter aislada del usuario: JDK 17, build-dir `build`; Gradle
sin daemon persistente/configuration-cache. `APP_ENV=production`, release
universal, sin override de versión ni configuración OAuth nueva.

La generación inicial de plugins en el snapshot requiere uniones NTFS locales
para los plugins Windows; no se activa Developer Mode ni se cambia el sistema.
El build muestra una advertencia previa por la familia de iconos `AfOutline`;
no se corrige dentro del ticket de firma ni se declara aceptación visual.

Un segundo intento detecta registrantes de desarrollo (`integration_test`)
incompatibles con release. El SDK fijado omite regenerarlos con `--no-pub`:
se prepara ahora tooling release con `--config-only`, sin clave en el entorno,
tras `pub get --enforce-lockfile`. El hash del lockfile se comprueba idéntico
antes de compilar con `--no-pub`. No se edita el SDK ni el Java generado.

## APK realmente producido y verificado

Salida local privada: `dist-private/android/signing-check/` en el checkout
principal; `autofinance-technical-signature-check.apk` y
`technical-inspection.json`. El mismo archivo se conserva en el snapshot de
verificación. **No es la aplicación completa aceptada ni una actualización
que deba instalarse sobre debug.** No se publica en Git ni artifacts/releases.

| Campo observado | Resultado |
| --- | --- |
| Paquete | `com.carlosmg91.myautofinance` |
| Nombre/código de versión | `0.1.0` / `1` |
| Modo/entorno de generación | release / `APP_ENV=production` |
| Depurable / certificado debug / split | No / No / No |
| SDK mínimo / compile / target | 24 / 36 / 36 |
| ABI | `arm64-v8a`, `armeabi-v7a`, `x86_64` |
| Tamaño | 68.986.851 bytes |
| SHA-256 del **archivo APK** | `72bd6242ceddf0962ea9f3034b279a699a1a4983cd30bdf8952968f7173a3bc0` |
| SHA-1 del **certificado** | `6a1557043d8b3f9fce356a2532aae09f81cd93f3` |
| SHA-256 del **certificado** | `d6e624f1402fcc0df84cda5373a0b2a89321bd62cb2340a8d69a4a3e663b1951` |
| Inspector T01 | `problems=[]`, `completeDelivery=false` |

El inspector usa `java -jar apksigner.jar verify --verbose --print-certs` y
`aapt2 dump badging`, Build-Tools 36.0.0/JDK 17. Exige el SHA-256 del certificado
público independiente y vuelve a calcular el hash del APK tras la inspección.
`check-android-signing-secrets.ps1` comprueba las **369 entradas descomprimidas**
sin encontrar alias, contraseña, ruta del almacén ni archivos privados de firma.

## Pruebas y calidad

- Once comprobaciones sintéticas de custodia: cifrado autenticado portátil,
  rechazo de llave incorrecta/alteración, rutas de repo/relativas/raíces,
  DPAPI, ausencia de secretos en claro, ACL privada y material corrupto.
- Ocho comprobaciones con Gradle real y una sola clave efímera aislada:
  ausencia de material, ruta relativa, contraseña incorrecta, certificado
  distinto, restricción de CI, fixture production rechazada, fixture test
  aceptada en CI y configuración sin material. Se elimina la fixture.
- Contraste adicional de los grafos reales sin clave: `assembleRelease
  --dry-run` falla con `APK-SIGNING[MISSING_MATERIAL]`; `assembleDebug
  --dry-run` pasa. Build real `flutter build apk --debug --no-pub
  --dart-define=APP_ENV=test`: correcto en 84 s, sin cargar la clave de
  distribución. Se conserva como prueba local, separado del APK técnico.
- Nueve pruebas Node del inspector T01 correctas; `actionlint` correcto para
  el workflow modificado y parseo PowerShell/Node sin errores.
- `check-quality.ps1`: versiones, lockfile, formato (505 archivos sin cambios)
  y análisis sin incidencias. Suite completa: **2.009 aprobadas y cuatro
  fallidas** en 16 min 16 s. No se declara calidad global correcta.

Dos fallos son los ya documentados en T01: `pending_lifecycle_test.dart`,
Windows tabla y Android tarjetas, `Bad state: No element` al buscar el menú.
Los otros dos son `local_recovery_journey_test.dart`: el primer caso agota sus
30 s y deja un cierre/bloqueo que afecta al segundo. Repetidos ambos solos con
`--concurrency=1` y sus límites originales, **dos aprobados en 27 s**. No se
modifican sus pruebas ni los servicios. La suite se ejecutó a la vez que
compilaciones; la carga es una posible causa del timeout, no una causa probada.

El script global se detiene antes de las variantes de arranque. Pasan aparte
development/test/production/invalid-synthetic (una prueba por variante). Los logs quedan
bajo `.tools/ma-tsk-238-*`, ignorados. No se compila el runner Windows: los
cambios nativos son solo Gradle Android; la nueva prueba de custodia Windows
sí se ejecuta con DPAPI real. CI se configura para repetirla en Windows y los
escenarios Gradle con clave efímera en Android; no recibe la firma estable.

## Alcance y límites

No se instala sobre ningún dispositivo, no se ejecuta `uninstall`, `clear-data`
ni downgrade. Se mantiene el bloqueo de primera transición desde debug de
certificado distinto hasta disponer de copia externa y recuperación probadas.
No se adopta una clave debug ni se intenta recuperar una clave perdida.

El APK técnico y su JSON llevan `completeDelivery=false`. No acreditan OAuth
Google real, Drive, Openbank, actualización con datos, almacenamiento/backup
nativo T06, teléfono ARM64 ni aceptación de épica. T03/T05/T07/T09 conservan
sus comprobaciones propias. No se publica APK, material privado o logs en Git,
Releases o artifacts de producción. La única identidad versionada es pública.
