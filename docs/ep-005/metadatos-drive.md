# MA-TSK-046 · Cliente de metadatos Drive v3

## Entrega

`DriveMetadataClient` es el puerto Dart público de `synchronization.dart`.
`HttpDriveMetadataClient` implementa `files.list/get/create` con el paquete
`http` ya fijado. Recibe cliente HTTP, fuente de credenciales y reloj por
constructor. El propietario cierra el cliente HTTP. No cambia dependencias,
lockfile, código nativo, SQLite, configuración OAuth ni pantallas.

Se ha usado el ticket íntegro facilitado por el usuario: Epic Board no tiene
conector disponible ni navegador conectado en esta sesión. No se ha leído ni
modificado directamente el estado del tablero.

## Operaciones

| Método | Comportamiento |
|---|---|
| Constructor | No consulta credenciales, autoriza, renueva ni hace red |
| `getMyDriveRootId(accountId)` | Añadido en MA-TSK-047: resuelve el ID real de la raíz con GET `fields=id,mimeType` |
| `listFiles(accountId, parentId?, name?, mimeType?, appProperties?)` | GET, `trashed=false`, filtros estructurados con literales escapados; todas las páginas, incluidas las vacías con continuación |
| `getFile(accountId, fileId)` | GET de metadatos, ID codificado como un segmento; comprueba identidad de la respuesta y rechaza papelera |
| `createAutofinanceFolder(accountId)` | Única escritura: POST JSON de carpeta normal `Autofinance`, MIME de carpeta y `parents=[root]`, en Mi unidad; MA-TSK-047 añade marca privada en el mismo POST |

La creación exige que el consumidor invoque ese método tras una acción expresa.
No se invoca desde autorización, arranque, consulta o búsqueda vacía. No hay
creación de archivo vacío, peticiones `alt=media`, endpoint de upload, lectura o
escritura de contenido de la base, reemplazo, fusión ni tareas en segundo plano.

Las listas usan `spaces=drive`, `corpora=user`,
`includeItemsFromAllDrives=false` y `pageSize=1000`. Solicitan
`nextPageToken,incompleteSearch,files(id,name,mimeType,parents,trashed,appProperties,modifiedTime,size,md5Checksum,version)`.
GET individual solicita los mismos campos de archivo; crear carpeta solicita
solo `id,name,mimeType,parents,trashed,appProperties`. MA-TSK-047 añade
`appProperties`, mapa opcional tipado e inmutable para verificar identidad.
Los campos opcionales de archivo aportan
fecha, tamaño, checksum y revisión sin descargar contenido. `version` se
conserva como cadena para admitir el entero uint64 de Drive.

La respuesta exige `id`, `name`, `mimeType`, `parents` y `trashed` para los
recursos esperados de Autofinance. Los campos opcionales pueden estar ausentes
(por ejemplo, tamaño/checksum en carpetas), pero se validan cuando llegan.
`parents` y el resultado de lista son inmutables. `incompleteSearch=true`,
JSON inválido, campos requeridos ausentes, continuaciones inválidas/cíclicas o
elementos en papelera en una lista filtrada producen `incompleteResponse`.
Un fallo en cualquier página descarta el resultado entero; no se entregan
resultados parciales que puedan confundirse con ausencia de copia.

Una búsqueda válida sin coincidencias devuelve una lista vacía. El
[localizador de MA-TSK-047](carpeta-drive.md) comprueba/vincula la carpeta y
señala duplicados. La localización posterior de archivos de copia decidirá
`sin_copia`; este adaptador no interpreta un 404 como ausencia de copia.

## Sesión y composición

`DriveMetadataCredentialSource` y `DriveMetadataCredential` pertenecen a
`data`; el dominio y `DriveSession` siguen sin transportar tokens. La fuente
se inyecta para adaptar la credencial de plataforma ya autorizada a la petición
manual. Debe acreditar que el token pertenece a esa cuenta y al permiso
efectivo exacto. No debe abrir consentimiento ni renovar acceso por su cuenta.
Esta entrega mantiene esa frontera simulable; no conecta el cliente al arranque
ni añade todavía la composición del localizador con los proveedores nativos.

Antes de **cada** petición (también cada página), el cliente vuelve a pedir la
credencial y comprueba cuenta solicitada, cuenta de la carpeta vinculada,
vigencia, scope exactamente `{drive.file}` y token válido para la cabecera
Bearer. Nunca amplía permisos, almacena credenciales ni conserva tokens entre
operaciones. La autorización/renovación corresponde al flujo explícito
`DriveAccess` definido en [sesión Drive](sesion-drive.md).

El endpoint HTTPS es fijo `www.googleapis.com/drive/v3/files`; no se aceptan
URLs remotas del consumidor y se deshabilitan redirects para no reenviar el
Bearer. No se registran cuerpos, cabeceras, IDs, URLs ni excepciones externas.
`toString()` de credencial/metadatos omite sus valores; el fallo imprime solo
enum y estado HTTP.

## Fallos tipados y límites

| Condición | `DriveMetadataIssue` |
|---|---|
| HTTP 401 / vigencia caducada | `credentialExpired` |
| HTTP 403 sin motivo de límite / scope inválido | `permissionDenied` |
| HTTP 404 / GET de recurso en papelera | `notFound` (inexistente o inaccesible) |
| HTTP 429 / 403 `rateLimitExceeded`, `userRateLimitExceeded` | `rateLimited` |
| 403 por cuota diaria, almacenamiento, elementos, hijos o profundidad | `quotaExceeded` |
| Error del transporte o lectura del cuerpo | `networkFailure` |
| Tiempo agotado en credencial, petición o cuerpo | `requestTimeout` |
| Respuesta incompleta o inconsistente | `incompleteResponse` |
| HTTP 5xx | `serverUnavailable` |
| Otros HTTP, incluidos redirects / argumentos vacíos | `invalidRequest` |
| Token vacío o inválido para Bearer | `invalidCredential` |
| Cuenta o carpeta de otra cuenta | `accountChangeRequired` |
| Fallo al obtener la credencial | `credentialUnavailable` |

`DriveMetadataFailure` expone enum, estado HTTP cuando existe y `retryAfter`
opcional para límites/5xx. Acepta segundos o fecha HTTP de `Retry-After`; una
fecha pasada se representa con duración cero y una cabecera inválida se ignora.
No conserva mensajes remotos. El timeout por fase es de 30 segundos por defecto
y es inyectable para pruebas.

No hay reintentos, esperas ni renovación automáticos. El futuro flujo manual
puede decidir otro intento respetando el límite comunicado. Un timeout/fallo
de red o respuesta incompleta tras POST **no demuestra que la carpeta no se haya
creado**: el consumidor debe volver a localizarla antes de crear otra. La
operación pendiente del transporte puede terminar después del timeout; no se
anuncia cancelación remota ni idempotencia del POST.

## Fuentes oficiales

Consultadas durante esta implementación:
[files.list](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/list),
[files.get](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/get),
[files.create](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/create)
y [errores Drive](https://developers.google.com/workspace/drive/api/guides/handle-errors).

## Verificación

`test/synchronization/drive_metadata_client_test.dart` usa exclusivamente HTTP
simulado y credenciales sintéticas. Cubre el puerto falso, campos/filtros,
escape de consultas, paginación completa/vacía/cíclica, GET y creación de
carpeta, todos los estados HTTP relevantes en las tres operaciones, motivos de
límite/cuota, Retry-After, red, timeout de petición/cuerpo/credencial, respuestas
incompletas, caducidad/cambio de cuenta entre páginas y scope exacto. No crea
recursos en una cuenta real de Drive.

Verificación local del 2026-10-01:

- `flutter --version`, `scripts/check-toolchain.ps1` y
  `flutter pub get --enforce-lockfile`: Flutter 3.47.0 y Dart 3.13.0 correctos,
  sin cambios de SDK, paquetes ni lockfile. La resolución inicial no pudo
  acceder a pub.dev dentro del sandbox; funcionó con la revisión de permisos
  de ejecución.
- Pruebas de metadatos y arquitectura: **96 correctas**, de las que **94** son
  nuevas de MA-TSK-046.
- `scripts/check-quality.ps1` completo: 72 archivos Dart sin cambios de
  formato, análisis sin incidencias, **307 pruebas correctas** y las cuatro
  variantes adicionales de arranque `APP_ENV` correctas.
- `git diff --check`: correcto. Solo se incluyen los archivos propios del
  ticket, con datos sintéticos y sin credenciales reales.

OAuth y Drive reales permanecen sin verificar: el aprovisionamiento de
MA-TSK-042 sigue pendiente según [verificación OAuth](verificacion-oauth.md).
No se requieren builds nativos: esta entrega solo añade Dart común, sin cambios
de plataformas ni dependencias.
