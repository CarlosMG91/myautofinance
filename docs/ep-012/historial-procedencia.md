# MA-TSK-111 · Historial de lotes y procedencia

Ticket MA-TSK-111 y requisito MA-TSK-107 contrastados el 2026-10-07 mediante
lectura de `http://localhost:4310/api/data`, tablero **My autofinance**.
MA-TSK-107 está completado. Se reutilizan los originales y metadatos de
[MA-TSK-110](confirmacion-atomica.md), las referencias de EP-004 y los contratos
de movimientos/presupuestos. No se cambia el estado del tablero.

## Puerto y composición

`importing.dart` exporta `ImportHistoryRepository`, sus páginas y cursores y
`ImportRowHistory`. Es un puerto separado de confirmación para poder inyectar
solo lectura en la UI. App aporta `SqliteImportHistoryRepository(database)`;
ningún módulo importa adaptadores de app ni se añaden dependencias al grafo.

```dart
final history = SqliteImportHistoryRepository(database);
final batches = await history.listBatches(limit: 100);
final nextBatches = batches.next == null
    ? null
    : await history.listBatches(limit: 100, cursor: batches.next);
final batch = await history.getBatch(batchId);
final rows = await history.listRows(batchId, limit: 100);
final provenance = await history.getRow(record.importRowId!);
```

Cada lote conserva UUID, fecha de confirmación, nombre original, origen,
versión común, versión del lector cuando existe, SHA-256 y conteos originales
de REAL/PRESUPUESTO. Los conteos nuevos proceden de metadatos inmutables; en
lotes antiguos se cuentan las identidades de origen, nunca los destinos vivos.

Cada fila muestra UUID de origen, UUID de lote, ordinal y tipo.
`original` reconstruye la interpretación guardada con los tipos públicos
existentes: campos nombre/valor ordenados y repetidos, texto exacto, concepto,
discrecionalidad, importe original/interno, convención de signo y referencias
de cuenta/categoría originales. Los importes decimales se convierten a int64
sin pasar por double; el interno debe coincidir con la convención almacenada.
Una versión de payload desconocida falla expresamente; no se inventa un original.

`currentMovement` o `currentBudget` es una lectura separada del registro actual,
con UUID enlazable y sus referencias de procedencia. Corregir concepto, importe,
fecha, cuenta o categoría no modifica `original`. `isDeleted` indica ausencia
del destino, manteniendo la identidad y originales de la fila. Un lote anterior
sin payload devuelve `original == null`: la UI debe indicar «Original no
disponible», incluso si el registro actual existe. Una lista de campos vacía
guardada es distinta de originales no disponibles.

## Paginación y persistencia

- Páginas inmutables de 1 a 500 elementos (100 por defecto); se lee como máximo
  `limit + 1` para detectar continuación. No hay tope total de lotes o filas.
- Lotes por orden de inserción/confirmación descendente. El cursor conserva
  UUID del último lote y resuelve su rowid vigente: no expone un rowid persistido,
  ni depende del reloj o de desempates entre timestamps. Nuevas confirmaciones
  no desplazan las páginas iniciadas. Se conserva el orden tras `VACUUM`.
- Filas por ordinal ascendente, con cursor ligado al UUID del lote. Usa el índice
  único existente `(batch_id, source_ordinal)`; los JOIN a originales y destinos
  usan sus índices únicos de origen. Correcciones/borrados no desplazan las filas.
- Cada página realiza una consulta con JOIN, sin consultar el destino fila por
  fila ni cargar todo el lote. Los conteos heredados solo recorren sus propias
  identidades de origen mediante el índice existente.
- UUID inexistente: detalle nulo o página vacía. Límites fuera de rango, cursor
  vacío de lotes o cursor de filas inválido/de otro lote: `ArgumentError`.
- Los datos actuales reflejan el estado en la consulta de cada página; no son
  una copia congelada entre páginas. Tras reemplazar/restaurar la base, el
  consumidor debe reiniciar cursores y recargar contexto, como el resto de vistas.

Son SELECT exclusivamente: no modifican revisión, seguimiento de mutaciones ni
tablas. No hay migración ni índices/esquema nuevos. No se guardan bytes del
archivo, sesiones canceladas o intentos fallidos. No hay restaurar fila ni
deshacer lote. La confirmación existente conserva SHA-256 incluso tras borrar
un destino: repetir bytes renombrados no recrea ni revierte registros.

La pantalla común y sus rutas corresponden a MA-TSK-112; lectores CSV/XLS a
EP-013/014. Este ticket entrega las consultas reales que consumirán esos flujos.

## Verificación

`test/importing/sqlite_import_history_test.dart` usa archivos SQLite temporales
y datos sintéticos. Sus siete pruebas cubren vacío/inexistentes, límites/cursores,
reapertura, columnas repetidas y texto exacto, int64 mínimo, presupuestos
normalizados/cero, selección bancaria global y versiones, registros corregidos
y borrados de ambos tipos, conteos originales, repetición renombrada sin recrear,
lotes antiguos sin originales, cancelación y fallo atómico sin nuevos lotes.

Recorre 1.205 filas idénticas con UUID independientes y 107 lotes, incluyendo una
confirmación nueva y `VACUUM` entre páginas y correcciones/borrados entre páginas
de filas. Compara todas las tablas, revisión y seguimiento de mutaciones antes
y después de lecturas; comprueba uso de índices para filas y destinos.

Resultados dirigidos: 85 pruebas de importación y arquitectura correctas.
`scripts/check-quality.ps1` completo correcto con Flutter 3.47.0 / Dart 3.13.0:
dependencias con `--enforce-lockfile`, formato sin cambios, análisis sin
incidencias, 1.121 pruebas aprobadas y las cuatro variantes APP_ENV correctas.
`node docs/ep-001/verificar-casos.mjs`: casos financieros conservados.
La ejecución inicial dentro del sandbox no pudo abrir los bloqueos de fichero
SQLite ni consultar pub.dev; se repitió con los permisos adecuados.

No se modifican plataformas, SDK ni lockfile. No se ejecutan builds ni recorrido
nativo Windows/Android: este ticket cambia contratos de lectura y adaptador
SQLite; la integración visual/nativa corresponde a MA-TSK-112/114. Los cambios
concurrentes de Drive, README y diseño EP-008 quedan fuera de la entrega.
