# MA-TSK-158 · Consulta de Estado del mes

Contrato financiero: EP-001 §5.1 y casos B, C, J, K y L. El ticket y sus
dependencias se han consultado en Epic Board, tablero My autofinance.

## Entrada y resultado

`MonthlyStatusQuery.read(BudgetMonth)` vive en el dominio de `monthly_status`
y se exporta desde su entrada pública. `createMonthlyStatusQuery` compone
repositorios SQLite, catálogo EP-008 e invalidación compartida por constructor,
sobre una misma conexión ya abierta. No depende de fotos patrimoniales ni de navegación.

La instantánea `MonthlyStatus` conserva mes, árbol actual completo, filas en
preorden por nombre/UUID, `DatasetState` y generación del catálogo. Las filas
incluyen raíces activas y categorías con movimientos o partidas del mes,
junto a sus antecesores, aunque estén archivadas. Un hijo sin registros no
aparece solo porque su padre esté presupuestado. Los homónimos se identifican
por UUID; la ruta y el tipo efectivo corresponden al árbol actual.

Cada fila proporciona `ownBudget` (partida explícita o null),
`actualDirectCents`, `directMovementCount` y `totals`. Las cifras agregadas son
`plannedCents`, `actualCents` y `differenceCents = actualCents - plannedCents`.
`hasOwnBudget` distingue presencia propia y `totals.hasBudget` presencia en
la rama. Un cero explícito mantiene su partida y contador: aporta cero, pero
no se etiqueta «sin presupuesto». Una partida padre no se reparte a sus hijos.

`unclassified` no tiene UUID ni se incorpora al árbol. Su previsto es cero y
`hasBudget` siempre es false; la interfaz puede mostrarlo cuando
`hasMovements` sea true. El total suma exclusivamente las raíces y este grupo.
Los contadores mantienen el origen de movimientos compensados y transferencias
entre cuentas; no deduplican movimientos por concepto, fecha o importe.

## Lectura y errores

`MonthlyMovementTotalsReader` es un puerto adicional de movimientos para
informes, sin alterar los consumidores de `MovementRepository`.
`SqliteMovementRepository.readMonthTotals` ejecuta un `GROUP BY category_id`
con contador y el agregado exacto `movement_subtotal` de EP-010. Utiliza el
filtro civil existente, todas las cuentas y sin cargar movimientos completos.
Presupuesto reutiliza `BudgetRepository.list` y mantiene sus partidas originales.
El número de resultados reales depende de las categorías presentes, no del
número de movimientos. No cambia el esquema ni requiere generación Drift.

`SqliteReadUnitOfWork` usa la transacción Drift directamente, evitando las
escrituras de control de `LocalDatabase.run`. Drift 2.35.1 inicia con
`BEGIN IMMEDIATE`: reserva la conexión/escritura mientras se leen revisión,
árbol, partidas y sumas, pero la consulta no modifica tablas, ni siquiera TEMP.
Otra conexión no puede confirmar una mutación entre esas lecturas. La prueba
mide `total_changes()` y revisión, además del bloqueo y su liberación.

La agregación de ramas y total utiliza BigInt y comprueba el resultado int64
de cada cifra, incluida la diferencia, sin desbordamiento intermedio. Un
desbordamiento de suma directa SQLite produce `MovementTotalsOverflow`; la
consulta lo traduce a `MonthlyStatusFailureCode.overflow`, igual que una cifra
agregada fuera de rango. Los fallos
técnicos producen `persistence`, sin sustituirlos por ausencia ni cero. Los
datos de entrada incoherentes producen `invalidData`.

No hay caché. Después de guardar/importar, el consumidor relee el mes; después
de cambios del catálogo o restauración usa la invalidación de sesión. Si cambia
la generación durante la consulta, se descarta el resultado con `invalidated`.
Tras reemplazar la base, app debe resolver la conexión activa y recomponer la
consulta con la misma invalidación, siguiendo `LocalBackupSession`. Una
instantánea anterior permanece inmutable y conserva su identidad/revisión.

## Verificación

- `test/monthly_status/monthly_status_query_test.dart`: CSV sintético aprobado
  B/C, variantes J/K y caso L; padres y hojas, presencia/ausencia y cero,
  homónimos/archivo, todas las cuentas, fechas civiles y límites 1/9999,
  relectura tras edición/traslado y reemplazo de conexión, 601 movimientos,
  desbordamientos y compensación exacta, error de lectura y ausencia de writes.
- `test/monthly_status/monthly_status_snapshot_test.dart`: archivo SQLite con
  conexiones independientes, snapshot y revisión coherentes, relectura tras
  commit, invalidación durante lectura y liberación tras fallo.
- Regresión de `movement_search_test.dart` y fronteras de `architecture_test.dart`:
  ejecución específica inicial de 23 pruebas correcta; la suite completa
  incorpora también la ampliación de desbordamiento de previsto/total,
  sumando 14 pruebas nuevas de Estado.
- `./scripts/check-quality.ps1` correcto el 2026-10-10: SDK fijado, resolución
  con `--enforce-lockfile`, formato sin cambios, análisis sin incidencias,
  1.524 pruebas correctas y cuatro ejecuciones adicionales de arranque para
  development/test/production/invalid-synthetic.
- `git diff --check` correcto. El lockfile y las versiones se conservan.

El ticket entrega consulta y composición; las vistas PC/Android y sus enlaces
pertenecen a los otros tickets de EP-019. No modifica plataformas y no requiere
builds nativos. Las pruebas de reemplazo ejercen la recomposición de la consulta;
no vuelven a verificar el protocolo de restauración de EP-006/007.
