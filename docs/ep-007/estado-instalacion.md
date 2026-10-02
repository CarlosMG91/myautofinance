# MA-TSK-062 · Estado de sincronización por instalación

`InstallationSyncState` es el puerto público; `createInstallationSyncState`
compone el adaptador con la lectura de `DatasetState` de MA-TSK-038 y el lector
de contraste de MA-TSK-056. Construirlo no abre SQLite, restaura sesión OAuth ni
consulta Drive. El consumidor de EP-007 aporta `DriveAccount.permissionId` y
el ID/metadatos de la copia resuelta por EP-005, nunca correo como identidad.

## Persistencia e identidad

Se guarda `<soporte>/drive-sync/state.json`, separado de `<soporte>/sqlite` y
de todas las imágenes SQLite compartidas. Contiene cuenta, archivo, versión
remota conocida, dataset/revisión de la imagen correspondiente, última versión
observada, fecha UTC de comprobación, epoch contrastado y operación pendiente
(UUID, dirección, imagen capturada, epoch inicial y versión a instalar).
No guarda tokens, correo, credenciales, bytes SQLite ni respuestas HTTP.

Se conserva una única vinculación activa por instalación, siempre asociada a
la cuenta Google y al archivo. Al seleccionar otra cuenta **o** archivo se
invalida duraderamente la relación anterior, incluida cualquier operación:
volver a seleccionar la identidad anterior empieza desconocido, sin reutilizar
su versión. Un acuse tardío con el UUID anterior se rechaza. No hay caché de
comparaciones antiguas por cuenta que pueda acreditar limpieza al volver.

El adaptador reutiliza el sobre JSON estricto con SHA-256 y las primitivas
nativas de EP-006: archivo completo temporal, flush y reemplazo durable
(MoveFileExW WRITE_THROUGH en Windows; rename/fsync en Android). El archivo
anterior permanece válido hasta el reemplazo; los temporales no son estados
publicados. Un bloqueo local nativo cubre lectura/modificación/escritura y la
instalación de descarga, incluso entre instancias/procesos. Errores de disco,
formatos futuros o datos corruptos fallan sin sobrescribir el estado ni afirmar
limpieza. El hash detecta corrupción accidental; no es cifrado ni autenticación.

## Comparación y transiciones

| Estado local | Evidencia |
|---|---|
| `unknown` | No existe relación acreditada entre imagen y versión remota |
| `clean` | Dataset y revisión iguales a la imagen vinculada, epoch contrastado, sin operación ni señal ambigua |
| `changed` | Dataset o revisión actual distintos de la imagen vinculada |
| `contrastRequired` | Restauración posterior o señal de contraste todavía sin acreditar |
| `pending` | Operación persistida todavía sin confirmación duradera |

`remoteChanged` es independiente del estado **local**: compara la última versión
observada con la conocida. `recordCheck` actualiza observación/fecha sin vincular
la base ni limpiar una restauración. Una divergencia observada impide
`beginUpload`; la consulta remota fresca, los estados sin copia/ambiguos y la
decisión ante estado desconocido corresponden al coordinador de MA-TSK-066.
Una igualdad de versiones observada no prueba igualdad del contenido local.

Para subir, capturar una imagen validada de EP-006/MA-TSK-038 y pasar **su**
`DatasetState` a `beginUpload` antes de transferir. Solo después del acuse de
publicación verificado llamar a `completeUpload` con el UUID y los metadatos de
ese archivo. Se conserva la revisión capturada, no la revisión al acabar:
una edición durante la transferencia continúa como `changed`. Si cambia el
epoch durante la subida, la confirmación se rechaza y conserva `pending`.
Un acuse incierto tras un corte requiere contraste explícito posterior; este
ticket no inventa éxito remoto, condiciones HTTP ni reintentos automáticos.

Para descargar, `beginDownload` registra la versión desde el inicio de la
transferencia; `recordDownloadedImage` añade la imagen tras validarla en staging.
También se permite aportar la imagen ya validada a `beginDownload`.
Eso todavía no vincula la activa. `installDownload` recibe el callback del
instalador seguro, que debe aplicar la imagen indicada con respaldo, confirmación
del usuario y validación, conforme a EP-006. Solo `restored`, con imagen actual
coincidente y nuevo epoch de instalación, vincula esa versión. Cancelación,
rechazo, rollback, excepción o caída antes de publicar el estado conservan
`pending`. Tras un reinicio no se aplica una descarga automáticamente: el
coordinador debe resolver la operación incierta. `abandonPending` invalida la
comparación; nunca convierte cancelación o incertidumbre en limpio.

El lector de MA-TSK-056 añade `unreliable` para distinguir diario en curso o
catálogo dañado/ambiguo de una petición ordinaria de contraste. Esa señal
impide confirmar operaciones. La sincronización conserva su propio epoch
contrastado; no modifica el catálogo de respaldos ni su indicador persistente.
Una restauración local posterior cambia el epoch incluso con la misma revisión
y exige nuevo contraste. La instalación remota satisfactoria acredita su nuevo
epoch únicamente después de validar la base aplicada.

## Alcance y verificación

Se utiliza el ticket completo proporcionado. Epic Board no está disponible en
esta sesión; no se cambia el estado administrativo. No se implementan pantallas,
transferencias, resolución de conflictos ni OAuth; los adaptadores de EP-005 se
consumen mediante identidad y metadatos. MA-TSK-061 documenta pendiente su ensayo
empírico por falta de OAuth; este estado no promete escritura condicional.

Las 19 pruebas nuevas cubren desconocido, reinicio, versión/fecha sin tokens,
ediciones antes/durante la transferencia, otro dataset, cuenta/archivo y acuse
tardío, operación incierta, restauración de igual revisión, catálogo ambiguo,
cancelación/rechazo/rollback, instalación validada, imagen/epoch incorrectos,
fallo del reemplazo, estado corrupto y exclusión entre instancias. Incluyen una
base SQLite real, copia consistente, mutación transaccional, instalación con el
restaurador real, reapertura y posterior restauración local.

Verificación local del 2026-10-02:

- Flutter 3.47.0 / Dart 3.13.0 y `check-toolchain.ps1` correctos; resolución con
  `flutter pub get --enforce-lockfile`, sin cambios de SDK, paquetes o lockfile.
- `scripts/check-quality.ps1` final: 114 archivos Dart con formato correcto,
  análisis sin incidencias, **646 pruebas correctas**, incluidas las 19 nuevas,
  y las cuatro variantes adicionales de arranque `APP_ENV`.
- Los primeros intentos en sandbox quedaron bloqueados por red a pub.dev y por
  resolución de antecesores de rutas temporales Windows. Con permisos revisados
  pasan las comprobaciones de persistencia nativa y SQLite.
- `node docs/ep-001/verificar-casos.mjs` y `git diff --check`: correctos.
- Builds intentados con los comandos fijados: Windows bloqueado por falta de
  Visual Studio C++; Android bloqueado por ausencia del SDK Android. No se
  acredita compilación nativa de la aplicación ni ejecución en Android.

Las pruebas usan datos sintéticos; no acceden a una cuenta Drive ni acreditan
un corte eléctrico del hardware. La publicación Git se comunica únicamente
después de comprobar el push, sin modificar el estado administrativo del tablero.
