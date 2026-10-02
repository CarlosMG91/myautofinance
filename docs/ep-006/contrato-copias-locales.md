# MA-TSK-051 · Contrato de copias locales y catálogo

## Alcance y fuentes

Contrato **v1** de EP-006 / MA-EPIC-050 para Windows y Android. Define archivos,
metadatos, estados y garantías para MA-TSK-052–056; no implementa todavía el
servicio, la restauración ni la pantalla. No transfiere a Drive, importa archivos
externos arbitrarios ni fusiona bases. La interfaz de MA-TSK-058 espera las
aprobaciones de MA-TSK-019 y del mockup MA-TSK-057.

Se revisan MA-TSK-051 y sus dependencias en el ticket íntegro facilitado por el
usuario y en la lectura local previa `.tools/epic-board-read.json`, tablero
**My autofinance**. Esta última es una instantánea, no acredita el estado actual
del tablero. No hay conector Epic Board disponible para actualizarlo.

Fuentes vigentes: [persistencia de MA-TSK-032](../ep-004/persistencia-local.md),
[primitiva de MA-TSK-038](../ep-004/transacciones-copias.md),
[esquema v6 y entrega EP-004](../ep-004/guia-integracion.md),
[EP-001 §7.1](../ep-001/especificacion.md) y
[arquitectura](../ep-003/arquitectura.md). EP-005 no es una dependencia.

## Artefacto y ubicación

Una copia completa es un directorio inmutable con **dos archivos**:
`autofinance.sqlite` y `manifest.json`. SQLite contiene solamente los datos
financieros y `database_state`; el manifiesto describe esos mismos bytes. No es
un ZIP ni una copia del archivo principal mientras la base está abierta. No
incluye WAL, SHM, journal, objetos TEMP, catálogo, sesión OAuth ni estado Drive.
Si necesita sidecars para abrirse, no es una copia completa de este formato.

App inyecta `LocalBackupSource`, ya publicado por `synchronization`, y usa
exclusivamente `LocalDatabaseStore.createConsistentBackup()` para capturar la
base viva. Conserva `LocalBackup.path` y lee identidad/revisión de
`LocalBackup.state`; confirma versión y tamaño desde el archivo resultante.
No vuelve a leer la revisión de la base activa para describir la copia. No
añade otro motor `VACUUM INTO`, backup API ni copia de la base viva. El traslado
de una imagen ya terminada y cerrada no es una segunda captura.

`S = getApplicationSupportDirectory()` resuelto por instalación, nunca Documents,
una carpeta compartida, Drive, almacenamiento externo Android ni una ruta elegida
por el usuario. Se mantiene la ubicación de MA-TSK-032:

```text
S/sqlite/
  autofinance.sqlite                       # base activa; sidecars solo aquí
  copies/snapshot-*/autofinance.sqlite      # salida privada de MA-TSK-038
  local-backups/
    catalog-a.json                         # generación confirmada A
    catalog-b.json                         # generación confirmada B
    catalog-<operationId>.next              # escritura pendiente, no publicable
    backups/<backupId>/
      autofinance.sqlite
      manifest.json
    staging/<backupId>/
      intent.json                          # intención previa a la captura
      receipt.json                         # ruta relativa de la salida recibida
      autofinance.sqlite.part
      manifest.json.part
    tombstones/<backupId>.json              # baja duradera, fuera de la copia
    restore/<operationId>/                 # trabajo, anterior y diario de intercambio
```

`backupId` y `operationId` son UUID v4 nuevos, minúsculos, independientes del
linaje de datos. Un nombre no contiene fecha, revisión, categoría o nombre de
cuenta; no se reutiliza ni sobreescribe un destino existente. La fecha legible
procede de metadatos, no del nombre. Todos los movimientos de publicación se
hacen en este volumen, con destino nuevo.

Las rutas persistidas son relativas a `S/sqlite`, usan `/` y se derivan de UUID
validados: `local-backups/backups/<backupId>/autofinance.sqlite`. Se rechazan rutas
absolutas, `..`, URI, enlaces simbólicos/reparse points y cualquier resolución
fuera de esa raíz antes de leer, renombrar o borrar. La recuperación no sigue
enlaces encontrados durante el escaneo. Solo `receipt.json` puede referenciar
`copies/snapshot-*/autofinance.sqlite`; no convierte una ruta externa en copia.

Windows usa el soporte privado del usuario y sus permisos heredados; Android
usa el directorio interno de la app. No se añade cifrado. Estas copias sobreviven
al cierre y reinicio, pero no garantizan recuperación tras desinstalación, pérdida
del dispositivo o borrado del directorio privado. Los respaldos `pre-v*` de
migración pertenecen a EP-004: no se podan ni se adoptan automáticamente aquí.

## Serialización y metadatos

Los JSON son UTF-8 sin BOM, con claves únicas y sin NaN ni Infinity. Todos los
documentos duraderos usan este sobre de dos campos:

```json
{"payload":"{}","payloadSha256":"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"}
```

`payload` es una cadena que contiene el JSON del documento. `payloadSha256` es
SHA-256 hexadecimal minúsculo de los **bytes UTF-8 de la cadena decodificada**,
sin BOM ni salto añadido. Primero verificar el hash, después interpretar ese
JSON; no reserializarlo para calcular el hash. El ejemplo ilustra solo el sobre,
no un manifiesto válido. El hash detecta daños accidentales, no autentica datos
frente a una persona que pueda alterar ambos archivos.

Fechas: UTC gregoriana con formato `YYYY-MM-DDTHH:mm:ss.SSSZ`. UUID de base:
formato hexadecimal minúsculo `8-4-4-4-12`, conservado exactamente de EP-004;
no imponer una nueva restricción de variante a linajes históricos. Contadores
int64 no negativos (`revision`, `generation`, `sizeBytes`, `creationOrder`) se
serializan como cadenas decimales canónicas, sin signo ni ceros iniciales,
rango 0–9223372036854775807. Tamaño, orden y generación deben ser > 0. Comparar
como enteros exactos, nunca como coma flotante o cadenas lexicográficas.
Si un contador se agota se devuelve error sin reiniciarlo.

Payload obligatorio de `manifest.json`:

| Campo | Tipo y significado |
|---|---|
| `kind` / `formatVersion` | `autofinance.localBackup` / entero `1`; versión de este formato, no de SQLite |
| `backupId` | UUID v4 igual al directorio y a la entrada de catálogo |
| `datasetId` | Identidad de `database_state.dataset_id` en la copia |
| `applicationId` | Entero `1095126595` (`0x41464e43`, AFNC) |
| `schemaVersion` | Entero de `PRAGMA user_version`; actualmente esquema publicado 6 |
| `revision` | Cadena decimal de `database_state.revision` capturada |
| `createdAtUtc` | Fecha al finalizar la captura; no equivale a fecha del último movimiento |
| `creationOrder` | Orden creciente asignado bajo exclusión local; desempata fechas y relojes atrasados |
| `origin` | `manual` o `preRestore`; no se deduce de nombres o revisión |
| `restoreOperationId` | UUID v4 para `preRestore`; `null` para `manual` |
| `databaseFile` | Literal `autofinance.sqlite` |
| `sizeBytes` | Longitud exacta positiva del archivo final |
| `databaseSha256` | SHA-256 de todos los bytes SQLite, hexadecimal minúsculo de 64 caracteres |
| `initialValidation` | Objeto `{state, checkedAtUtc, policySchemaVersion, issue}`; al publicar: `valid`, fecha UTC, entero 6 actualmente, `null` |

Ejemplo sintético de **payload** (el hash SQLite es ilustrativo, no una base
distribuida ni una prueba de integridad):

```json
{
  "kind": "autofinance.localBackup",
  "formatVersion": 1,
  "backupId": "22222222-2222-4222-8222-222222222222",
  "datasetId": "11111111-1111-4111-8111-111111111111",
  "applicationId": 1095126595,
  "schemaVersion": 6,
  "revision": "12",
  "createdAtUtc": "2026-10-02T12:00:00.000Z",
  "creationOrder": "4",
  "origin": "manual",
  "restoreOperationId": null,
  "databaseFile": "autofinance.sqlite",
  "sizeBytes": "4096",
  "databaseSha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "initialValidation": {
    "state": "valid",
    "checkedAtUtc": "2026-10-02T12:00:01.000Z",
    "policySchemaVersion": 6,
    "issue": null
  }
}
```

No hay credenciales, tokens, correos, IDs de cuenta/carpeta Drive, versión remota,
rutas absolutas o textos de excepciones en estos documentos. Rechazar campos
desconocidos en v1; una ampliación exige versionar formato y lector explícitamente.
Una versión futura se preserva y se señala incompatible; no se reescribe como v1.

## Catálogo independiente

El catálogo se resuelve y lee **antes de intentar `LocalDatabaseStore.open()`**.
Leerlo no llama a la fuente de snapshot, no crea una base vacía y no depende de
tablas en la activa. Tampoco necesita abrir SQLite de las copias para mostrar
el último resultado de validación. Su payload contiene:

| Campo | Contrato v1 |
|---|---|
| `kind` / `formatVersion` | `autofinance.localBackupCatalog` / `1` |
| `generation` | Contador positivo, incrementado por cada escritura confirmada del catálogo |
| `writtenAtUtc` | Fecha UTC de esta escritura |
| `nextCreationOrder` | Contador positivo mayor que todo orden asignado, incluso a intenciones pendientes |
| `localRestoreEpoch` | UUID v4 por instalación; cambia tras cada restauración local completada |
| `syncContrastRequired` | Booleano; `true` tras restaurar o reconstruir un estado perdido |
| `entries` | Lista de entradas únicas por `backupId`; nunca duplica una misma copia por ruta |

En una raíz nueva se crea epoch aleatorio, `generation = "1"`,
`nextCreationOrder = "1"` y `syncContrastRequired = true`: todavía no existe
un contraste remoto acreditado. Ejemplo sintético del payload vacío:

```json
{
  "kind": "autofinance.localBackupCatalog",
  "formatVersion": 1,
  "generation": "1",
  "writtenAtUtc": "2026-10-02T12:00:00.000Z",
  "nextCreationOrder": "1",
  "localRestoreEpoch": "33333333-3333-4333-8333-333333333333",
  "syncContrastRequired": true,
  "entries": []
}
```

Cada entrada contiene `descriptor` (payload íntegro e inmutable del manifiesto),
`manifestPayloadSha256` (hash de su payload), `relativeDirectory` (ruta derivada
del ID), `availability` y `validation`. Esta caché conserva fecha, origen y tamaño
aunque falte el archivo. `validation` tiene los cuatro campos de
`initialValidation`; refleja la última comprobación, sin modificar el manifiesto.
`availability` admite `present`, `missing`, `incomplete`, `quarantined` y
`deletionPending`. Una entrada `present` exige manifiesto y SQLite finales;
sin descriptor fiable se muestra una incidencia separada con ruta derivada/ID y
origen **desconocido**, nunca se inventan datos ni se registra como copia válida.

Estados de `validation.state`:

| Estado | Significado y acción |
|---|---|
| `pending` | Sin comprobación integral reciente; `checkedAtUtc`, `policySchemaVersion` e `issue` nulos |
| `valid` | Comprobación integral terminada; fecha y política obligatorias, `issue = null` |
| `invalid` | Daño o incumplimiento probado; fecha, política e incidencia obligatorias |
| `incompatible` | Formato/esquema no soportado; fecha, política e incidencia obligatorias; conservar |
| `unavailable` | No se pudo leer por permisos, disco o archivo ausente; fecha, política e incidencia obligatorias; no equivale a corrupción |

Incidencias estables: `incompleteFile`, `sizeMismatch`, `hashMismatch`,
`invalidMetadata`, `foreignFormat`, `futureFormat`, `futureSchema`,
`unsupportedSchema`, `schemaMismatch`, `integrityFailure`, `foreignKeyFailure`,
`financialRuleFailure`, `missingFile`, `storageFailure`. Mensajes españoles en
presentación, sin SQL, rutas privadas ni excepciones nativas. Una validación
histórica se muestra como «Validada el …», no garantiza el estado actual:
restaurar y podar requieren volver a comprobar bytes y política vigente.

El listado se ordena por `createdAtUtc` descendente y después `creationOrder`
descendente e ID; la retención usa `creationOrder`, no el reloj. La lectura tiene
resultado `ready`, `recovered`, `empty`, `incompatible` o `unavailable`.
`empty` solo significa raíz nueva sin artefactos o catálogo válido sin entradas
y sin incidencias; un error de lectura nunca se convierte en lista vacía.

## Publicación y validación de una copia

Todas las mutaciones del catálogo, creación, baja y restauración se serializan
por instalación, también entre procesos. Un segundo propietario obtiene
`operationInProgress`; al morir el proceso se libera la exclusión del sistema.
No basta un booleano en memoria. No se permite publicar dentro de `UnitOfWork.run`.

1. Reservar UUID/orden y persistir `staging/<backupId>/intent.json` antes de
   llamar a la primitiva. Payload: `kind = autofinance.localBackupIntent`,
   `formatVersion = 1`, `backupId`, `creationOrder`, `origin`,
   `restoreOperationId`, `requestedAtUtc`. Guardar el siguiente orden en catálogo.
2. Llamar una vez a `createConsistentBackup()`. Persistir `receipt.json` con
   `kind = autofinance.localBackupReceipt`, `formatVersion = 1`, `backupId` y
   `snapshotRelativePath`, comprobada dentro de `copies`. Un crash antes del
   receipt puede dejar un snapshot sin asociación: se conserva como huérfano,
   no se presume automático ni se elimina por antigüedad.
3. Trasladar la imagen cerrada a `.part` en staging sin sobrescribir. Calcular
   tamaño y SHA-256, abrir **solo esa imagen en modo lectura** y reutilizar la
   política de EP-004: AFNC, versión/estructura exactas, `integrity_check`,
   `foreign_key_check`, metadatos y reglas financieras. Comparar linaje/revisión
   con el resultado de la primitiva. Esquema actual: 6; versiones publicadas
   1–5 solo mediante el camino de migración soportado de MA-TSK-054, sobre una
   copia de trabajo. La v0 sintética no es un formato local publicado.
4. Cerrar, vaciar buffers de archivos y persistir el manifiesto completo.
   Renombrar los `.part` a sus nombres finales y publicar el directorio con UUID
   nuevo en `backups`. La mera existencia de nombres finales no publica éxito.
5. Añadir la entrada y confirmar una nueva generación de catálogo. Solo entonces
   devolver la copia disponible. La limpieza de intent/receipt y de la salida
   temporal propia viene después; un fallo de limpieza es un aviso, no pérdida.

Cada escritura duradera exige archivo completo, flush, cierre, relectura de
hash/estructura y confirmación del cambio de nombre en el directorio mediante
el adaptador de plataforma. No presumir que `rename` o `File.flush` por sí solos
garantizan resistencia a pérdida eléctrica; MA-TSK-052/056 deben probar la
implementación Windows/Android. Si falta espacio, falla escritura/cierre o no
se confirma persistencia, no anunciar éxito ni eliminar copias existentes.
SQLite advierte que una interrupción de `VACUUM INTO` puede dejar una salida
incompleta; por ello los temporales siempre se vuelven a validar.
Fuente: [documentación oficial de VACUUM INTO](https://www.sqlite.org/lang_vacuum.html).

## Escritura y recuperación del catálogo

Se mantienen **dos generaciones completas**, nunca se trunca la más reciente.
Leer y verificar A y B; seleccionar la generación válida mayor. Escribir la
siguiente en `catalog-<operationId>.next`, persistir y releer, después sustituir
solo el slot ausente, inválido o de generación menor. El slot seleccionado
permanece intacto hasta confirmar el nuevo. No se necesita un puntero mutable.
Igual generación con payloads diferentes es conflicto, no se elige por fecha.
`.next` nunca se adopta como catálogo confirmado ni se usa para borrar archivos.
Si existe un slot de formato futuro o ilegible por I/O, no reemplazarlo con una
generación antigua: modo diagnóstico/reconstrucción, sin mutaciones destructivas.

Si la escritura falla, leer el último slot válido; mostrar el fallo y mantener
base/copias. Al reiniciar, verificar ambos sobres y reconciliar referencias,
manifiestos, intenciones y bajas. Casos de recuperación:

- Solo un slot válido: usarlo y reconciliar archivos; reparar el otro con una
  nueva generación cuando el almacenamiento vuelva a estar disponible.
- Copia final con manifiesto válido no catalogada: incorporarla como `pending`
  tras comprobar ubicación/identidad y ausencia de baja; revalidar antes de uso.
- Referencia sin archivo, hash distinto o manifiesto dañado: mantener sus datos
  conocidos y marcar ausencia/daño; no borrarla ni darla por disponible.
- `.part`, directorio sin manifiesto o snapshot huérfano: incidencia incompleta
  o en cuarentena. Conservar el origen de intent si es verificable; de lo
  contrario desconocido y protegido. No promover por extensión o tamaño.
- Ambos slots dañados/ausentes con artefactos: reconstruir desde los manifiestos
  verificados y bajas duraderas, sin abrir la activa. Un hash del manifiesto no
  acredita SQLite: las entradas reconstruidas comienzan `pending`. Conservar
  archivos dañados para diagnóstico; no iniciar catálogo vacío silenciosamente.

La reconstrucción usa el máximo orden de todos los descriptores/intenciones/bajas
legibles más uno. Si hay orden/origen ambiguo o datos ilegibles, deshabilita poda
hasta resolverlo. Conserva una generación verificable o inicia una nueva solo
tras aislar ambos slots dañados; genera un `localRestoreEpoch` nuevo y marca
`syncContrastRequired = true` para no inventar continuidad con Drive.
La recuperación de archivos nunca consulta Drive ni crea una nueva base activa.

También con slots válidos, antes de reservar otro orden se reconcilian las
intenciones: `nextCreationOrder` debe superar todo orden ya persistido, aunque
el proceso muriese entre guardar intent y actualizar catálogo. Un orden repetido
entre IDs distintos se trata como ambiguo y suspende la poda, no se renumera una
copia publicada. No borrar intenciones desconocidas para resolver ese conflicto.

Una baja se registra primero en `tombstones/<backupId>.json`, sobre con
`kind = autofinance.localBackupDeletion`, `formatVersion = 1`, `backupId`,
`creationOrder`, `deletedAtUtc`, `reason` (`explicitUser` o `retention`) y
`restoreOperationId` (UUID solo para retención; `null` para baja expresa).
Después se confirma `deletionPending` en catálogo y se eliminan únicamente los
archivos del ID. Al terminar se retira la entrada en una nueva generación.
Se conservan las bajas indefinidamente para evitar que un catálogo anterior o
un escaneo resuciten una copia borrada. Una baja corrupta o contradictoria
produce cuarentena y aviso, nunca autoriza un borrado. Un fallo de borrado deja
`deletionPending`; se puede reintentar la baja ya autorizada, sin podar otras.

## Retención y espacio

**Manuales: conservación indefinida hasta baja expresa de ese ID por el usuario.**
No hay caducidad, cuota que las pode, deduplicación por hash ni conversión a
automáticas. Crear una copia manual no ejecuta retención.

**Automáticas: objetivo de tres copias válidas `preRestore` más recientes por
instalación**, entre todos los linajes. Se permite exceder tres durante una
operación, por restauraciones fallidas o si las protecciones impiden borrar.
Solo una restauración completada, reabierta, validada y confirmada duraderamente
autoriza la poda; cancelación, error o intercambio pendiente no la autorizan.
La próxima restauración satisfactoria puede podar el exceso acumulado, incluidos
respaldos de intentos fallidos; esos respaldos permanecen hasta entonces.

Antes de cada baja por retención, bajo exclusión:

1. Revalidar las copias que se conservarán; elegir las tres automáticas válidas
   de mayor `creationOrder`. Datos desconocidos/incompatibles no son candidatas
   de borrado. Bloquear poda si no se puede comprobar el conjunto o sus bajas.
2. Excluir siempre las manuales, la candidata en uso, el respaldo de una
   restauración no resuelta y los archivos originales aislados de una activa
   corrupta. Una automática no validada no cuenta entre las tres ni se elimina
   para aparentar cumplimiento.
3. Borrar solo automáticas válidas más antiguas fuera del conjunto protegido,
   una a una mediante baja duradera. **Nunca borrar la única copia válida del
   catálogo**: debe quedar al menos otra copia integralmente validada. La base
   activa, staging y una copia pendiente de validar no cuentan como superviviente.

La baja expresa también comprueba que no sea una copia en uso ni la última válida;
si lo es, exige crear/verificar otra antes de proceder. Bajo presión de espacio
se informa del bloqueo y se permite gestionar copias expresamente. No se podan
manuales, huérfanos o desconocidos para hacer sitio; no se restaura sin respaldo
previo cuando la activa puede abrirse. Los originales corruptos aislados no son
copias válidas ni entran en el límite de tres.

## Intercambio y señal local para sincronización

Se reserva `restore/<operationId>` para MA-TSK-055/056. El diario recuperable
debe conservar ID de candidata y respaldo, rutas privadas derivadas, fase y
epoch anterior/nuevo. Sus fases y reemplazo se concretarán en esos tickets;
no se implementan aquí. El arranque resuelve primero ese diario, después abre
la activa. Una operación pendiente protege todos sus archivos contra retención.
Si la activa no abre, se aíslan sus originales y sidecars sin destruirlos;
no se llama a la primitiva fingiendo una base nueva para obtener respaldo.

El linaje y la revisión financiera se restauran tal como están en la candidata;
no se incrementan artificialmente para representar el reemplazo. Cada éxito
local cambia `localRestoreEpoch` y marca `syncContrastRequired = true`, incluso
si coinciden `datasetId` y `revision` con los anteriores. Diario y catálogo deben
permitir completar esta marca tras reinicio antes de ofrecer escritura o éxito.
Un rollback confirmado conserva el epoch anterior; si no puede demostrarse qué
base quedó activa, se exige contraste. Catálogo perdido también exige contraste.

La futura sincronización consume la señal sin red automática. Solo su flujo
manual, tras contraste remoto confirmado, puede reconocer el epoch y limpiar
la marca; escribir una copia manual, editar datos o abrir la app no la limpia.
La revisión detecta ediciones posteriores; el epoch detecta reemplazos aunque
las revisiones coincidan. Sin estado/baseline verificable se comunica «pendiente
de contraste», nunca «igual a Drive».

| Identificador/versión | Qué representa |
|---|---|
| `formatVersion` | Contrato JSON local |
| `schemaVersion` | Estructura SQLite (`user_version`) |
| `datasetId` + `revision` | Linaje y mutación financiera confirmada de esa imagen |
| `backupId` / `creationOrder` | Artefacto local y orden de captura, sin equivalencia remota |
| `generation` / `localRestoreEpoch` | Escritura de catálogo / evento de reemplazo local |
| `Drive.version` | Cadena decimal remota de Drive, propiedad de la futura sincronización; nunca se deduce de ninguno de los anteriores |

El estado remoto conocido y las credenciales se guardan fuera de SQLite y del
artefacto local. Esta definición no cambia
[el contrato de copia remota de MA-TSK-048](../ep-005/copia-remota.md).

## Verificación y traspaso

[Casos de aceptación](casos-contrato.md) vincula cada criterio con resultados
esperados, puntos de interrupción y tickets que deben implementarlos. Esta
entrega define el contrato; no presenta esas garantías como ejecutadas en un
servicio EP-006 inexistente. No modifica esquema, puertos, SDK ni lockfile.
La evidencia local de calidad y sus límites se registra al final de ese documento.
