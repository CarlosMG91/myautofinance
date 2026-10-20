# MA-TSK-244 · Guía de entrega privada Android

Guía operativa en español para generar, verificar, instalar y actualizar una
entrega privada. Contrato consultado el 20/10/2026: [APK privado](contrato-apk-privado.md)
(T01), [firma y custodia](firma-distribucion.md) (T02),
[generador](generador-apk.md) (T05) y recorrido de instalación T04 declarado
aprobado en MA-TSK-240. La nota local [revisión del recorrido](revision-recorrido-v1.md)
conserva una instantánea anterior que todavía dice pendiente; no sustituye el
estado actual del ticket. No se afirma aceptación final de EP-029.

## Estado y condiciones previas

La entrega es un único APK universal `release`, `APP_ENV=production`, paquete
invariable `com.carlosmg91.myautofinance`. El versionName y versionCode salen
de `pubspec.yaml` (`0.1.0+1` en el contrato consultado); toda entrega nueva debe
usar un versionCode mayor que cualquier APK ya distribuido. La base actual no
es una versión production acreditada.

Al redactar esta guía, el archivo versionado
`config/google-oauth.public.json` sigue en `blocked_external`: proyecto nulo,
Drive API desactivada, sin tester ni cliente Android y sin `serverClientId`.
Por tanto T03 sigue sin acreditar Google real y el generador debe rechazar una
entrega completa. **No hay un APK completo disponible para instalar siguiendo
esta guía todavía.** La prueba técnica T02 y los APK fixture de CI no son
entregas para el teléfono. T09 debe acreditar autorización Drive real y
verificación del hash exacto del candidato; no sustituirlo por proveedor falso.

## Preparar y generar el APK

Use un PC con Windows, PowerShell, acceso al repositorio y el toolchain fijado:
Flutter 3.47.0 / Dart 3.13.0, JDK 17, Android Platform/Build-Tools 36 y NDK
28.2.13676358. No necesita instalar SDK en el teléfono. Antes de cada build:

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
```

No use `flutter upgrade`, cambie `pubspec.lock` ni pase overrides de versión.
Con T03 habilitado y validado, y tras comprobar la configuración pública
Android, genere con:

```powershell
# $sdk y $jdk son las rutas locales al Android SDK y JDK 17 fijados.
./scripts/build-private-android-delivery.ps1 -Jdk $jdk -AndroidSdk $sdk
```

El script solo genera release universal production con la firma T02 estable y
`GOOGLE_ANDROID_SERVER_CLIENT_ID` público procedente de T03. Rechaza OAuth
incompleto antes de compilar/leer la clave. No escriba IDs secretos, passwords
ni credenciales en argumentos, dart-defines, Git o chat. El destino candidato
es `dist-private/android/candidate/<hash>/`; está ignorado por Git y se entrega
por un canal local privado elegido expresamente. No subir APK production, claves
ni datos a Releases, artifacts públicos, tiendas o hosting; no hay AAB ni
autoactualizador.

Un resultado existente en `build/`, la firma técnica T02 o una fixture no
eluden esas condiciones. Regenerar si cambian código, configuración pública,
lockfile o recursos. El manifiesto que acompaña al candidato debe identificar
el APK por SHA-256 y registrar paquete, versión, SDK, ABI, firma, toolchain y
gates; no contiene rutas privadas ni secretos.

## Verificar el archivo exacto

Mantenga el APK recibido en una carpeta privada. Contraste el hash publicado
por el manifiesto con el archivo local y use las herramientas oficiales
incluidas en el SDK fijado:

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath $apk
node scripts/check-android-apk-contract.mjs --apk $apk --sdk $sdk --jdk $jdk `
  --expected-certificate d6e624f1402fcc0df84cda5373a0b2a89321bd62cb2340a8d69a4a3e663b1951
```

La huella anterior es SHA-256 del **certificado** T02, no del APK. La salida de
`Get-FileHash` es SHA-256 del archivo y debe coincidir carácter por carácter
con el manifiesto del mismo APK. T02 también fija SHA-1
`6a1557043d8b3f9fce356a2532aae09f81cd93f3` para registrar el cliente Android
Google. No confunda las tres huellas. El inspector técnico T01 siempre produce
`completeDelivery=false`; no demuestra por sí mismo `APP_ENV`, OAuth, T06/T07,
Openbank ni teléfono real. Para una actualización, compare además el APK
anterior como `--previous-apk` y anote el API y ABI reales del dispositivo.
No instale si firma, paquete, hash, integridad, universalidad o versionCode no
coinciden con el manifiesto esperado.

T09 debe enlazar explícitamente su prueba de Google real, Openbank y dispositivo
ARM64 al hash SHA-256 del artefacto final. Las pruebas de proveedores falsos,
emulador x86_64, build correcto o metadatos del mockup no son sustitutos.

## Requisitos Android y flujo oficial de instalación

Contrato binario: mínimo Android 7.0/API 24; compile/target API 36. ABIs
requeridas `arm64-v8a` y `x86_64`; `armeabi-v7a` también está permitida si
figura en el APK comprobado. El APK universal no significa que todo dispositivo
sea compatible: verifique API, ABI, almacenamiento libre, integridad y que el
dispositivo permita instalar desde la fuente elegida. Drive usa Google Play
Services con la configuración Android real; si falta o está desactualizado,
puede fallar la conexión Google aunque las finanzas locales sigan funcionando
offline. La versión mínima funcional concreta de Play Services depende de las
dependencias empaquetadas y debe quedar acreditada por T03/T09; no inferirla de
`minSdk`.

En España, a 20/10/2026, la FAQ oficial de Android indica que la fase iniciada
el 30/09/2026 aplica a tiendas participantes en regiones seleccionadas y que
la instalación directa (sideload) no está sujeta a esa fase; recomienda
prepararse para la expansión global de 2027. Vuelva a revisar las fuentes en
cada entrega porque las reglas pueden cambiar. Compatibilidad del dispositivo,
política del fabricante, operador o versión de Android puede añadir condiciones.

1. Obtenga el APK y manifiesto por el canal privado acordado. No acepte enlaces
   reenviados sin validar hash y certificado por una vía confiable.
2. En el teléfono, abra el archivo con el selector/gestor de archivos del
   sistema Android y el instalador oficial. Si Android lo pide, permita a esa
   fuente concreta instalar esta aplicación en Ajustes; vuelva al instalador y
   confirme. Android 8/API 26+ configura la fuente individual; Android 7/API
   24–25 usa el control del sistema de fuentes desconocidas. Los nombres y pasos
   cambian por fabricante. Si el instalador no ofrece una ruta compatible,
   deténgase y conserve la instalación actual.
3. Revise el nombre Autofinance y los avisos de Android. Cancele si los datos
   del paquete/version no son los esperados. Tras instalar, abra Inicio y
   compruebe sus datos; no hay instalación silenciosa ni se requiere ADB.

No desactive Play Protect/protecciones, no habilite root ni permisos amplios de
almacenamiento y no conceda acceso a carpetas salvo cuando una función lo pida
mediante selector oficial. No se promete que todos los fabricantes ofrezcan
idénticos textos, controles o flujo.

Fuentes oficiales consultadas el 20/10/2026:
[distribución alternativa Android](https://developer.android.com/distribute/marketing-tools/alternative-distribution),
[FAQ Android Developer Verification](https://developer.android.com/developer-verification/guides/faq),
[comprobar/actualizar Android](https://support.google.com/android/answer/7680439) y
[servicios de Google Play](https://support.google.com/googleplay/answer/9037938).

## Actualizar conservando datos

Una actualización compatible se instala sobre Autofinance existente y exige,
antes de abrir el instalador, **el mismo `applicationId`, el mismo certificado
SHA-256 y un `versionCode` estrictamente mayor**. Compare el paquete/certificado
del APK realmente instalado con la evidencia de origen y compare el nuevo
candidato con su manifiesto. Con igual identidad Android actualiza la app sin
desinstalar; T07/T09 deben haber probado con APK production N→N+1 que conserva
SQLite, WAL/diarios, copias locales y catálogo, restauraciones pendientes,
estado `drive-sync` y el registro cifrado/sesión Keystore. Abra la app y
contraste la información y estado de sincronización antes de continuar.

No interprete una copia local dentro del espacio privado Android como respaldo
externo: al desinstalar o borrar datos se pierden base, copias locales,
catálogos, diarios, estado de instalación/Drive, sesión de Google y soporte
Keystore privado. Una copia Drive manual confirmada permanece en la cuenta,
pero recuperarla requiere autorización y validación expresa. No se restaura
automáticamente el secreto/sesión de otro dispositivo; la sesión puede requerir
reconexión si caduca, se revoca o Google la invalida. La política Android de
backup automático excluye finanzas, copias y secretos; no promete control
absoluto frente a todos los mecanismos OEM.

### Primera transición desde una versión debug

La firma debug suele ser distinta de la estable T02 y Android rechazará la
actualización directa. **No desinstale, no borre datos, no use downgrade ni
intente forzar la instalación.** Antes de cambiar nada, identifique el paquete,
certificado y versionCode de la app instalada; si no se pueden comprobar,
considérela instalación con datos. Exija una copia independiente de la app,
accesible después, validada y una recuperación completa ensayada con una
instalación nueva de la app destino firmada con T02. Use Drive EP-007 si está
configurado realmente en origen y destino; use exportación EP-027 solo si está
entregada y su recuperación fue probada. Compruebe contenido financiero,
esquema y conteos antes de tocar el teléfono original.

Si no existe esa copia viable, falta la clave/firma necesaria, Drive no está
configurado, o la recuperación con la versión destino no se probó, **detenga
la transición y conserve intacta la instalación debug**. No hay rescate
prometido por `adb`, `run-as` o root de una app release. Pida que se resuelva y
pruebe una vía de recuperación antes de volver a intentar. Desinstalar o
«borrar datos» nunca es el remedio automático de una incompatibilidad.

## Custodia y recuperación de la firma T02

La identidad debe permanecer estable durante toda la vida de las instalaciones.
El material T02 vive fuera del repositorio, con respaldo cifrado y una llave de
recuperación separada; no versionar ni copiar keystore, passwords, tokens o
archivos DPAPI en el APK, Git, CI, chat o logs. Conserve respaldo y llave en
soportes privados separados. La mera copia de un archivo no prueba que la
clave sea recuperable: ejecute el procedimiento T02 en destino privado nuevo,
verifique que puede firmar y confirme la misma huella T02 antes de usarla.

```powershell
# $jdk: JDK 17 fijado. No incluya secretos en la línea de comandos.
./scripts/manage-android-signing.ps1 -Action Check -Jdk $jdk
```

Si se recupera tras perder DPAPI/equipo, use `Recover` solo con respaldo cifrado
y llave existentes, en carpeta privada nueva, y después `Check` según
[instrucciones T02](firma-distribucion.md). Nunca ejecute `Create` para reparar
una clave perdida: produciría otra identidad y rompería las actualizaciones.
No envíe el material ni passwords por chat. Si faltan respaldo o llave, pare;
no es posible afirmar que las instalaciones actuales sean actualizables.

## Alcance de verificación

La guía describe el contrato y procedimiento, no acredita que se haya instalado
un APK completo en el teléfono. Registro del artefacto, Google real,
preservación, 16 KB, ejecución en teléfono ARM64 y recorrido final corresponden
a T09 y MA-TSK-245. No compilar, instalar ni publicar una build incompleta para
simular esos criterios.
