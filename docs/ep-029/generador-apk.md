# MA-TSK-241 · Generador local de APK privado

El comando de producción usa la identidad T02 y el control Android T03 existente.
Rechaza CI, firma fixture y configuración Google incompleta antes de compilar o
abrir el material privado. No requiere que Windows OAuth esté preparado.

```powershell
# SDK/JDK locales fijados en toolchain.json; no actualizar herramientas.
./scripts/build-private-android-delivery.ps1 -Jdk $jdk -AndroidSdk $sdk
# MaterialDirectory permite seleccionar otro respaldo T02 ya recuperado.
```

La compilación es universal release, sin overrides de versión y con
`APP_ENV=production` explícito. Inyecta exclusivamente el
`GOOGLE_ANDROID_SERVER_CLIENT_ID` público devuelto por
`loadAndroidOAuthConfiguration()`. Las contraseñas T02 se recuperan mediante
DPAPI y se pasan a Gradle por entorno local; nunca por argumentos o dart-defines.
No se genera otra clave de producción. Consultar [custodia T02](firma-distribucion.md).

El proceso aísla la configuración Flutter, resuelve con
`flutter pub get --enforce-lockfile`, comprueba Flutter/Dart, JDK 17 y los
paquetes SDK/NDK fijados, prepara plugins release mediante `--config-only` y
compila con `--no-pub`. Captura/restaura las variables de entorno incluso ante
fallo. No instala, desinstala, borra datos, autoriza Google ni transfiere copias.

## Comprobaciones sobre el archivo efectivo

- `aapt2 dump badging` contrasta versión de pubspec, paquete, SDK, ABIs y ausencia
  de splits/debuggable; `apksigner verify --verbose --print-certs` valida la firma
  contra el certificado público independiente T02.
- El ZIP debe contener manifiesto, recursos, fuentes AfRoboto, DEX/MainActivity
  y libapp/libflutter/libsqlite3 para cada ABI efectiva.
- `zipalign -c -P 16 -v 4` valida el APK. El `llvm-objdump -p` del NDK fijado
  inspecciona **cada** biblioteca `.so`: inventario, tamaño, hash, compresión,
  offset y alineación de todos los segmentos LOAD. `llvm-readelf -Wl` comprueba
  además que el final de cada segmento GNU_RELRO sea múltiplo de 16 KB o que
  ocupe su propio LOAD completo sin cola escribible en la página protegida
  (caso permitido también por la guía Android y el linker Bionic).
  En arm64-v8a/x86_64 se exige
  al menos `2**14`; ARMv7 también se inventaría, sin atribuirle un dispositivo
  de 16 KB. Un fallo aborta y no modifica dependencias.
- El hash del APK se contrasta entre inspecciones. Código, assets, scripts,
  configuración, lockfile, contrato y commit se comparan antes y después de
  compilar: cualquier cambio exige regenerar.

Los controles siguen la [guía Android de páginas de 16 KB](https://developer.android.com/guide/practices/page-sizes).
La excepción RELRO de LOAD completo se contrasta con
[`_extend_gnu_relro_prot_end` de Bionic](https://android.googlesource.com/platform/bionic/+/refs/heads/main/linker/linker_phdr.cpp).
No sustituyen la ejecución nativa en la matriz de dispositivos de T07/T09.

## Salida y trazabilidad

Solo tras pasar todos los controles se copian `autofinance.apk` y `manifest.json`
a `dist-private/android/candidate/<sha256>/`, ignorado por Git. El manifiesto
registra versión, paquete, SDK, ABIs, certificado SHA-1/SHA-256, tamaño/hash,
toolchain/JDK, comandos comprobados, commit, hash de las entradas y del OAuth
público, fecha, estado dirty e inventario nativo. Incluye archivos fuente nuevos
no ignorados y cambios concurrentes; sus contenidos y rutas privadas no se
copian al manifiesto. No se promete igualdad binaria entre máquinas.

Es un **candidato pendiente de T09**: `completeDelivery=false` y
`realDriveVerified=false` siempre. El gate de configuración T03 es necesario,
pero las declaraciones públicas no prueban Google real, preservación, teléfono
ARM64 ni Openbank. T09 debe usar un árbol confirmado, regenerar tras cualquier
cambio y acreditar el hash exacto final con sus evidencias propias. No existe
un interruptor para etiquetar completo un candidato sin esas pruebas.

Los APK previos identificados por hash no se renombran ni sobrescriben con otra
versión. Un fallo no convierte la salida bruta de `build/` ni candidatos de una
ejecución anterior en una entrega nueva validada.

## CI sin distribución

```powershell
node --test scripts/tests/android-delivery.test.mjs scripts/tests/android-apk-contract.test.mjs scripts/tests/google-oauth-android.test.mjs
# JAVA_HOME/ANDROID_HOME apuntan al entorno fijado.
node scripts/tests/build-android-delivery-fixture.mjs
```

La fixture crea una clave efímera fuera del repositorio, distinta de T02, y la
elimina en finally. Ejecuta el mismo pipeline con `APP_ENV=test`, sin inventar
IDs Google; el manifiesto declara `ci-ephemeral-fixture`. Se conserva localmente
en `dist-private/android/ci-fixture/<sha256>/`. No equivale a distribución ni
Drive operativo. Las pruebas ejercitan entradas y rechazos conocidos sin alta
Google externa; el contrato Gradle existente comprueba también los rechazos
de firma. El workflow build verifica esta fixture en Android y **no la sube**.
El upload ya existente sigue limitado al APK debug de prueba y al build Windows;
no se añade upload/release/hosting de producción ni material privado.
