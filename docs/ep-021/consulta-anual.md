# MA-TSK-166 · Proyección de presupuesto anual

## Composición y lectura

`createAnnualBudgetQuery(database: ..., invalidation: ...)`, en `lib/app`,
compone los repositorios existentes de presupuesto y categorías y
`SqliteReadUnitOfWork` sobre la misma conexión. El dominio se publica desde
`features/budget/budget.dart`; no se añaden tablas, migraciones ni operaciones
de captura. No consulta cuentas, movimientos o fotos.

`await query.read(year)` admite años 1–9999. En una única transacción lee
primero `DatasetState` (identidad y revisión), después el árbol actual y una
sola vez `BudgetRepository.readYear(year)`, sin filtrar por marca de ingreso.
No realiza doce consultas mensuales ni escribe controles de mutación. La
generación de invalidación se captura antes de la lectura y se contrasta tras
terminar la transacción; un cambio descarta el resultado con error tipado.

La consulta no tiene caché. Sus consumidores deben releer tras una captura,
edición, borrado o importación y escuchar `query.invalidation.changes` para
los cambios del árbol/restauración. Después de restaurar, app recompone la
consulta con la nueva conexión y la invalidación compartida de la sesión.

## Contrato para las interfaces y enlaces

- `AnnualBudget.rows`: árbol activo completo, incluidas categorías sin
  partidas, más archivadas que tengan partidas del año y todos sus antecesores.
  Preorden; las hermanas se ordenan por nombre y después UUID. No se incluyen
  ramas archivadas vacías ni partidas de otros años.
- Cada fila conserva `categoryId`, `CategoryDetails` y la ruta/jerarquía/tipo
  actuales. Los nombres y las rutas repetidos no identifican filas.
- `row.months[0..11]`: enero–diciembre. `cell.ownBudget` contiene la partida
  original con UUID y procedencia; `ownAmountCents` es nullable. Si falta la
  partida propia, sigue siendo «sin presupuesto» propio aunque haya agregado.
- `cell.total`: suma de la partida propia y las de todos los descendientes,
  con `budgets`, `budgetIds`, `budgetCount` y `hasBudget`. Sirve para abrir
  exactamente las partidas que originan el subtotal. Una partida de padre no
  se reparte ni crea cifras propias o agregadas en hijos.
- `row.ownAnnualTotal`: suma de sus propias partidas de los doce meses.
  `row.annualTotal`: suma de sus agregados de los doce meses.
- `AnnualBudget.months[0..11]`: total general mensual sumando únicamente las
  raíces. `annualTotal` suma esos doce meses; nunca vuelve a sumar padre+hijos.
  `datasetState` y `categoryGeneration` identifican la lectura compartida.

Las listas son inmutables. Ausencia aporta cero aritmético con `hasBudget`
falso y sin UUID. Una partida explícita de cero conserva UUID/presencia. Un
agregado neto cero con partidas conserva todos sus orígenes y `hasBudget`
verdadero. Los importes se suman algebraicamente en céntimos; la marca de
ingreso no cambia su signo. Se usa `BigInt` durante la suma y se comprueba
int64 al publicar cada cifra, evitando overflow y redondeos intermedios.

`AnnualBudgetFailure` distingue año inválido, datos inválidos, invalidación,
overflow y fallo de persistencia, con mensaje español. Un fallo no devuelve
una matriz parcial o ceros ficticios. Se rechazan UUID duplicados, dos
partidas por nodo/mes, categorías inexistentes, partidas de otro año y
solapamientos padre/descendiente; no hay desglose o sustitución automática.

## Verificación y alcance

`test/budget/annual_budget_query_test.dart` usa SQLite y datos sintéticos.
Comprueba árbol completo, orden/UUID/rutas repetidas, tres niveles,
ausencia/cero/neto cero, cambio de nivel por mes, totales sin doble conteo,
archivadas y antecesores, reactivación, rename/reparent histórico, límites
civiles, corrección/borrado sin caché, errores, overflow e invalidación.

El CSV sintético EP-001 reproduce 48 partidas, doce totales mensuales de
**+1.100,00 EUR** y un total anual de **+13.200,00 EUR**, con procedencia
intacta. Otra prueba intenta adquirir escritura desde una segunda conexión
entre la lectura del árbol y `readYear`, verifica el bloqueo y la revisión,
y comprueba que la siguiente consulta ve conjuntamente la nueva ruta y cifra.
El lector instrumentalizado exige una sola llamada anual y rechaza llamadas
mensuales o escrituras.

Este ticket entrega la consulta y su factoría para las interfaces posteriores;
no implementa pantallas, navegación, propuesta ni edición anual. Se utiliza el
ticket completo facilitado por el usuario: esta sesión no dispone de herramienta
Epic Board y no se ha consultado ni modificado el tablero.

Comprobaciones locales del 2026-10-11, con Flutter 3.47.0 y Dart 3.13.0:

- `flutter --version`, `check-toolchain.ps1` y `pub get --enforce-lockfile`:
  correctos, sin actualizar SDK ni lockfile.
- `check-quality.ps1`: formato de 357 archivos sin cambios y análisis sin
  incidencias. La batería global termina con 1.572 pruebas correctas y un
  fallo en `movement_form_test.dart`, «Fallo al guardar conserva campos y
  permite reintentar» (resultado de guardado nulo, línea 227).
- Repetición aislada con `--concurrency=1` de la consulta anual, el archivo
  completo de formulario de movimientos y arquitectura: **32 pruebas
  correctas**, incluidas las **13 pruebas anuales** y la prueba que había
  fallado. No se modificó código de movimientos. La ejecución global se
  registra como fallida; la repetición no acredita que deje de ser intermitente.
- Las cuatro variantes de `environment_bootstrap_test.dart` (development,
  test, production e invalid-synthetic) pasan por separado, ya que el fallo
  global impidió que el script llegara a esa fase.

No se realizaron builds ni comprobaciones en dispositivos nativos: el cambio
añade dominio/composición de consulta y no afecta plataformas o pantallas.
La entrega excluye los cambios concurrentes presentes en README,
sincronización y prototipos/fixtures de otras épicas.
