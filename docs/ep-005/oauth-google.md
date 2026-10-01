# MA-TSK-042 · Proyecto Google y OAuth mínimo

## Estado y alcance

La preparación local está entregada. El alta real está **bloqueada por acceso
externo**: esta sesión no dispone de Google Cloud autenticado, navegador
conectado ni `gcloud`. No hay un ID de proyecto, cliente o certificado real
acreditado. El [registro de verificación](verificacion-oauth.md) distingue las
comprobaciones locales de las pendientes del propietario.

Este ticket configura el acceso futuro; no implementa autorización en ejecución,
almacenamiento de sesión, pantallas, operaciones de carpeta, transferencias ni
lectura de SQLite. Usa la app de MA-TSK-023 y el módulo `synchronization` de
MA-TSK-024. Las siguientes tareas de EP-005 consumirán esta configuración y la
épica de sincronización combinará el acceso Drive con la persistencia EP-004.

## Contrato de permisos e identidad

El único scope solicitado y declarado en consentimiento será
`https://www.googleapis.com/auth/drive.file`. Es un permiso por archivo para
recursos creados por la app o concedidos expresamente a ella. No autoriza a
enumerar toda Mi unidad. Véase [scopes de Drive](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).

La futura integración podrá identificar la unidad autorizada mediante
`GET https://www.googleapis.com/drive/v3/about?fields=user(permissionId,emailAddress)`:
`permissionId` identifica al usuario de Drive; el correo, si está disponible,
sirve para indicar la cuenta vinculada. La API admite `drive.file` y permite
pedir solo estos campos. Por ello no se añaden `openid`, `email`, `profile` ni
`userinfo.*`. Esta es una identidad de Drive para vincular una sesión local,
no un servicio de autenticación de usuarios ni un identificador OIDC `sub`.
Referencias: [about.get](https://developers.google.com/workspace/drive/api/reference/rest/v3/about/get)
y [User](https://developers.google.com/workspace/drive/api/reference/rest/v3/User).

No usar cuentas de servicio, claves API como sustituto de OAuth, delegación,
`drive`, `drive.readonly`, permisos generales de metadatos, `drive.appdata` ni
`drive.appfolder`. El inventario y su verificador rechazan cualquier scope
adicional. La lista en Cloud no limita por sí sola todas las solicitudes:
la implementación futura también deberá solicitar exactamente esta lista y
comprobar el permiso concedido; nunca ampliar permisos como solución a un 403.

## Alta reproducible por el propietario

1. Entrar en [Google Cloud Console](https://console.cloud.google.com/) con la
   cuenta propietaria. Comprobar si ya existe el proyecto Autofinance y
   reutilizarlo; si no existe, crear uno con nombre visible **Autofinance** y
   un ID único elegido por el propietario. No reutilizar un proyecto MyFinance.
   Registrar su ID y número, públicos, en `config/google-oauth.public.json`.
   Los clientes de ambas plataformas deben vivir en ese mismo proyecto.
2. En **APIs y servicios → Biblioteca**, buscar **Google Drive API**, habilitar
   `drive.googleapis.com` y comprobar que aparece en las API habilitadas.
   Registrar `drive.apiEnabled: true` únicamente después de comprobarlo.
   Si el propietario ya usa Cloud SDK, la habilitación equivalente es
   `gcloud services enable drive.googleapis.com --project=<ID_DEL_PROYECTO>`.
   No requiere habilitar Firebase ni servicios de cuentas de servicio.
3. En **Google Auth platform → Branding**, configurar nombre **Autofinance**,
   correo de asistencia y contacto del desarrollador elegidos por el propietario.
   Esos correos quedan en la consola, fuera del repositorio. Completar cualquier
   requisito que Google muestre con datos reales; no inventar dominios,
   políticas publicadas o verificación de marca. No se necesita configurar
   orígenes JavaScript ni un callback público para el cliente de escritorio.
4. En **Audience**, elegir **External** para la cuenta personal y dejar el
   estado **Testing**. Añadir como usuario de prueba únicamente la cuenta que
   probará Autofinance. Registrar el booleano `testUserAdded: true` al terminar;
   no registrar la dirección de esa cuenta. No publicar la aplicación en
   producción como parte de este ticket.
5. En **Data Access → Add or remove scopes**, seleccionar exclusivamente
   `https://www.googleapis.com/auth/drive.file`. Guardar y comprobar la lista
   completa, retirando permisos generales o de perfil que no se necesitan.
6. Crear los clientes Android y Windows como se detalla abajo, revisar que el
   selector de proyecto no haya cambiado y completar el inventario público.

El propietario debe resolver acceso al proyecto, permisos para habilitar API y
gestionar OAuth, restricciones de organización, datos de contacto y cualquier
aceptación de condiciones que Google solicite. No se le pide compartir su
contraseña, claves privadas o tokens con agentes ni con el repositorio.
Referencia: [creación de credenciales](https://developers.google.com/workspace/guides/create-credentials).

## Android: paquete y firma del APK efectivo

El paquete vigente es **`com.carlosmg91.myautofinance`**, tomado de
`android/app/build.gradle.kts` (`applicationId`). No cambiarlo incidentalmente;
`namespace` o la ubicación de `MainActivity.kt` no sustituyen el paquete final.
Si se añaden flavors o sufijos, revisar y registrar cada paquete efectivo.

Antes de registrar una firma, compilar o descargar el **APK exacto que se vaya
a instalar**. Preparar las herramientas de [EP-003](../ep-003/entorno.md), con
JDK 17 y SDK Android fijados, e inicializar Flutter:

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
# Con Build-Tools 36.0.0 y Command-line Tools del SDK en PATH:
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-debug.apk
apkanalyzer manifest application-id build/app/outputs/flutter-apk/app-debug.apk
Get-FileHash -Algorithm SHA256 build/app/outputs/flutter-apk/app-debug.apk
```

Exigir que la firma sea válida y que el paquete leído del APK coincida. Tomar
las huellas **del certificado del firmante**, SHA-1 y SHA-256, del resultado de
`apksigner`; normalizarlas a mayúsculas y pares hexadecimales separados por `:`.
El hash SHA-256 del archivo APK es otro dato: registrarlo en minúsculas sin
separadores como evidencia del artefacto. No confundirlo con la huella del
certificado. Si aparecen varios firmantes o una rotación, revisar la firma con
el propietario antes de registrar clientes.

Como comprobación local adicional, si existe el almacén debug:

```powershell
keytool -list -v -keystore "$env:USERPROFILE/.android/debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

La contraseña `android` corresponde al almacén debug estándar; nunca pasar una
contraseña de firma privada en comandos versionados. El informe de Gradle
`./gradlew.bat :app:signingReport` desde `android/` también ayuda a inspeccionar
variantes. Estos informes pueden mostrar rutas personales: copiar al inventario
solo las huellas públicas comprobadas, sin guardar logs crudos.

En **Google Auth platform → Clients → Create client**, seleccionar **Android**,
nombre **Autofinance Android · <origen del build>**, paquete vigente y SHA-1 del
certificado real. Guardar el Client ID público. Crear un cliente por certificado
distinto y reutilizarlo para los APK que tengan la misma firma. En el inventario,
cada elemento de `android.clients` tiene exactamente:

| Campo | Contenido público |
|---|---|
| `clientId` | ID real de ese cliente Android |
| `certificateSha1` | 20 bytes hexadecimales con `:`; huella usada en Cloud |
| `certificateSha256` | 32 bytes hexadecimales con `:`; evidencia de firma |
| `builds` | Lista de objetos con `source` y `apkSha256` del APK inspeccionado |

`source` admite `local-debug`, `local-release-debug-key`, `ci-debug` y
`distribution`. El build release actual también usa la clave debug: no es firma
de distribución. Las claves debug de una máquina y de los runners CI suelen
ser distintas; una nueva ejecución efímera de CI puede producir otra firma.
Para probar un APK de Actions, descargar ese artefacto, verificarlo y registrar
su certificado antes de instalarlo. Un cliente de la firma local no acredita
ese APK de CI. No subir ni compartir el keystore para hacer coincidir firmas.
La firma de producción o Play, si se incorpora, requerirá sus clientes propios.

MA-TSK-044 usa el paquete oficial `google_sign_in` 7.2.0 y su implementación
Android 7.2.17: Credential Manager selecciona la cuenta y `AuthorizationClient`
solicita `drive.file`. Sin `google-services.json`, el paquete requiere además
un cliente **Web application** del mismo proyecto, cuyo ID público se registra
en `android.serverClientId`. No configurar secreto, backend, orígenes JavaScript
ni redirecciones para esta integración nativa. Pasar ese ID a la composición
Android; el cliente Android registrado con paquete/firma sigue siendo necesario.
No usar el cliente Windows ni redirecciones loopback/custom scheme en Android.
No pedir acceso offline ni código de servidor. El SDK de selección realiza su
autenticación Google y entrega un ID token; Autofinance no lo consume, guarda
ni utiliza como identidad Drive. La autorización Drive solicita exactamente
`drive.file`; la integración comprueba también el scope del access token y
rechaza cualquier concesión adicional. No se añaden scopes OIDC a esa petición.
Véase [configuración oficial del paquete Android](https://pub.dev/packages/google_sign_in_android)
y [implementación y prueba pendiente](autorizacion-android.md).
Referencia: [autorización en Android](https://developer.android.com/identity/authorization).

## Windows: cliente instalado de escritorio

En el mismo proyecto, crear un cliente de tipo **Desktop app**, nombre
**Autofinance Windows**. Registrar su Client ID en `windows.clientId` y
conservar `windows.type: desktop`. No crear un cliente Web como sustituto.

La futura implementación abrirá el navegador del sistema y usará código de
autorización con PKCE **S256**, `state` aleatorio comprobado y callback loopback
`http://127.0.0.1:<puerto efímero>`. El listener se limita a la interfaz local y
se cierra al terminar o cancelar. No usar WebView ni copiar códigos OOB.
El cliente desktop admite loopback sin registrar cada puerto como cliente Web.

El Client ID es público. El JSON descargable de Cloud puede contener un
`client_secret`: no copiar ese JSON al inventario, assets o dart-defines ni
confirmarlo. Google trata las aplicaciones instaladas como clientes públicos
que no pueden mantener un secreto; PKCE protege el intercambio. Si la librería
elegida requiere algún material adicional del cliente desktop, evaluarlo en el
ticket de implementación y mantenerlo separado, sin versionarlo ni registrarlo
en logs. Referencia: [OAuth para aplicaciones instaladas](https://developers.google.com/identity/protocols/oauth2/native-app).

## Inventario, validación y protección de secretos

`config/google-oauth.public.json` es un **inventario de preparación**, no un
asset ni una configuración consumida por el arranque Flutter. `null` y la lista
vacía significan datos pendientes, no credenciales utilizables. `blocked_external`
documenta el estado actual. Cambiar a `configured` únicamente tras comprobar el
proyecto común, Drive API, consentimiento, usuario de prueba y ambos clientes.
Esto declara el alta en Cloud; no declara un login en dispositivos exitoso.

```powershell
# Node.js 20 o posterior; no instala paquetes ni accede a Google.
node scripts/check-google-oauth.mjs
node --test scripts/tests/google-oauth-config.test.mjs
# Debe fallar mientras el alta siga bloqueada:
node scripts/check-google-oauth.mjs --require-configured
```

El verificador exige esquema cerrado, scope exacto, paquete coincidente con
Gradle, formatos de IDs/huellas y evidencia de APK. Comprueba la coherencia del
prefijo del Client ID con el número de proyecto, pero **no consulta Google** ni
demuestra que el certificado corresponda al APK declarado. Eso requiere las
comprobaciones del propietario y de los siguientes tickets.

Datos sensibles quedan fuera del repositorio. Si hay que descargar material de
Cloud, usar una carpeta privada fuera del checkout o `config/private/`, ignorada
por Git. Se ignoran también patrones habituales de exportaciones OAuth y tokens.
`.gitignore` es prevención, no un detector universal: revisar el diff antes de
confirmar, no usar `git add -f` y no confiar en el verificador para sanear otros
archivos. No versionar correos personales, tokens, sesiones, keystores, JSON
crudos de Cloud, cabeceras Authorization, códigos ni URLs de callback completas.
La sesión segura por instalación y su revocación corresponden a tickets futuros;
sus tokens tampoco vivirán en SQLite, copias Drive o configuración pública.

## Modo de prueba y comprobaciones posteriores

**Testing** permite autorizar únicamente a usuarios añadidos como testers.
Los consentimientos caducan a los siete días, incluidos refresh tokens cuando
se emiten; `drive.file` no entra en la excepción de scopes de identidad.
La futura sesión debe gestionar reautorización explícita, revocación,
cancelación y `invalid_grant`, sin bucles en segundo plano. Véase
[audiencia y caducidad](https://support.google.com/cloud/answer/15549945?hl=en).

Cuando existan los adaptadores de los siguientes tickets, comprobar en Windows
y en cada APK con firma registrada: cuenta tester seleccionada, permisos
efectivamente concedidos solo `drive.file`, consulta de identidad mínima,
cancelación/revocación y acceso a los mismos recursos de la app entre
plataformas. Guardar resultados sin correos, tokens o IDs de archivos personales.
Una firma no registrada debe fallar de forma controlada; no ampliar permisos.

El alta OAuth no crea la carpeta. La futura carpeta **Autofinance** será normal
y visible en Mi unidad; se creará solo tras una acción expresa. Si aún no hay
copia, el flujo informará `sin_copia` y esperará la primera subida válida, sin
archivo vacío. Una carpeta homónima creada manualmente puede no estar concedida
a `drive.file`: su nombre o ID no otorgan acceso. No elevar el scope para
encontrarla. La localización real, ambigüedad y metadatos pertenecen a EP-005;
subida, descarga, reemplazo y divergencias a la épica de sincronización.
