# MA-TSK-174 · Consulta de reales anuales

`createAnnualActualQuery(database: ..., invalidation: ...)` compone en app
el repositorio de movimientos existente, la gestión del árbol actual y
`SqliteReadUnitOfWork`, todos sobre la misma conexión. La consulta pública
está en `features/actual_spending/actual_spending.dart`. No cambia tablas,
migraciones, captura, pantallas ni enlaces.

## Lectura y consistencia

`await query.read(year)` admite años civiles 1–9999. Una sola transacción
lee primero identidad/revisión (`DatasetState`), después categorías y
`AnnualMovementTotalsReader.readYearTotals(year)`. Este puerto mínimo vive
en Movimientos y lo implementa `SqliteMovementRepository`: una consulta
agrupa por mes de fecha de valor y UUID/null, sobre todas las cuentas.
Reutiliza el filtro civil y `movement_subtotal` existentes; no carga registros
del año ni ejecuta doce consultas mensuales. La respuesta tiene como máximo
una entrada por categoría/mes con datos, incluidas las sumas netas cero.

El dominio reutiliza `CategoryGrouping.aggregateExact` para importes y
contadores. Esta extensión usa el mismo recorrido por UUID que `aggregate`,
sin cambiar el comportamiento de consumidores anteriores. Cada subtotal
directo se aporta una sola vez a cada antecesor, nunca a descendientes.
Las sumas intermedias usan `BigInt`; cada cifra publicada comprueba int64.
No se invierten signos por tipo categorial: se incluyen ingresos, salidas,
ahorro, transferencias y signos excepcionales.

La consulta no tiene caché ni escribe controles de mutación. Releer después
de guardar, borrar, reclasificar o importar; escuchar `query.invalidation.changes`
para catálogo/restauración. La generación se captura antes de la transacción
y se comprueba tras finalizarla: si cambia, se rechaza el resultado completo.
Tras reemplazar la base, app debe recomponer la consulta con la conexión nueva
y la invalidación compartida de la sesión, igual que EP-019/021.

## Contrato para interfaces y enlaces

- `AnnualActual.tree`: snapshot inmutable del árbol completo actual.
- `rows`: raíces activas y nodos con movimientos del año junto a sus antecesores,
  incluidos archivados, en preorden; hermanas por nombre y después UUID. Los
  descendientes sin movimientos no generan filas por sí solos. Nombres/rutas
  repetidos no fusionan nodos; las rutas y tipos efectivos son los actuales.
- `row.category` conserva `CategoryDetails`; `row.categoryId` identifica el UUID.
- `row.months[0..11]`: enero–diciembre; `cell.month` vale 1–12, `cell.direct`
  incluye solo el nodo y `cell.total` el nodo más descendientes.
- `row.directAnnualTotal` y `row.annualTotal`: sumas de las doce cifras propias
  y agregadas, respectivamente.
- `unclassified`: grupo aparte, con `category` y `categoryId` null; no crea una
  categoría. Sus cifras directas y agregadas coinciden.
- `AnnualActual.months[0..11]`: totales generales de raíces + Sin clasificar;
  `annualTotal` suma esos doce meses sin volver a sumar filas hijas.
- Cada `AnnualActualTotal` publica `amountCents`, `movementCount` y
  `hasMovements`. Mes sin datos: cero y contador cero. Neto cero con datos:
  cero con contador positivo; conserva presencia para acceder al origen.
- `datasetState` y `categoryGeneration` identifican el snapshot compartido.

El origen se conserva como año, mes, categoría UUID/null y alcance directo/rama,
con su número de registros. Los UUID de movimientos y su procedencia se leen
al abrir la lista paginada de EP-010, sin cargarlos en la matriz. MA-TSK-178
puede conectar estos alcances al contrato de enlaces existente. El total
general abre todos los registros del periodo; Sin clasificar filtra solo null.
No se incluyen servicios ni dependencias de presupuesto o fotos.

`AnnualActualFailure` distingue año inválido, datos incoherentes, invalidación,
overflow y persistencia, con mensaje español. Subtotales duplicados, meses
inválidos, contadores no positivos y categorías ausentes se rechazan; un error
no devuelve matriz parcial ni ceros ficticios. El árbol se valida también en
ramas vacías, con un máximo de tres niveles.

## Verificación

`test/actual_spending/annual_actual_query_test.dart` usa SQLite real y datos
sintéticos. Sus 13 pruebas cubren el caso F del CSV de EP-001, importación con
procedencia y duplicados legítimos, inmutabilidad y ausencia de escrituras,
directos en los tres niveles, signos excepcionales, dos cuentas y transferencia
neta cero, null, archivo/reactivación, homónimos, límites 1/9999 y doce meses,
602 registros sin paginación del agregado, corrección/borrado/reclasificación,
traslado/rename del histórico, cambio de conexión/identidad, fallos y reintento,
invalidación dentro y después de la transacción y overflow directo/rama/mes/año
con compensación exacta. La lectura funciona incluso eliminando las tablas de
presupuesto y fotos en una base sintética.

Una prueba sobre archivo abre una segunda conexión y comprueba que la escritura
competidora queda bloqueada entre la lectura del árbol y la agregación anual.
La siguiente consulta ve juntos el nombre, mes, cifra y revisión nuevos.

El caso F conserva diez movimientos originales y devuelve enero **+1.229,75 EUR**,
febrero **+1.099,90 EUR**, marzo–diciembre **0,00 EUR** y anual **+2.329,65 EUR**.
Arquitectura y consumidores anteriores de CategoryGrouping pasan junto con las
13 pruebas nuevas (18 pruebas en total).

Comprobaciones locales del 2026-10-12 con Flutter 3.47.0 / Dart 3.13.0:

- `flutter --version`, `check-toolchain.ps1` y `pub get --enforce-lockfile`:
  correctos; SDK y lockfile sin cambios.
- `check-quality.ps1`: formato de 375 archivos sin cambios y análisis sin
  incidencias. La batería global finaliza con **1.629 pruebas correctas y
  cuatro fallos** en recorridos existentes: presupuesto anual Windows
  (pantalla aún muestra la partida tras eliminar), Estado mensual Windows
  (lectura nula), recuperación local EP-001 (timeout de 30 segundos) y rollback
  de recuperación local (conexión cerrada tras el fallo anterior).
- Repetición de los cuatro casos fallidos con `--concurrency=1`: **cuatro
  pruebas correctas**, sin cambios en esos módulos. Los fallos globales no se
  reprodujeron de forma aislada; esta repetición no convierte la batería
  global en una ejecución correcta ni demuestra que deje de ser intermitente.
- Las cuatro variantes de `environment_bootstrap_test.dart` (development,
  test, production e invalid-synthetic) pasan por separado; el fallo global
  impedía que `check-quality.ps1` llegara a esta fase.
- `git diff --check`: correcto.

Se consultó MA-TSK-174 en la API local de Epic Board antes de implementar.
La entrega excluye cambios concurrentes de README, sincronización y
prototipos/fixtures de otras épicas. No se requieren builds ni verificación
nativa: el cambio solo añade dominio y composición de lectura, sin plataformas
o pantallas. La implementación de interfaces y enlaces permanece en sus tickets.
