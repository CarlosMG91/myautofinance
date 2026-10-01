# MA-TSK-047 · Carpeta visible Autofinance

## Entrega y composición

`DriveFolderLocator`, exportado por `synchronization.dart`, recibe `DriveAccess`
y `DriveMetadataClient` por constructor. Es Dart común a Windows y Android;
construirlo no restaura sesión ni realiza operaciones remotas. El futuro flujo
manual debe componer un único localizador por instalación, obtener previamente
acceso para la cuenta activa y llamar a sus métodos solo por acción expresa.
No se conecta al arranque ni se añaden pantallas, dependencias o código nativo.

Se utiliza el ticket completo facilitado por el usuario. No hay conector
Epic Board disponible en esta sesión; no se ha consultado ni modificado el
estado actual del tablero. Se revisaron el cliente MA-TSK-046, el contrato de
sesión MA-TSK-043 y los proveedores de persistencia de ambas plataformas.

## Identidad y búsqueda

La marca estable `appProperties={autofinanceRole: backupFolderV1}` se escribe
en el mismo POST que crea la carpeta. Los clientes Windows y Android deben
pertenecer al mismo proyecto OAuth conforme a [OAuth Google](oauth-google.md).
La marca es privada de la app; el nombre visible no determina la identidad.
Una carpeta ajena llamada Autofinance no se adopta, renombra ni marca.

En cada petición:

1. Comprobar sesión activa, cuenta y permiso exacto `drive.file`.
2. Resolver `files.get(root, fields=id,mimeType)` al ID real de Mi unidad:
   el alias `root` no es necesariamente el valor que aparece en `parents`.
3. Si hay ID recordado, leerlo y verificar ID, MIME de carpeta, marca,
   ausencia de papelera y padre único igual al ID real de la raíz.
4. Buscar todas las páginas por marca en `spaces=drive`, sin nombre ni MIME
   como filtro. Se buscan también recursos fuera de raíz para detectar una
   carpeta movida desde una instalación que aún no recuerda su ID.
5. Combinar por ID el resultado de búsqueda y la referencia verificada.
   Varias IDs producen ambigüedad; ninguna se elige ni se borra. Una única
   candidata se valida y se vincula localmente antes de anunciar éxito.

El cliente mantiene filtros escapados, paginación completa y errores tipados
de [metadatos Drive](metadatos-drive.md). `appProperties` es un mapa inmutable;
su ausencia se representa como mapa vacío y no acredita identidad. Una lista
incompleta o incoherente nunca equivale a una carpeta ausente.

`DriveAccess.rememberFolder` conserva el ID con su `DriveAccount.permissionId`
en el almacenamiento seguro de la plataforma. No se guarda en SQLite ni en
la futura copia. Otra instalación descubre la misma marca y guarda su propio
vínculo. Restaurar sesión permite reutilizarlo; renombrar la carpeta conserva
ID y marca. La selección expresa de otra cuenta sigue borrando la referencia
anterior según el contrato existente de sesión.

## API y estados

| Método | Comportamiento |
|---|---|
| `findFolder()` | Consulta manual; nunca crea. Una búsqueda completa vacía devuelve `notFound` |
| `requestFolder()` | Petición manual que permite crear si no hay ID recordado ni candidatas ni POST pendiente de confirmar |

| `DriveFolderStatus` | Significado |
|---|---|
| `found` | Carpeta existente, validada y vinculada localmente |
| `created` | Carpeta creada, validada y vinculada localmente |
| `notFound` | Búsqueda válida sin carpeta, sin crear recursos |
| `missingOrInaccessible` | ID recordado en papelera o GET 404; Drive no permite distinguir inexistencia de falta de acceso |
| `moved` | Carpeta marcada con ubicación distinta de la raíz de Mi unidad |
| `invalidIdentity` | ID recordado sin marca correcta, o marca en un recurso con tipo incorrecto |
| `ambiguous` | Varias IDs candidatas; lista inmutable de IDs para el futuro flujo de resolución, sin carpeta seleccionada |
| `creationUnconfirmed` | Hubo un POST de resultado incierto y la búsqueda aún no encuentra su carpeta; no repetir POST a ciegas |

Solo `found` y `created` contienen `folder`. Los errores de transporte,
credencial, límites y permisos conservan `DriveMetadataFailure`, incluido
`retryAfter`; los de sesión o persistencia usan `DriveAccessFailure`. Un GET
403 no se interpreta como ausencia. Un fallo local al guardar el vínculo no
anuncia creación confirmada; el siguiente intento vuelve a descubrir la carpeta.
No se registran IDs, nombres, mensajes externos ni credenciales en `toString`.

Un ID recordado inválido no se sustituye silenciosamente aunque pudiera existir
otra carpeta marcada. Requiere resolver expresamente la situación fuera de
este ticket. Sin ID previo no se puede inferir que una carpeta inaccesible o
borrada pertenecía a esta instalación; la búsqueda solo acredita los recursos
visibles al permiso concedido.

## Creación y límites

La única escritura remota sigue siendo `files.create` con nombre Autofinance,
MIME `application/vnd.google-apps.folder`, `parents=[root]` y la marca privada.
Es una carpeta normal y visible. No se usa `appDataFolder`, ni se crean archivos
vacíos, ni se modifica o elimina ninguna carpeta preexistente.

Las llamadas al mismo localizador son exclusivas. En condiciones normales la
primera petición hace un POST y las siguientes reutilizan la carpeta. Tras el
POST se vuelve a buscar por marca para detectar duplicados aparecidos durante
la operación. Drive no ofrece una restricción única por marca: dos instalaciones
que creen simultáneamente pueden producir duplicados, que se señalan sin elegir
ni borrar ninguno. No se promete exclusión distribuida ni idempotencia del POST.

Ante timeout, fallo de red, 5xx o respuesta incompleta, se vuelve a descubrir
antes de cualquier decisión. Si sigue sin haber candidata, el servicio conserva
en memoria el estado `creationUnconfirmed` por cuenta y bloquea otra creación.
Ese bloqueo dura la vida del localizador; no es un registro duradero entre
reinicios. El consumidor debe conservar este servicio durante el flujo manual;
una futura protección duradera de operaciones remotas queda fuera de la entrega.
Un rechazo definitivo, por ejemplo HTTP 429, permite otro intento manual después
de volver a buscar. No hay reintentos, esperas ni renovación automáticos.

La existencia de una carpeta no acredita que haya copia remota. Este ticket no
lista ni valida archivos de copia; el localizador de copia posterior decidirá
`sin_copia` y esperará a la primera subida válida. No hay upload, download,
SQLite, reemplazo, fusión ni ejecución en segundo plano.

## Fuentes oficiales

Se verificaron [propiedades privadas y búsquedas](https://developers.google.com/workspace/drive/api/guides/properties),
[consultas Drive](https://developers.google.com/workspace/drive/api/guides/search-files)
y [campos del recurso File](https://developers.google.com/workspace/drive/api/reference/rest/v3/files).

## Verificación

`test/synchronization/drive_folder_locator_test.dart` usa exclusivamente cuentas,
metadatos, almacenamiento y HTTP sintéticos. Cubre creación expresa, consultas
sin efectos remotos, persistencia/restauración, dos instalaciones, renombrado,
carpetas homónimas ajenas, duplicados, papelera/404/403, carpetas movidas, marca
o MIME incorrectos, listas incoherentes, todos los errores de metadatos,
persistencia fallida, POST incierto, carrera de creación, cambios de cuenta,
caducidad y exclusión de peticiones locales simultáneas. El recorrido con el
cliente HTTP real comprueba marca en POST y consulta, raíz real y un único POST
entre dos instalaciones simuladas. Las pruebas existentes de metadatos se
amplían con raíz, filtros escapados y validación/inmutabilidad de propiedades.

Comprobaciones locales del 2026-10-01:

- `flutter --version` y `scripts/check-toolchain.ps1`: Flutter 3.47.0 y
  Dart 3.13.0 correctos.
- `flutter pub get --enforce-lockfile`: correcto, sin cambios de SDK,
  dependencias ni lockfile. El sandbox impidió consultar pub.dev inicialmente;
  funcionó con la revisión de permisos de ejecución.
- Localizador, metadatos y arquitectura: **149 pruebas correctas**.
- `scripts/check-quality.ps1`: 74 archivos Dart sin cambios de formato,
  análisis sin incidencias, **360 pruebas correctas** y las cuatro variantes
  adicionales de arranque `APP_ENV` correctas.
- Permanece la advertencia previa de Drift sobre instancias múltiples en la
  prueba SQLite integrada; no produjo fallos ni se cambió ese módulo.
- `git diff --check`: correcto; solo se incluyen los nueve archivos propios
  de MA-TSK-047, con datos sintéticos y sin credenciales reales.

La comprobación con una cuenta Drive real y dispositivos Windows/Android sigue
pendiente del aprovisionamiento OAuth de MA-TSK-042 registrado en
[verificación OAuth](verificacion-oauth.md). Los tests no acreditan consentimiento,
indexación real de Drive ni almacenamiento nativo en dispositivos.
No se requieren builds nativos: no cambian plataformas ni dependencias.
