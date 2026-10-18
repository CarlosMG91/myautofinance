# MA-TSK-239 · OAuth Android de distribución

**Estado: bloqueo externo; ticket sin completar.** La identidad de T02 está
comprobada, pero faltan alta Google verificable y autorización real. No se
declara Drive operativo ni se habilita un APK completo con valores ficticios.

## Identidad pública comprobada

El [inventario público](../../packaging/android/oauth-distribution.public.json)
se contrasta con el [PEM de T02](../../packaging/android/distribution-certificate.pem)
y el APK técnico local. No contiene clave privada, alias, cuenta ni tokens.

| Dato | Valor |
| --- | --- |
| Paquete | `com.carlosmg91.myautofinance` |
| SHA-1 del certificado, para cliente Android | `6A:15:57:04:3D:8B:3F:9F:CE:35:6A:25:32:AA:E0:9F:81:CD:93:F3` |
| SHA-256 del certificado | `D6:E6:24:F1:40:2F:CC:0D:F8:4C:DA:53:73:A0:B2:A8:93:21:BD:62:CB:23:40:A8:D6:9A:4A:3E:66:3B:19:51` |
| SHA-256 del archivo APK técnico T02 | `72bd6242ceddf0962ea9f3034b279a699a1a4983cd30bdf8952968f7173a3bc0` |

El hash del APK cambia al compilar otra versión; el certificado debe mantenerse.
La [verificación T02](verificacion-firma.md) describe el origen del APK técnico,
incluido el árbol de trabajo con cambios concurrentes. No es una entrega final.

## Alta pendiente del propietario

Reutilizar el proyecto **Autofinance**, común a las plataformas, si ya existe.
No tomar un proyecto MyFinance. En [Google Cloud Console](https://console.cloud.google.com/):

1. Comprobar ID y número del proyecto y permisos para administrar API/OAuth.
   Habilitar exclusivamente la API necesaria, `drive.googleapis.com`.
2. En Google Auth platform, revisar Branding con nombre **Autofinance**.
   El propietario aporta los contactos en la consola; no se versionan correos.
   Audience: **External / Testing**, con la cuenta tester autorizada.
3. En Data Access declarar solo `https://www.googleapis.com/auth/drive.file`.
   No añadir permisos de perfil, identidad, Drive general ni appData.
4. Crear/revisar el cliente **Android** para el paquete y SHA-1 exactos de
   la tabla. Guardar únicamente su Client ID público.
5. Crear/revisar el cliente **Web application** del mismo proyecto para
   `serverClientId`. La integración nativa recibe su ID público: no necesita
   backend, servicio, clave API, secreto Web, redirección ni acceso offline.
6. Registrar en `config/google-oauth.public.json` los datos públicos reales:
   `project.id/number`, `drive.apiEnabled`, `consent.testUserAdded`,
   `android.serverClientId` y un cliente Android con `clientId`, ambas huellas
   y `builds: [{source: "distribution", apkSha256: ...}]` usando el hash T02.
   No copiar el JSON descargado de credenciales: puede contener secretos.
7. Mantener `status: "blocked_external"` si Windows sigue pendiente. Solo
   declarar el estado global `configured` cuando ambas plataformas y el alta
   común estén completas. Android puede superar su control estricto sin Windows.

El agente no acepta términos, inventa contactos ni concede permisos ajenos.
Si se requiere inicio de sesión, aceptación de condiciones o consentimiento,
el propietario debe intervenir. Para continuar basta aportar los IDs públicos
y acreditar los ajustes; no compartir contraseñas, tokens o material de firma.

El cliente Web es requerido por la [configuración oficial de google_sign_in_android](https://pub.dev/packages/google_sign_in_android)
cuando no se usa `google-services.json`. La autorización conserva el adaptador
EP-005, que comprueba el scope efectivo y obtiene `permissionId` desde Drive.
No se altera el SDK ni se amplían scopes para resolver errores. Referencias:
[credenciales Google](https://developers.google.com/workspace/guides/create-credentials),
[permiso por archivo](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
y [autorización Android](https://developer.android.com/identity/authorization).

## Controles locales y contrato para T05/T09

```powershell
# Esquema global: conserva exactamente el contrato anterior.
node scripts/check-google-oauth.mjs
node scripts/check-google-oauth.mjs --require-configured
# Android estricto: salida 1 hasta completar el alta Android real.
node scripts/check-google-oauth-android.mjs
# APK candidato real: apksigner y aapt2, sin instalar ni modificar datos.
node scripts/check-google-oauth-android.mjs --apk $apk --sdk $sdk --jdk $jdk
```

El control Android conserva el comprobador global y valida el proyecto común,
API, tester, scope único, paquete y clientes públicos. Exige el cliente de
distribución con **ambas huellas** de T02 y la evidencia del APK técnico. No
autoriza claves CI genéricas. El PEM independiente evita aceptar como identidad
esperada el certificado elegido por un APK candidato. Con `--apk` rechaza
debug, splits, ABI/SDK incompatibles y cualquier otro certificado. Una nueva
versión del mismo certificado puede tener un hash de archivo diferente.

T05 debe importar `loadAndroidOAuthConfiguration()` de
`scripts/check-google-oauth-android.mjs`, abortar si lanza error y consumir
`configuration.serverClientId` como `GOOGLE_ANDROID_SERVER_CLIENT_ID` público
en su build `APP_ENV=production`. No pasar secretos a dart-defines. Después
de compilar, ejecutar el control con **el APK producido** y los SDK/JDK fijados;
T09 debe repetirlo sobre el archivo final. El generador pertenece a T05 y no
se implementa de nuevo aquí. `createDriveUi` ya consume ese dart-define y
compone los adaptadores reales de EP-005/007.

La salida JSON solo acredita coherencia local declarada y, si se pide,
inspección de firma. Siempre lleva `completeDelivery=false` y
`realDriveVerified=false`: ni una salida 0 ni un ID con formato correcto
demuestran que Google haya aplicado el alta o autorizado la app.

## Prueba Google real pendiente

Usar Android con Google Play Services, cuenta tester y el APK exacto cuya
firma se registró. No atribuir una prueba debug a la firma de distribución.
T09 debe recoger hash del APK final, ambas huellas, versión, fecha, dispositivo
y versión Play Services; no publicar cuentas, permissionId, IDs de carpeta,
huellas de carpeta personales, tokens, capturas de cuentas ni logs OAuth.

En una instalación dedicada, con datos sintéticos y acciones manuales:

1. Autorizar mediante el selector/consentimiento Google real. Acreditar scope
   efectivo exactamente `drive.file` y `permissionId` estable, sin usar correo
   como identidad. Cancelar no cuenta como autorización.
2. Localizar/reutilizar la carpeta Autofinance con los adaptadores existentes;
   crearla solo por acción expresa. No elevar permisos ante carpetas homónimas
   inaccesibles ni crear una copia vacía.
3. Restaurar sesión local y renovar; verificar que conservan permissionId y
   carpeta. Cerrar/reabrir y renovar de nuevo; si se requiere interacción,
   reconectar expresamente. La caducidad/revocación debe conservar los metadatos
   para reconectar, sin bucles ni transferencias en segundo plano.
4. Comprobar cancelación, denegación y configuración de firma incorrecta con
   diagnóstico controlado. Credential Manager puede devolver `canceled` ante
   errores de configuración; no convertirlo en evidencia de login.

Los recorridos existentes `integration_test/android_drive_access_test.dart`
y `integration_test/drive_metadata_access_test.dart` ayudan a verificar estos
adaptadores en una instalación **dedicada**; limpian su sesión y no prueban
preservación de producción. El runner suele generar un APK debug: inspeccionar
su certificado exacto antes de usarlo y registrar esa identidad solo si el
propietario autoriza esa prueba específica. No ejecutarlos sobre datos/sesión
personales ni sustituir con ellos la prueba del APK production final.

No se ha detectado aquí una instalación Autofinance existente. Si aparece una
debug con datos, detener cualquier transición a otra firma hasta verificar
copia externa y recuperación con consentimiento. No desinstalar, borrar datos,
forzar instalación o dar por recuperada una clave perdida. Esta preparación no
registra certificados debug/CI ni implementa otro lector o motor de copias.
