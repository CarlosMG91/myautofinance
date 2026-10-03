# MA-TSK-080 · Reorganización atómica con histórico

Implementa las reglas de [MA-TSK-079](arbol-categorias.md) y los
[casos L–O](../ep-001/casos-referencia.md), sin pantallas ni cambios de navegación.
Se ha consultado el ticket íntegro facilitado por el usuario. No hay conector
Epic Board disponible; no se cambia su estado administrativo.

## Contrato del adaptador

`CategoryRepository.edit` conserva UUID y referencias al cambiar de padre.
Toda la rama adopta el tipo efectivo de su nueva raíz sin escribir movimientos,
partidas, procedencia ni fotos. Al promover un descendiente, `isIncome: null`
conserva el tipo anterior; también se admite indicarlo explícitamente si coincide.
Elegir un tipo distinto se rechaza. Una raíz usada sigue sin admitir cambio
directo de tipo, incluso con referencias únicamente históricas o archivadas.

La validación, escritura y revisión comparten la transacción de EP-004. Se
comprueban destino existente y activo, ciclos y profundidad de todo el subárbol.
El traslado no reactiva categorías. Los presupuestos se validan contra todos
los ancestros del árbol propuesto y todos los meses, sin filtrar año, archivo
ni importes de cero. Hermanas y meses distintos siguen siendo válidos.

Un solapamiento lanza `CategoryFailure` con `budgetConflicts`: lista inmutable
de `CategoryBudgetConflict`, con mes ISO `YYYY-MM-01`, `ancestorId`,
`descendantId`, `ancestorPath` y `descendantPath`. Las rutas corresponden al
árbol propuesto; los UUID distinguen nombres duplicados. No se retira, fusiona
ni reasigna ninguna partida para permitir el traslado.

Una operación efectiva incrementa una vez la revisión; el no-op no incrementa.
Un rechazo revierte también las operaciones previas de la unidad de trabajo
si la excepción se propaga fuera de `run`. Las escrituras técnicas directas
deben usar `run`/`writeTransaction` para registrar revisión, conforme al contrato
de EP-004; los triggers SQL protegen restricciones incluso fuera del adaptador.
El error SQL directo es un código de restricción; el detalle de meses y ramas
lo devuelve el puerto de categorías.

## Esquema 7, apertura y copias

La migración 6 → 7 elimina `categories_budget_history` e instala cinco triggers:
bloqueo de tipo de raíz usada (movimientos o presupuestos), promoción con tipo
conservado, destino válido en altas y traslados y solapamiento tras cambio de
padre. Se mantienen CHECK, FK y triggers publicados de ciclos/profundidad.
El solapamiento usa `RAISE(ABORT)` para revertir la sentencia completa.

No cambia ninguna tabla ni dato. Las definiciones y snapshots v1–v6 permanecen
publicados; se añade `drift_schema_v7.json` y se regenera Drift. El store guarda
la imagen consistente previa a migrar, incluso con WAL; la sustitución de
triggers es transaccional y no incrementa revisión de negocio. La apertura
verifica primero la alcanzabilidad del árbol con profundidad acotada, evitando
recursión indefinida en imágenes manipuladas, y después las reglas financieras.

La validación de candidatas reconoce v7 y migra v1–v6 exclusivamente en staging.
La creación de copias exige v7; el catálogo y su validador reconocen las
versiones publicadas anteriores sin modificarlas. Se actualizan los controles
de versión de EP-006 porque un cambio de esquema afecta a estas copias.
No se cambian OAuth, transferencias Drive ni EP-009.

## Verificación

`category_reorganization_test.dart` usa SQLite real sobre archivos sintéticos:
signos y referencias completos, tipo heredado, promoción, rechazo de cambios
directos, profundidad de subárbol, ciclos, archivo, todos los conflictos por mes,
hermanas/meses distintos, revisión/no-op, SQL directo y rollback de una unidad
que ya había renombrado. Comprueba reapertura, copia consistente y v6 → v7 con
respaldo, fallo intermedio y comparación exacta con el snapshot exportado.
Incluye rechazo sin cambiar bytes de imágenes con ciclos, cuarto nivel,
solapamientos y triggers ausentes.

Las suites existentes conservan la cobertura de archivo/asignaciones y se
adaptan las fixtures de versiones antiguas y futuras. Las pruebas de candidatas
cubren ahora todas las versiones publicadas v1–v6 hacia v7.

Resultado local del 2026-10-03: Flutter 3.47.0 / Dart 3.13.0 comprobados;
`check-quality.ps1` completo con lockfile exigido, formato correcto, análisis
sin incidencias, 804 pruebas y cuatro variantes `APP_ENV` correctas. Tras
ampliar las aserciones de lecturas públicas históricas, profundidad SQL y
la fixture de corrupción FK, nuevo análisis sin incidencias y las 44 pruebas
de reorganización/copia local correctas. Comprobador numérico EP-001 y L/M
correcto; snapshots v1–v6 y lockfile sin cambios. La suite incluye trabajo
concurrente de sincronización que no pertenece al commit de este ticket.

La primera ejecución restringida no pudo completar las comprobaciones nativas
de rutas temporales; la ejecución con acceso autorizado completó la suite.

No se han ejecutado builds ni recorridos nativos Windows/Android: el cambio
afecta persistencia compartida y contratos Dart, sin modificar plataformas ni UI.
