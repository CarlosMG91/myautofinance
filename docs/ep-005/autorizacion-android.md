# MA-TSK-044 · Autorización nativa Android

## Implementación y composición

`lib/app/drive_access_factory.dart` compone `DriveAccessSession` y el proveedor
Android, por constructor. Recibe el `serverClientId` Web **público** y un cliente
HTTP cuyo ciclo de vida controla el llamante. Reutilizar una sola instancia por
instalación/flujo; el SDK Google es singleton. La fábrica rechaza otras
plataformas. No se conecta al arranque ni a las rutas técnicas.

Los adaptadores permanecen en `synchronization/data`; la entrada pública sigue
exportando solo dominio. No se modifica SQLite ni el grafo de módulos. Se
añaden `google_sign_in` 7.2.0, Android 7.2.17, `http` 1.6.0 y la interfaz oficial
3.1.0 como dependencia de pruebas, manteniendo el resto del lockfile y el SDK.

Una acción `requestAccess()` solicita selección nativa cuando corresponde,
consulta silenciosamente la concesión existente y abre consentimiento solo si
falta `drive.file`. La elección expresa usa `signOut()` local antes de
`authenticate()`; nunca `disconnect()` del SDK, que revocaría permisos.
La reconexión exige la cuenta persistida. Una selección distinta produce
`accountChangeRequired` y conserva el registro anterior. `changeAccount()`
borra primero sesión y carpeta según MA-TSK-043; cancelar deja desconectado.

El SDK no expone en su API Dart general los scopes efectivos ni la caducidad.
El proveedor consulta `https://oauth2.googleapis.com/tokeninfo` por HTTPS,
comprueba scope exacto y `expires_in`, y descuenta 60 segundos de margen. Después
consulta exclusivamente `about.get?fields=user(permissionId,emailAddress)`.
Solo `User.permissionId` identifica la cuenta. Ni correo ni OIDC `sub` sirven
como clave. Ninguna petición sigue redirecciones; cada respuesta tiene timeout
de 30 segundos. No se guardan ni registran URLs con tokens, cabeceras o cuerpos
OAuth, y las excepciones externas se sustituyen por códigos cerrados.

Referencias: [API oficial google_sign_in](https://pub.dev/packages/google_sign_in),
[about.get](https://developers.google.com/workspace/drive/api/reference/rest/v3/about/get)
y [autorización Android](https://developer.android.com/identity/authorization).

## Sesión local y renovación

Los access tokens se usan en memoria dentro del adaptador de datos. El SDK y
Google Play Services gestionan su autorización nativa; Autofinance no solicita
refresh tokens, códigos de servidor ni acceso offline. El ID token del selector
Google no se consume ni persiste. Los únicos scopes solicitados a la API de
autorización son `{drive.file}`; si Google devuelve un access token con scopes
ampliados, se rechaza, sin rebajar la comprobación para permitir el login.

`KeystoreDriveSessionStore` persiste únicamente metadatos: identidad, etiqueta
opcional, scopes, vigencia y carpeta. El canal Android `autofinance/drive_session`
usa AES-256-GCM, IV aleatorio generado por Keystore y datos autenticados de
versión. La clave permanece en Android Keystore. Un registro único versionado
vive en `Context.noBackupFilesDir`, excluido de backup/restauración automática;
`AtomicFile` confirma o revierte la escritura. El canal usa una cola de trabajo
serial para no bloquear la UI. No se añade este registro a copias SQLite/Drive.
No se borra ni regenera una sesión ilegible silenciosamente. Borrar es local,
idempotente y comprueba la ausencia de registro y restos atómicos.

Referencias: [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
y [AtomicFile](https://developer.android.com/reference/android/util/AtomicFile).

Restaurar lee solo ese registro, sin SDK ni red. Renovar ocurre exclusivamente
al pedir `renewAccess()`: descarta un token en caché si lo hay y usa
`authorizationForScopes`, con consentimiento deshabilitado. No usa
`attemptLightweightAuthentication`, porque su implementación Android puede
mostrar un selector. Tras reiniciar se puede intentar autorización silenciosa
sin cuenta en memoria; siempre se vuelve a verificar `permissionId`. Si no se
puede obtener autorización sin UI, si se revocó o si la cuenta no coincide,
se guarda vigencia caducada y se conserva identidad/carpeta para reconectar
expresamente. Un fallo de red conserva el registro anterior.

Desconectar olvida las referencias del SDK en el adaptador y borra el registro
local sin red; no elimina cuentas Google del dispositivo ni revoca concesiones
Google Play Services. Después solo una nueva acción expresa puede recuperarlas.
La instalación nueva comienza sin sesión aunque el sistema conserve su cuenta.

## Configuración y diagnóstico

Completar el alta de [MA-TSK-042](oauth-google.md): proyecto común, Drive API,
audiencia testing y cuenta tester. Registrar el cliente Android con paquete
`com.carlosmg91.myautofinance` y **SHA-1 del certificado del APK efectivo**, y
guardar SHA-256 y hash del artefacto en el inventario. Cada firma local/CI requiere
su cliente correspondiente; no compartir keystores para hacerlas coincidir.
Crear además un cliente Web del mismo proyecto y registrar su ID público en
`android.serverClientId`. El verificador exige formato, proyecto común, no
duplicación y su presencia cuando el inventario declara `configured`.
El inventario sigue siendo preparación pública y no se carga como asset.

`clientConfigurationError` es el nuevo diagnóstico cerrado para ausencia/formato
del ID y errores de configuración del cliente o proveedor nativo. Revisar
paquete, certificado del APK, cliente Web y Google Play Services. El SDK puede
devolver `canceled` tras seleccionar cuenta ante algunas firmas/paquetes erróneos;
**no puede distinguirlo de una cancelación real**. Se mantiene `cancelled` para
proteger la sesión y se revisa la configuración con los comandos públicos de
MA-TSK-042. No se propaga el texto privado del error para diagnosticarlos.
Referencia: [limitación oficial CredentialManager](https://pub.dev/packages/google_sign_in_android#troubleshooting).

## Prueba manual preparada, pendiente

Usar un Android con Google Play Services y una **instalación dedicada de prueba**:
el recorrido limpia su sesión local. No crea carpetas ni archivos, y no realiza
subida/descarga. No debe ejecutarse sobre una instalación personal en uso.

Compilar el APK con el SDK/JDK fijados y verificar paquete/firma con los comandos
de MA-TSK-042. El APK del runner de integración también debe inspeccionarse
(`build/app/outputs/apk/debug/app-debug.apk` cuando exista), pues ese es el que
se instala durante la prueba. Registrar en Cloud su certificado real antes del
consentimiento. Ninguna huella sintética acredita un build real.

```powershell
node scripts/check-google-oauth.mjs --require-configured
flutter test integration_test/android_drive_access_test.dart -d <ANDROID_ID> --no-pub --dart-define=APP_ENV=test --dart-define=MANUAL_DRIVE_TEST=true --dart-define=GOOGLE_ANDROID_SERVER_CLIENT_ID=<ID_WEB_PUBLICO> --dart-define=DRIVE_TEST_SCENARIO=authorize
```

El escenario `authorize` verifica autorización, identidad estable, scope exacto,
restauración local, renovación sin UI y reconexión. Repetir con `cancel`:
aceptar la primera conexión y cancelar el segundo selector; comprueba que la
identidad persistida se conserva. Repetir con `change`, eligiendo una segunda
cuenta tester en el cambio expreso, y comprobar que no se conserva carpeta.
Con un paquete/firma deliberadamente no registrado, ejecutar `configuration`:
debe fallar con diagnóstico cerrado y sin sesión. La prueba permite `cancelled`
por la limitación documentada del SDK, pero no cuenta esa salida como login.

Comprobar además denegación de consentimiento, pérdida de red y revocación desde
Google antes de renovar, cierre/reapertura, desconexión sin red y ausencia del
registro tras reinstalar. Guardar fecha, versión Android/Play Services, SHA del
commit y hash/firma **públicos** del APK y resultados; no correos, tokens,
permissionId reales, capturas de cuentas ni logs OAuth crudos.

## Evidencia de esta entrega

El 2026-10-01 se consultaron Epic Board por su API local, MA-EPIC-041,
MA-TSK-044 y sus dependencias completadas MA-TSK-042/043. El checkout estaba
limpio en `main`. No se modifica el estado del tablero desde el código.

El inventario continúa `blocked_external`, sin proyecto/clientes reales,
certificados verificados ni tester acreditado. `flutter doctor -v` y
`flutter devices` confirman que faltan Android SDK y dispositivo Android;
también falta Visual Studio C++. No se ha realizado la prueba manual, registrado
firmas en Cloud ni acreditado OAuth/Keystore en dispositivo. Esto impide dar
por cumplidos todos los criterios del ticket, aunque el código y las pruebas
sintéticas estén entregados. Los resultados finales locales se registran abajo.

- `flutter --version`, `check-toolchain.ps1` y resolución con
  `--enforce-lockfile`: correctos, Flutter 3.47.0/Dart 3.13.0. Solo se añaden
  las dependencias necesarias; ninguna versión existente se actualiza.
- `scripts/check-quality.ps1` completo: **61 archivos** con formato correcto,
  análisis sin incidencias, **159 pruebas Flutter aprobadas**, incluidas **50
  nuevas** del proveedor, canal seguro y SDK oficial. También pasan las cuatro
  variantes de arranque `APP_ENV`. La advertencia existente de instancias
  múltiples de Drift sigue sin producir fallos.
- `node --test scripts/tests/google-oauth-config.test.mjs`: **14 pruebas**
  aprobadas, incluyendo ausencia del cliente Web y coherencia del inventario.
- Verificador OAuth normal: contrato válido y aviso de bloqueo; con
  `--require-configured`: salida **1**, rechazo esperado. No acredita un alta.
- Builds Windows release y APK debug intentados con `APP_ENV=test` y `--no-pub`:
  fallan antes de compilar por Visual Studio ausente y Android SDK ausente.
  El JDK disponible es 25; el build Android exige preparar JDK 17 según EP-003.
- La prueba de integración manual no se ejecutó; el análisis comprueba su
  compilación Dart, pero no la ejecución nativa, firma, consentimiento, acceso
  real ni cifrado en Keystore. Falta evidencia para cerrar el ticket.
- `git diff --check`: correcto. Revisión de archivos propios, pruebas
  sintéticas y ausencia de credenciales personales.

La resolución inicial de paquetes necesitó acceso de red fuera del sandbox.
El entorno Windows también carecía de permisos de symlink: se crearon junctions
locales en el directorio efímero ignorado de Flutter para sus plugins existentes,
sin cambiar ajustes globales ni archivos versionados. El control de calidad
final resolvió el lockfile correctamente.
