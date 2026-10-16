# MA-TSK-219 · Contrato de exportación y portabilidad v1

Contrato de EP-027, decisiones confirmadas el 2026-10-16. Se ha consultado el
ticket íntegro proporcionado por el usuario; no hay conector Epic Board
disponible en esta sesión y no se acredita una actualización del tablero.
Este ticket publica el contrato y sus casos comprobables. Los exportadores,
guardado nativo, guía de recuperación y UI corresponden a los siguientes tickets.

## Dos acciones y tres formatos independientes

| Acción/formato | `kind` | `formatVersion` | Contenido |
|---|---|---|---|
| Exportar datos | `autofinance.dataExport` | entero `1` | ZIP de siete CSV, `diccionario.json`, `LEEME.md`, `manifest.json` |
| Exportar copia completa | `autofinance.portableBackup` | entero `1` | ZIP de `autofinance.sqlite`, `LEEME.md`, `manifest.json` |
| Copia privada EP-006 | `autofinance.localBackup` | entero `1` | Directorio privado y manifiesto con sobre `payload`/`payloadSha256`, gestionado por su catálogo |

Los dos manifiestos públicos son JSON directos, UTF-8 sin BOM, sin sobre privado.
No se aceptan como copias privadas ni se registran en su catálogo. No se cambia
el formato, la retención o el restaurador de EP-006. `formatVersion` versiona
cada `kind`, independientemente de `schemaVersion`. Cualquier cambio de columnas,
semántica, null, dialecto o campos del manifiesto exige nueva versión; v1 rechaza
campos desconocidos, claves JSON duplicadas, versiones/kinds no reconocidos.
Los formatos futuros se conservan sin reinterpretarlos como v1.

El [diccionario normativo](diccionario-v1.json) fija orden, tipos, nullabilidad,
procedencia y claves. El [esquema JSON](manifest-v1.schema.json) fija la estructura
de los manifiestos. Este documento fija las restricciones semánticas adicionales.
`diccionario.json` dentro del ZIP será una copia exacta de `diccionario-v1.json`.

## Captura coherente y ámbito financiero

Ambas acciones solicitan **una** imagen a `LocalBackupSource.createConsistentBackup`,
implementado por `LocalDatabaseStore` en EP-004. Toda lectura, catálogo, revisión,
conteo y hash procede de esa imagen terminada y validada; jamás se mezclan con
lecturas posteriores de la base viva. Confirmar `datasetId`/`revision` de
`LocalBackup.state` contra `database_state` de la imagen. Leer `application_id`
y `user_version` en ella y contrastar con la política vigente del código
(`lib/core/persistence/local_database_format.dart` y `schema_policy.dart`).
En esta revisión son AFNC `1095126595` y esquema **8**; no copiar el 6 histórico
de la documentación EP-006 ni fijar el 8 en el futuro exportador.

No añadir otro motor de snapshot, copiar la base viva, ni exportar WAL/SHM/journal,
TEMP, sesión, credenciales, configuración de instalación o estado Drive. Crear
staging propio y destino nuevo; publicar solo después de validar archivos y ZIP.
Cancelar o fallar conserva base, copias privadas y destinos previos. La gestión
de temporales solo afecta a los creados por la operación, nunca al catálogo.
No se añade envío automático, cifrado ni acceso root Android.

La copia portable conserva **todos** los objetos y filas de la SQLite financiera
validada: `database_state`, catálogos, movimientos, presupuestos, cabeceras/valores
patrimoniales y tablas de procedencia (`import_batches`, `import_rows`,
`import_batch_metadata`, `import_row_originals`). Los originales por fila ya
persistidos permanecen en esa base completa; no se adjuntan XLS/CSV bancarios ni
extractos originales completos. No se redacta ni reconstruye una SQLite parcial.

## Selección de datos legibles y contexto

`filter.mode=all`: todo el histórico, `fromMonth` y `throughMonth` nulos.
`filter.mode=months`: ambos meses `YYYY-MM-01`, límite inicial <= final,
inclusivos, sin periodos parciales. Los movimientos se filtran por **fecha de
valor**: desde el primer día inicial hasta el último día final inclusive,
independientemente de creación, importación o edición. Presupuestos y cabeceras
de fotos se seleccionan por su mes; se incluyen todos los valores de esas
cabeceras. Para `9999-12-01` comparar año/mes sin calcular el año 10000.
No se aplica el estado de filtros de otras pantallas, texto, categoría o cuenta.

Los tres archivos de contexto (`cuentas`, `categorias`, `liquidez_cuentas`)
incluyen **todos** sus registros en la imagen, sin filtro temporal ni exclusión
de archivados/bajas. Es una decisión deliberada de v1: garantiza referencias,
antecesores, cuentas esperadas sin valoración y clasificación histórica incluso
con selección vacía. Incluye contexto no utilizado y anterior/posterior al rango;
el LEEME debe advertirlo antes de compartir. No incluye flujos o fotos fuera del
rango para completar ese contexto. Se conservan los límites originales de los
periodos de liquidez, sin recortarlos. Vigencia de cuenta: alta y baja inclusivas;
liquidez: desde inclusivo, hasta exclusivo; fin nulo significa abierto. Las deudas
no tienen periodos de liquidez.

Orden estable: movimientos `(fecha_valor,id)`; presupuestos `(mes,id)`;
fotos `(mes,id)`; valores `(foto_id,cuenta_id,id)`; cuentas/categorías `(id)`;
liquidez `(cuenta_id,desde_mes,id)`. Comparaciones binarias de UUID ASCII,
fechas ISO y meses. Cabecera siempre, también con cero registros.

## Valores, relaciones y ausencia

Cada registro persistido aparece una vez, sin agregación, deduplicación por
contenido ni creación de filas de relleno. Identidades UUID minúsculas
`8-4-4-4-12` preservadas sin exigir variante nueva a identidades existentes.
`exportId` sí es un UUID v4 nuevo. Nombres y rutas son contexto de la captura,
no una reconstrucción de nombres históricos: el esquema no tiene ese historial.

Importes EUR: texto decimal exacto obtenido del INTEGER de céntimos mediante
aritmética entera; punto, dos decimales, sin símbolo/agrupación/`+`/exponente,
cero `0.00` (nunca `-0.00`). Todo el rango int64: `-92233720368547758.08` a
`92233720368547758.07`; no pasar por `double`, `Number` ni valor absoluto int64
del mínimo. Movimiento no admite cero. Presupuesto admite cero explícito;
signo igual al interno, incluso ingreso negativo, ahorro o transferencias.
**No invertir presupuestos como el CSV histórico EP-013/EP-001**. Valor de foto
no negativo; deuda mantiene magnitud positiva, se resta solo en una lectura
patrimonial completa. No se calculan saldos desde movimientos.

`categoria_id` nulo significa real **sin clasificar**, no una categoría creada
ni ingreso inferido por signo. `clasificacion` lo explicita como `sin_categoria`
o `categorizado`. Presupuesto siempre referencia categoría. Categorías conservan
padre, raíz, profundidad, marca de ingreso solo en raíz y tipo efectivo heredado.
`ruta_ids` y `ruta_nombres` son arrays JSON de raíz a nodo dentro de la celda CSV:
sin ambigüedad si un nombre contiene `/`, `;` o coincide con un hermano.
No identificar registros por nombre ni repetir cantidades por antecesor.

`fotos.csv` contiene **solo cabeceras existentes**, aun vacías. `estado` reproduce
la lectura EP-017: `absent` si no hay valores, `incomplete` si falta alguna cuenta
vigente, `complete` en otro caso. `cuentas_esperadas`, `valores_registrados` y
`cuentas_pendientes` son conteos exactos; las esperadas son las fichas de cualquier
tipo vigentes en ese mes y las pendientes son esperadas sin valor. Una cabecera
vacía con cero cuentas sigue `absent`. Un mes sin cabecera no tiene fila y es
foto ausente; no se inventa una cabecera ni un cero. No hay columna de patrimonio
o subtotal: una foto incompleta jamás presenta su suma parcial como patrimonio.
`valores_fotos.csv` conserva cada UUID/valor individual incluido `0.00`.
Una partida ausente tampoco equivale a presupuesto explícito cero.

Discrecionalidad se conserva literalmente, incluidos vacío, espacios y Unicode,
sin convertirla en enum. `fila_importacion_id`, `lote_id`, `ordinal_origen` y
`tipo_origen` se obtienen por LEFT JOIN con `import_rows`/`import_batches` y se
conservan cuando existen; las cuatro son nulas en registros manuales. El ordinal
es de origen, no la línea física actual del CSV multilínea. No se adjuntan payloads
originales, rutas, nombres de archivos bancarios ni extractos a la exportación CSV.

| Referencia CSV | Destino |
|---|---|
| `movimientos.cuenta_id`, `valores_fotos.cuenta_id`, `liquidez_cuentas.cuenta_id` | `cuentas.id` |
| `movimientos.categoria_id`, `presupuestos.categoria_id` | `categorias.id` (nula solo en reales sin clasificar) |
| `categorias.padre_id`, `raiz_id`, elementos de `ruta_ids` | `categorias.id` (padre nulo en raíz) |
| `valores_fotos.foto_id` | `fotos.id` |
| `fila_importacion_id`, `lote_id` | Identificadores de procedencia de la SQLite; no hay CSV de lotes/filas originales |

El consumidor puede resolver las relaciones financieras dentro del ZIP. Las
referencias de procedencia son opacas para CSV y no prometen acceso al extracto
original; la copia SQLite completa sí conserva las tablas de procedencia.

## Dialecto CSV y lectura como texto

UTF-8 sin BOM; separador `;`; registros terminados en CRLF incluido el último.
Cabeceras exactas sin comillas, orden del diccionario. Todo valor **no nulo** se
escribe entre comillas dobles, incluso números; comillas interiores se duplican.
El null SQL es campo vacío **sin comillas**; cadena vacía es `""`.
El lector que necesite distinguirlos debe conservar si el campo estaba
entrecomillado. `NULL`, `null` o `\N` entrecomillados son textos literales.
No recortar, normalizar Unicode, sustituir CR/LF internos ni usar escapes de
barra inversa CSV: los saltos originales permanecen dentro de las comillas.
El escape JSON se usa solo en campos de tipo array JSON y en documentos JSON.

Un texto que empieza por `=`, `+`, `-`, `@`, tabulador o retorno sigue siendo el
texto original; entrecomillar **no impide** que una hoja de cálculo lo ejecute.
No añadir apóstrofos ni mutilar conceptos para resolverlo. LEEME obligatorio:
abrir primero con editor de texto o importar desde la herramienta de texto/CSV
de la hoja, seleccionar UTF-8, `;` y calificador `"`, desactivar detección de
fórmulas/tipos y fijar **todas las columnas como Texto antes de cargar**. No abrir
con doble clic. Si la herramienta no permite garantizarlo, usar un editor/lector
CSV que no evalúe fórmulas. Fechas, UUID y grandes números también se importan
como texto. La distinción null/cadena vacía requiere lector sensible a comillas;
una hoja que las colapsa sirve para consulta visual, no para análisis de ausencia.
Convertir importes después solo con decimal exacto o céntimos enteros.

## Manifiestos públicos v1

Campos comunes obligatorios: `kind`, `formatVersion`, `exportId`, `createdAtUtc`
(UTC `YYYY-MM-DDTHH:mm:ss.SSSZ` al terminar captura), `datasetId`, `revision`,
`applicationId`, `schemaVersion`, `currency` (`EUR`), `filter`, `dictionary`,
`files`, `databaseTables`. Sin claves adicionales. Fecha no es la del último
movimiento. Esquema e identidad describen la imagen capturada.

`revision`, `rowCount` y `sizeBytes` son cadenas decimales canónicas int64 no
negativas sin ceros iniciales, hasta `9223372036854775807`; tamaño >0. También
son texto exacto los conteos de fotos y ordinales CSV (ordinal >=2). Ningún
consumidor debe decodificarlos como coma flotante; validar límite además del
patrón del esquema JSON. `formatVersion`, `schemaVersion` y `applicationId`
son enteros JSON pequeños. Overflow provoca error, nunca redondeo o reinicio.

Cada entrada `files` lleva `path`, `mediaType`, `rowCount`, `sizeBytes`, `sha256`.
Lista en orden lexicográfico binario de path. Hash SHA-256 hexadecimal minúsculo
de **todos los bytes descomprimidos finales**, incluido CRLF/BOM si lo hubiera;
no reserializar antes de verificar. Conteo CSV excluye cabecera y cuenta registros
lógicos, no líneas físicas. `rowCount=null` para JSON, Markdown y SQLite.
`manifest.json` no se lista ni se auto-hashea; todos los demás archivos están
listados exactamente una vez. Hashes detectan corrupción, no autentican autoría.

Datos: exactamente siete CSV más `diccionario.json` y `LEEME.md`;
`dictionary="diccionario.json"`, `databaseTables=[]` y filtro `all`/`months`.
Copia: exactamente SQLite y `LEEME.md`; `filter=null`, `dictionary=null`.
`databaseTables` lista cada tabla de usuario de la imagen (`sqlite_*` excluidas)
en orden de nombre, con `name` y `rowCount` exactos leídos de la misma imagen.
No pierde `import_row_originals` aunque CSV no lo publique. Verificar metadatos
SQLite, tablas/conteos y `database_state` contra manifiesto; la integridad del
archivo sigue exigiendo validación SQLite además del hash.

ZIP estándar sin contraseña, entradas regulares, sin duplicados (también
colisiones de mayúsculas en Windows), enlaces, rutas absolutas, unidades, URI,
`..`, barras inversas o directorios anidados. Solo nombres literales anteriores.
No hay otro ZIP interno ni sidecars. Validar inventario, tamaños, conteos y hashes
antes de publicar o extraer. Guardado/recuperación deben imponer límites de
recursos coherentes y rechazar tamaños descomprimidos que no concuerden.

## Lectura independiente y límites de la entrega

La recuperación acordada valida la copia portable y la extrae a **carpeta nueva
Windows**, sin reemplazar la instalación, migrar la imagen ni registrar copias
privadas. Una copia creada en Android tiene el mismo formato y puede consultarse
en Windows. Tras verificar, SQLite estándar en solo lectura permite consultar
tablas, `PRAGMA application_id`, `PRAGMA user_version`, `PRAGMA integrity_check`,
`PRAGMA foreign_key_check` y `SELECT dataset_id,revision FROM database_state`.
No necesita Autofinance, root Android ni funciones de búsqueda de la aplicación
para SELECT directos de las tablas. La guía T07 concretará herramientas y pasos.
El `LEEME.md` de la copia portable debe indicar que contiene toda la base
financiera, sin filtro temporal; explicar verificación de manifiesto/hashes y
lectura de SQLite en carpeta nueva, y advertir que no sustituye una instalación.
No reutilizar el LEEME de CSV como instrucciones de recuperación de SQLite.

No se promete reconstrucción desde CSV, reimportación compatible con EP-013,
restauración de instalación, fusión, SQLite parcial, XLSX/PDF o envío/Drive
automático. UI T06 requiere exportadores/guardado y aprobación explícita T05;
publicar este contrato no acredita esa aprobación ni la aceptación visual
EP-026. La verificación real Windows/Android y lectura independiente de archivos
producidos por la app corresponde al cierre T08, no se infiere de estos ejemplos.

## Casos ejecutables

`node docs/ep-027/verificar-contrato.mjs` valida diccionario, ejemplos, manifiesto,
relaciones, estados de foto, precisión int64, filtros y preservación de texto
contra una base SQLite sintética creada con el esquema real. No implementa un
exportador de producto ni modifica una base personal. Véase
[evidencia y traspaso](verificacion.md).
