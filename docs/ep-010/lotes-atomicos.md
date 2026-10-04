# MA-TSK-090 · Categorizar y borrar lotes de forma atómica

Ticket contrastado el 2026-10-04 mediante `GET http://localhost:4310/api/data`,
tablero **My autofinance**. MA-TSK-088 y MA-TSK-089 figuran terminados.
Se siguen EP-001, el contrato de movimientos de EP-010 y la infraestructura
transaccional de EP-004, sin cambios de esquema, SDK ni lockfile.

## API y composición

La composición existente `createMovementManagement(database: db)` entrega:

- `assignCategory(ids, categoryId)`: asigna una categoría activa, a cualquier
  nivel del árbol, a los UUID suministrados.
- `removeCategory(ids)`: retira únicamente su categoría, también en históricos
  con categorías archivadas.
- `deleteBatch(ids)`: elimina únicamente esos movimientos. La interfaz debe
  invocarlo después de confirmar la cantidad y el alcance de la selección.

`MovementSelection` captura una lista inmutable, valida UUID canónicos,
elimina repetidos y rechaza el conjunto vacío. Para seleccionar la página
visible, el consumidor pasa `page.records.map((r) => r.id).toList()`; ninguna
operación acepta filtros ni amplía los UUID a todos los resultados.

El puerto `MovementRepository` incorpora `setCategoryBatch(ids, categoryId)`
(NULL retira) y `deleteBatch(ids)`. El adaptador SQLite también es atómico si
se invoca directamente: usa `LocalDatabase.writeTransaction`, compartido con
`UnitOfWork`, sin abrir conexiones ni implementar otra persistencia.

Dentro de la transacción se comprueba la existencia de **todos** los UUID y
la elegibilidad actual del destino antes de escribir. Una categoría archivada
se rechaza incluso si ya pertenecía a alguno de los seleccionados: categorizar
es una asignación explícita. Las escrituras usan parámetros y comprueban que
cada UPDATE/DELETE afecta a una fila; un fallo o una escritura ignorada revierte
el lote. No hay límite implícito de página ni consulta IN con parámetros ilimitados.

La asignación/retirada solo escribe `category_id` y la fecha técnica de edición.
Conserva UUID, importe firmado, cuenta, concepto, fecha de valor, discrecionalidad
y procedencia. Si una fila ya tiene la categoría pedida no se escribe, ni cambia
su fecha técnica. El borrado conserva `import_rows` e `import_batches`, por lo
que repetir el archivo no resucita movimientos. Presupuestos y fotos permanecen
intactos. La revisión central aumenta una vez si hubo cambios efectivos; un
lote sin cambios o rechazado no aumenta la revisión.

## Verificación

`test/movements/movement_batch_test.dart` usa SQLite real en archivo y datos
sintéticos. Compara todas las tablas financieras y la revisión tras rechazos;
tras categorizar compara exactamente los demás campos y la procedencia.
Cubre selección explícita y página capturada, duplicados de UUID, lote vacío,
UUID inválidos/ausentes, selección obsoleta, categorías archivadas/desconocidas,
los tres niveles, no-op, lote mixto, reapertura y bloqueo de reimportación.

Inyecta fallos ABORT e IGNORE en la segunda fila al asignar, retirar y borrar,
tanto por el servicio como directamente por el repositorio. Inyecta además un
fallo en la confirmación de revisión después de escribir las filas. Todo revierte,
incluidos timestamps, procedencia, presupuestos y fotos.

Resultados locales del 2026-10-04: Flutter 3.47.0 / Dart 3.13.0 comprobados,
`pub get --enforce-lockfile` sin cambios al lockfile y `check-quality.ps1`
completo correcto (formato, análisis, 950 pruebas y cuatro variantes APP_ENV).
Después de añadir los dos últimos escenarios, formato y análisis nuevamente
correctos y las 14 pruebas finales de lotes aprobadas. Las 39 pruebas dirigidas
previas de lotes, CRUD, búsqueda y unidad de trabajo también pasaron.
La ejecución SQLite se hizo fuera del sandbox, que impedía los bloqueos locales
de recuperación; no se modificó el producto para evitar esa protección.

No se implementan pantallas ni automatismos; confirmación visual y mockup
complementario corresponden a los tickets de interfaz. No se modifican plataformas
y no se acredita ejecución nativa en Windows/Android con este ticket.
