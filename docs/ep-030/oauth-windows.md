# MA-TSK-249 · OAuth Windows para el ensayo PC ↔ Android

**Estado: bloqueado; no entrega todavía una sesión Google real.** Revisión del
2026-10-20, fuentes `c6f8f715912eb77a06fc0f4659e5cb64f5cc8ef0`, rama configurada
`ticket/ma-tsk-193`. Epic Board consultado por `GET /api/data` en localhost:4310:
tablero **My autofinance**, workspace coincidente, EP-030/MA-TSK-249 y
EP-029/MA-TSK-239. El estado `done` de 239 no acredita el alta Google: su salida
y su [evidencia](../ep-029/verificacion-oauth-android.md) declaran el bloqueo.

## Inventario comprobado antes de actuar

`config/google-oauth.public.json` conserva `blocked_external`: proyecto ID/número
nulos, Drive API y tester falsos, Windows Desktop sin ID, Android sin clientes
ni `serverClientId`. No hay configuración válida acreditada que reutilizar.
Esto describe el inventario local, no demuestra que el proyecto no exista en
Cloud. No se han recibido adjuntos ni datos públicos del titular.
SHA-256 del inventario sin modificar:
`5edd7ab08658e4a9fe5e9e53db5fb0b648ae3db6d4df6e8d09e691e1855aaccf`.

CUA devuelve `apps=[]` y `browsers=[]`; `gcloud` no está en PATH. No hay acceso
autenticado a Cloud para contrastar el proyecto/consentimiento ni autorizar la
app. El conector Google Drive usa sus propias credenciales y no acredita OAuth
de Autofinance; no se usa como sustituto.

Se reutilizan sin modificar `drive_access_factory.dart`, `drive_ui_factory.dart`,
`WindowsDriveSessionProvider`, `LoopbackGoogleAuthorization` y Credential Manager.
La UI ya consume `GOOGLE_WINDOWS_CLIENT_ID`. El inventario JSON no es un asset:
editarlo no actualiza un EXE ya construido. EP-028 ya inyecta ese ID al compilar
production y registra el hash de configuración en `payload-manifest.json`.
No se crea otro cliente HTTP, almacén, pantalla ni flujo de autorización.

## Acción pendiente del titular

1. Abrir [Google Cloud Console](https://console.cloud.google.com/) con acceso al
   proyecto de ensayo. Comprobar con el propietario de MA-TSK-239 si existe y
   reutilizar **el mismo proyecto**, distinto de MyFinance. Facilitar solo el ID
   y número públicos; no crear dos proyectos independientes por plataforma.
2. Seguir el [alta EP-005](../ep-005/oauth-google.md): habilitar Drive API,
   nombre Autofinance, audiencia External, estado Testing, contactos reales en
   consola y la misma cuenta tester para ambos dispositivos. Registrar solo
   `apiEnabled`/`testUserAdded` tras comprobarlo; nunca el correo en el informe.
3. Comprobar que Data Access declara únicamente
   `https://www.googleapis.com/auth/drive.file`. Reutilizar o crear un cliente
   **Desktop app**, Autofinance Windows, y comprobar su proyecto/tipo en consola.
   Registrar solo su Client ID en `windows.clientId`, conservando `type: desktop`.
   No copiar el JSON descargable ni su `client_secret` al repositorio o informes.
4. El titular completa los accesos, condiciones o consentimiento que Google
   requiera. Conectar un navegador para poder continuar la verificación real.
   No compartir contraseñas, códigos OAuth ni tokens con el agente.
5. Android paquete/certificado/cliente Web sigue en MA-TSK-239. Si Windows queda
   listo antes, conservar `status: blocked_external` hasta completar ambas
   plataformas. Cambiar `configured` solo después de contrastar todo el alta.

El flujo de escritorio y loopback/PKCE se contrastó con la
[documentación oficial de Google](https://developers.google.com/identity/protocols/oauth2/native-app);
el permiso se contrastó con los
[scopes oficiales de Drive](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).
El verificador local no puede comprobar en Cloud el tipo del cliente, los
permisos efectivamente concedidos ni la pertenencia de la cuenta tester.

## Controles de configuración

```powershell
node scripts/check-google-oauth.mjs
node scripts/check-google-oauth-windows.mjs
node scripts/check-google-oauth-android.mjs
node scripts/check-google-oauth.mjs --require-configured
node --test scripts/tests/google-oauth-config.test.mjs scripts/tests/google-oauth-windows.test.mjs scripts/tests/google-oauth-android.test.mjs
```

El nuevo control Windows valida primero el contrato global sin modificarlo y
exige proyecto, API/tester y cliente Desktop. Acepta una declaración Windows
completa con Android pendiente, pero devuelve el estado global original y
`completeDelivery: false`, `realDriveVerified: false`. Sigue rechazando campos
Android incoherentes, scopes extra, secretos y un falso `configured` global.
El control Android existente permanece intacto. Los gates de empaquetado EP-028
siguen exigiendo la configuración global: no se relajan desde este ticket.

## Recorrido pendiente: distinguir runner y EXE final

Usar un usuario Windows/VM dedicado al ensayo, cuenta Google de ensayo y SQLite
sintética de [T02](datos-sinteticos.md). No basta con redefinir APPDATA: Credential
Manager y las carpetas nativas pertenecen al perfil Windows. Conservar las
instalaciones anteriores y las copias recuperables. No ejecutar las pruebas
destructivas de sesión sobre un directorio de instalación personal.

El [runner existente EP-005](../ep-005/oauth-windows.md) se ejecuta en la
instalación dedicada, después del control específico Windows. No necesita
esperar a Android para ensayar su autorización. Pasar el Client ID público real
en `GOOGLE_WINDOWS_CLIENT_ID`; habilitar `MANUAL_DRIVE_TEST=true` y
`APP_ENV=test`. `DRIVE_TEST_SCENARIO=authorize` comprueba acceso, restauración
en otra composición, reutilización y renovación; `cancel` cancela localmente
a los cinco segundos. Ambos escenarios desconectan su sesión de ensayo al
terminar. Esa limpieza **no verifica persistencia entre procesos**.

Para el EXE final, consumir sin modificar la
[automatización privada EP-028](../ep-028/generacion-privada.md) desde un checkout
limpio del commit definitivo, con configuración pública completa y herramientas
fijadas. No reutilizar `build/` compartido ni empaquetar el overlay concurrente.
Verificar `delivery-manifest.json` con `windows-delivery.mjs verify`; registrar
commit, versión, SHA-256 de configuración, EXE del payload, instalador y manifiesto.
Estos campos siguen **pendientes**, sin hashes ficticios ni binarios publicados.

| Caso Google real | Runner existente | EXE production en Windows físico |
|---|---|---|
| Autorizar cuenta tester con solo drive.file | `authorize`; permiso exacto verificado por proveedor | Gestión → Drive → Subir copia sobre datos sintéticos; comprobar cuenta local sin registrarla y copia creada solo por acción manual |
| Cancelar y reintentar | `cancel`, después `authorize` | Cancelar operación durante autorización; reintentar y comprobar recuperación sin perder datos |
| Reutilizar | Segunda composición de `authorize` | Repetir acción manual sin nuevo consentimiento |
| Persistir | No acredita reinicio de proceso | Cerrar/reabrir EXE en el mismo directorio; arranque sin red, acción manual reutiliza sesión |
| Renovar | `authorize` llama a `renewAccess()` | Dejar caducar access token con el EXE cerrado; siguiente acción manual renueva sin nuevo consentimiento |
| Reconectar tras revocación | No hay escenario específico | Titular revoca solo la concesión de ensayo en Google; siguiente acción informa el fallo o pide nueva autorización según flujo existente; recuperar con acción manual y comprobar acceso |

No añadir un botón de desconexión/renovación ni modificar la UI para poder
ejecutar estos casos. Si el recorrido revela una interacción que falta,
documentar reproducción y derivar su aprobación al propietario EP-005/007.
Corregir aquí únicamente fallos de integración reproducidos con el flujo actual.
Las transferencias/divergencias completas corresponden a las pruebas de EP-030;
se conserva la excepción contractual de carrera del único archivo Drive.

Registrar por caso fecha, plataforma, origen (proveedor simulado/runner/paquete
production/dispositivo físico), hashes y resultado saneado. Nunca registrar
correo, permissionId, ID de archivo/carpeta personal, callback, parámetros OAuth,
cabeceras, credenciales ni capturas de consentimiento. Una prueba sintética o
de runner no completa la columna EXE final ni la aceptación humana de EP-030.

## Resultado de esta ejecución

- Flutter 3.47.0/Dart 3.13.0 inicializados; `check-toolchain.ps1` correcto.
- Controles OAuth: contrato global válido con bloqueo; global estricto, Windows
  y Android rechazan la configuración pendiente (salida 1 esperada).
- Pruebas Node global/Android/Windows: **32 aprobadas, 1 omitida**, sin fallos.
  La omitida inspecciona el APK técnico Android si se aporta su ruta; no es
  una prueba de Google. Ocho casos nuevos Windows cubren independencia de
  plataforma, bloqueo global, contrato y errores saneados.
- Pruebas Flutter existentes Windows: **54 aprobadas**. Receptor loopback local
  real con navegador falso, HTTP simulado y mensajero de canal falso; no es
  sesión Google ni prueba nativa Credential Manager ni EXE final.
- `check-quality.ps1`: primer intento detenido por red pub.dev (SocketException
  10057). Reintento con red autorizada: resolución con lockfile correcto,
  **508 archivos** sin cambios de formato, análisis sin incidencias y
  **2.021 pruebas aprobadas, 2 fallidas** en 12 min 36 s. Los fallos son
  `pending_lifecycle_test.dart`, Windows tabla/Android tarjetas, con
  `Bad state: No element` en `pending_lifecycle_journey.dart:82/144`, ya
  registrados por MA-TSK-239 y la auditoría T01; no se modifican desde OAuth.
  No se declara calidad global correcta. El script se detiene antes de las
  variantes de arranque; se ejecutan aparte development/test/production/
  invalid-synthetic: **cuatro aprobadas**. Un primer intento sin elevación de
  development no pudo acceder a la DLL SQLite de salida ignorada; el reintento
  autorizado pasa sin modificar la configuración global de build.
  Logs locales ignorados: `.tools/ma-tsk-249-*`. Sintaxis Node y
  `git diff --cached --check` correctos.
- No cambian Dart, Windows nativo, instalador, configuración pública, lockfile,
  toolchain o UI. No se recompilan plataformas por controles Node/documentación.
  El checkout ya contenía cambios de sincronización y otros tickets: las pruebas
  reflejan ese árbol de trabajo, no certifican una entrega limpia de HEAD.
  Esos cambios concurrentes se excluyen del commit de MA-TSK-249.

**No ejecutado:** alta Cloud, autorización/cancelación/reconexión/renovación
Google reales en runner y paquete final, persistencia de una sesión real entre
procesos, generación con ID definitivo y ensayo PC ↔ teléfono. El bloqueo no
completa MA-TSK-249. Tampoco se cierra EP-030 ni se infiere aprobación humana.
