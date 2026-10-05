# MA-TSK-095 · Entrega de EP-010

Movimientos reales reutiliza cuentas EP-009, categorías EP-008 y la conexión,
repositorios y transacciones EP-004. No añade importadores, reglas automáticas,
presupuestos, fotos ni sincronización. El contrato financiero sigue siendo
[EP-001](../ep-001/especificacion.md), concretado en el
[contrato de movimientos](contrato-movimientos.md) y sus
[casos sintéticos](casos-referencia.md).

El ticket y MA-EPIC-086 se consultaron el 2026-10-05 en
`GET http://localhost:4310/api/data`, tablero **My autofinance**, workspace
de este repositorio. MA-TSK-094 consta `done`; todos los tickets previos de
EP-010 también. Se revisaron las dependencias de categorías y cuentas y la
[entrega visual EP-002](../ep-002/entrega-flutter.md).
La [evidencia de MA-TSK-094](integracion-lotes-navegacion.md) registra la
aprobación humana de MA-TSK-091. Se conservan el mockup y su propuesta originales:
sus etiquetas «pendiente» describen la presentación anterior a esa aprobación.
MA-TSK-095 añade pruebas y documentación, sin modificar pantallas ni contratos
compartidos. La [verificación](verificacion-recorrido.md) distingue ejecución
en host, ejecución nativa y límites del entorno.

## Entrega a informes

Consumir `features/movements/movements.dart`. `MovementRepository.readPage`
recibe un periodo civil `[from, until)` por **fecha de valor**, cuenta opcional,
categoría directa opcional, alcance `direct`/`branch`, `unclassifiedOnly`,
concepto, cursor exclusivo y límite. «Sin clasificar» significa NULL, sin
crear un nodo de categoría. Rama incluye el nodo y sus descendientes actuales,
también referencias archivadas. Los filtros se intersectan.

`MovementPage.records` contiene una página en orden fecha descendente/UUID
ascendente. `subtotalCents` suma con signo **todos los resultados filtrados**,
incluidos los que no están en la página. Es int64 en céntimos; overflow falla
explícitamente. No deducir transferencias, ingresos ni saldos desde categorías.
Para agregados anuales existe `readYear`, sin límite de página; no construir
un total de informe sumando únicamente la primera página de `readPage`.
Releer tras una escritura. Un cursor solo sirve con los mismos filtros y una
base estable; restaurar una copia exige reiniciar lectura y selección.

Para abrir una cifra, construir `MovementListQuery` con periodo, cuenta,
categoría/alcance o no clasificados y concepto. La capa app inyecta el callback
de navegación y serializa con `MovementLinks.list(query, origin: ...)`;
los informes no importan SQLite ni controladores de presentación ajenos.
`origin` es una ruta interna validada de las cinco vistas o inicio.
Gestión transmite únicamente el mes seleccionado, sin heredar filtros del
informe. Abrir detalle y volver conserva el contexto de la lista; volver al
informe conserva su ruta original. El consumidor de un informe futuro debe
pasar los filtros reales de su cifra, sin introducir totales simulados.

## Entrega a importación futura

`ImportBatchRepository` es infraestructura EP-004. Recibe filas **ya
interpretadas** y SHA-256 de los bytes originales; no analiza CSV/XLS. Usar
`getByFingerprint` antes de presentar una repetición, y `create` para confirmar
atómicamente. La restricción de huella sigue siendo la protección final frente
a carreras. Una huella repetida se rechaza, con cero altas y sin incrementar
revisión, incluso después de editar o borrar sus movimientos y aunque cambie
el nombre de archivo. Una huella diferente requiere revisión humana según
[contrato CSV](../ep-001/contrato-csv.md); no implica deduplicación semántica.

Cada ordinal conserva su propia identidad. Dos movimientos idénticos con UUID
distintos son legítimos, tanto manuales como importados. `MovementRecord`
publica `importRowId`, `batchId` y `sourceOrdinal`; correcciones y categorización
conservan esos campos. Borrar conserva `import_rows` y `import_batches`, por lo
que una repetición no resucita filas. No permitir editar procedencia.

`MovementManagement.edit` conserva argumentos ausentes; `MovementChange(null)`
retira expresamente categoría o discrecionalidad. El texto opcional vacío se
normaliza a NULL. Se puede conservar una categoría archivada en un registro
histórico, pero no asignarla de nuevo. La cuenta debe ser corriente y vigente
en el mes de valor; una cuenta cerrada sigue siendo elegible para su historia.

## Escrituras y selección

La composición usa `LocalBackupSession.movements`,
`createMovementListSource` y `createMovementManagement`, con repositorio y
`UnitOfWork` sobre la **misma conexión**. Resolver la sesión activa al escribir;
no retener una conexión anterior a restauración. La identidad opaca de conexión
protege borradores y selecciones incluso si dataset y revisión coinciden.

Una acción recibe `MovementSelection` no vacía con UUID concretos; seleccionar
página captura sus UUID, sin ampliar a los resultados filtrados. Categorizar
solo cambia categoría; quitarla usa NULL. Borrar individualmente o en lote
requiere confirmación previa. Cancelar no escribe. Las acciones revalidan todas
las referencias; fallo o UUID desaparecido revierte el lote y su revisión.
El éxito incrementa revisión una vez; no-op/error no la incrementa.
Presupuesto y fotos patrimoniales permanecen independientes.

Los contratos, casos y artefactos originales pendientes de publicación de
MA-TSK-087/091 se entregan junto con este cierre de EP-010. Se excluyen cambios
concurrentes de EP-007/008 y README, así como SDK, logs, bases sintéticas y builds.
