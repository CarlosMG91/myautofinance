# MA-TSK-045 · OAuth instalado para Windows

## Implementación

`createWindowsDriveAccess` en `lib/app/drive_access_factory.dart` compone el
contrato de MA-TSK-043 con `WindowsDriveSessionProvider`, el receptor OAuth y
Credential Manager. Devuelve `WindowsDriveAccessHandle`: `access` expone las
acciones comunes y `cancelAuthorization()` cancela el consentimiento en curso.
El llamante conserva y cierra su cliente HTTP y reutiliza una única composición
por instalación. No hay autorización ni restauración en el arranque, pantallas
de producto, carpetas, transferencias, archivos vacíos ni acceso SQLite.

El cliente es **Desktop**, público. Solo se inyecta su `clientId`; no existe
parámetro de secreto. `crypto` 3.0.7 pasa de dependencia transitiva a directa
para SHA-256, sin cambiar su versión ni ninguna otra versión del lockfile.
Los adaptadores y las credenciales permanecen en `synchronization/data`;
la entrada pública sigue exportando únicamente dominio.

El canal nativo usa `ShellExecuteW` para abrir la URL HTTPS de Google en el
navegador predeterminado. No usa un navegador incrustado. Cada intento reserva
exclusivamente `127.0.0.1:0`, obtiene del sistema un puerto libre y envía esa
dirección exacta como `redirect_uri`. No usa puertos fijos, interfaces públicas
ni esquemas personalizados. Un conflicto de binding se informa como
`loopbackUnavailable`, sin abrir navegador.

Cada intento genera `state` y `code_verifier` independientes con 256 bits de
aleatoriedad segura. El desafío es SHA-256 y base64url sin padding, con
`code_challenge_method=S256`. El retorno debe ser GET a `/`, con Host exacto y
un único `state` coincidente. Un callback ajeno recibe 400 y no consume el
intento; duplicación de código, código/error simultáneos o respuesta incompleta
con state válido producen `invalidSession`. Google verifica la prueba PKCE al
canjear el código: se envían el verifier original y el mismo redirect, sin
secretos de cliente. Un rechazo `invalid_grant` se traduce a `credentialExpired`.

El receptor se cierra en `finally` tras éxito, denegación, error del navegador,
cancelación explícita o timeout de tres minutos. Se termina de responder antes
del cierre normal, se bloquea el replay durante ese intervalo y se fuerzan a
cerrar todos los sockets. El HTML/cuerpo no refleja parámetros ni cuentas;
la respuesta usa `no-store`, `no-referrer` y CSP sin recursos. Cerrar únicamente
la pestaña del navegador no notifica a la app: el consumidor puede cancelar
expresamente o esperar al timeout, informado como `authorizationTimeout`.
`access_denied` es `permissionDenied`, distinto de la cancelación local.

Referencia verificada:
[OAuth para aplicaciones instaladas de Google](https://developers.google.com/identity/protocols/oauth2/native-app).

## Sesión y acceso manual

Se solicita exactamente `drive.file`, con `access_type=offline`. Se pide
`consent` cuando falta una credencial renovable y `select_account` en la
selección expresa. Una segunda `requestAccess()` verifica la cuenta con el
access token vigente sin abrir el navegador; si ha caducado, usa el refresh
token. `renewAccess()` siempre renueva sin UI. No existe temporizador de
renovación ni actividad remota al restaurar metadatos.

El endpoint de tokens debe devolver Bearer, token no vacío, vigencia suficiente
y permiso exacto. Se descuenta un margen de 60 segundos desde el comienzo de la
petición. En renovación, la omisión de scope conserva la concesión anterior;
la omisión de refresh token conserva el anterior de la misma cuenta. Una
rotación se guarda junto con los nuevos metadatos. Antes de persistir se obtiene
`User.permissionId` mediante `about.get?fields=user(permissionId,emailAddress)`.
El correo es solo una etiqueta. Una cuenta distinta no reemplaza una sesión
existente; cambiarla requiere `changeAccount()` y borra previamente la carpeta.

Las peticiones HTTPS no siguen redirecciones y tienen timeout de 30 segundos.
Los tokens viajan en el cuerpo POST o cabecera Authorization, nunca en URLs
de peticiones Drive. No se imprimen respuestas, códigos, cabeceras, URLs OAuth
ni excepciones externas. Los errores usan el conjunto cerrado del dominio.

Una renovación revocada (`invalid_grant`/401), sin permiso o con cuenta distinta
elimina de forma duradera ambos tokens, guarda vigencia caducada y conserva
identidad/carpeta para una acción posterior de reautorización. No abre
consentimiento automáticamente. Un fallo de red conserva el registro anterior.
Cancelar o fallar un consentimiento conserva el registro previo. Desconectar
es un borrado local verificable, idempotente y sin revocación remota.

## Almacén Windows e instalación

El canal `autofinance/windows_drive` usa `CredReadW`, `CredWriteW` y `CredDeleteW`
del Administrador de credenciales de Windows. Un registro genérico contiene
ambos tokens y metadatos, en una sola escritura del sistema. Se vuelve a leer
para verificar la escritura y se comprueba la ausencia después de borrar.
Los errores de almacenamiento se notifican como `secureStorageFailure`; no
hay fallback a texto plano, SQLite, assets, copias o archivos de la aplicación.
Se respeta `CRED_MAX_CREDENTIAL_BLOB_SIZE`; un registro demasiado grande se
rechaza sin truncarlo ni repartirlo en entradas no atómicas.

La persistencia es `CRED_PERSIST_LOCAL_MACHINE`, nunca enterprise/roaming. El
registro del usuario guarda **solo un GUID**, sin cuentas ni credenciales, bajo
`Software\CarlosMG91\Autofinance\Installations\<hash-del-directorio-del-EXE>`.
Un mutex local serializa su creación entre procesos. El GUID identifica la
entrada segura. Dos directorios de instalación independientes usan entradas
distintas; copiar el EXE o el repositorio no copia la sesión. Actualizar en el
mismo directorio conserva la instalación. Un futuro desinstalador deberá
desconectar y retirar su marcador; eliminar únicamente los binarios y volver
a ese mismo directorio no constituye borrado de credenciales del sistema.
No se entrega un instalador en este ticket.

El sistema protege el almacén para el usuario Windows y la máquina; esta
protección no aísla frente a otros programas que ya se ejecuten como ese mismo
usuario. No se exportan credenciales a mecanismos de copia propios de la app.
Las copias manuales futuras solo podrán incluir la base, nunca este almacén.

Referencias:
[CREDENTIALW y persistencia](https://learn.microsoft.com/en-us/windows/win32/api/wincred/ns-wincred-credentialw)
y [CredWriteW](https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credwritew).

## Verificación local y pendiente

El 2026-10-01 se consultaron MA-EPIC-041, MA-TSK-045 y su dependencia completada
MA-TSK-043 en la API local de Epic Board. El checkout comenzó limpio en `main`.

- SDK fijado inicializado desde `.tools/flutter`: Flutter 3.47.0/Dart 3.13.0.
- `scripts/check-quality.ps1`: 68 archivos Dart con formato correcto, análisis
  sin incidencias, **213 pruebas** correctas y cuatro variantes de `APP_ENV`.
  Incluye **54 pruebas nuevas Windows**: receptor real con navegador falso,
  proveedor con HTTP sintético y contrato de canal con mensajero falso.
- Se prueban dos receptores simultáneos, puertos distintos, state ajeno,
  PKCE S256, callbacks ambiguos, cancelación, denegación, timeout, puerto ocupado,
  cierre/reutilización del puerto, caducidad, revocación, renovación silenciosa,
  reinicio del proveedor, rotación de tokens, cuenta/carpeta, fallos seguros y
  ausencia de mensajes privados en los errores.
- `node --test scripts/tests/google-oauth-config.test.mjs`: 14 pruebas correctas.
- `git diff --check`: correcto. Se mantiene la advertencia existente de Drift
  sobre múltiples instancias en sus pruebas; no afecta a esta implementación.
- Builds locales Windows release/APK debug intentados: bloqueados por ausencia
  de Visual Studio C++ y Android SDK, respectivamente.
- Integración local Credential Manager intentada: no llega a ejecutarse por
  falta de Visual Studio. El workflow de builds añade esa prueba sintética
  nativa en el runner Windows, sin solicitar OAuth ni usar datos personales.

El inventario sigue `blocked_external` y sin cliente Desktop real. Falta
verificar consentimiento y revocación reales, navegador predeterminado,
aislamiento entre instalaciones y almacenamiento nativo. Las pruebas sintéticas
no acreditan esos criterios. La entrega de código no permite declarar todavía
completa la aceptación real del ticket. La evidencia CI, cuando se obtenga,
se registra debajo sin confundirla con autorización Google.

## Recorrido preparado con instalación dedicada

Preparar Visual Studio y el cliente Desktop público de MA-TSK-042. Usar una
instalación de prueba: estas pruebas desconectan y borran su registro local.

```powershell
node scripts/check-google-oauth.mjs --require-configured
flutter test integration_test/windows_drive_access_test.dart -d windows --no-pub --dart-define=APP_ENV=test --dart-define=WINDOWS_CREDENTIAL_TEST=true
flutter test integration_test/windows_drive_access_test.dart -d windows --no-pub --dart-define=APP_ENV=test --dart-define=MANUAL_DRIVE_TEST=true --dart-define=GOOGLE_WINDOWS_CLIENT_ID=<ID_DESKTOP_PUBLICO> --dart-define=DRIVE_TEST_SCENARIO=authorize
```

`authorize` verifica acceso, una segunda composición/restauración, petición sin
consentimiento repetido y renovación. Ejecutar también `cancel` (cancelación
local cinco segundos después del inicio), `timeout` (dejar sin responder tres
minutos) y `configuration` (ID ausente/inválido). Cerrar/reabrir el ejecutable
para verificar restauración pasiva, revocar desde Google antes de una renovación
y comprobar `credentialExpired` sin navegador automático. Denegar en Google
debe producir `permissionDenied`. Repetir en dos carpetas de instalación y
comprobar independencia y borrado local. No trasladar el almacén ni el marcador
de instalación entre equipos. Registrar solo SHA del commit, versión Windows,
hash del artefacto y resultados; nunca cuentas, tokens ni capturas OAuth.
