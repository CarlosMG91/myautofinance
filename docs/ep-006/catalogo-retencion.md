# MA-TSK-053 · Catálogo, retención y espacio

## API y consumo

Se consultó el ticket MA-TSK-053, sus criterios y la dependencia completada
MA-TSK-052 en Epic Board mediante `GET http://localhost:4310/api/data`, tablero
**My autofinance**, con workspace coincidente. Se implementa el
[contrato v1](contrato-copias-locales.md) sin cambiar esquema, SDK o lockfile.

`LocalBackupCatalog`, exportado por `synchronization.dart`, entrega resultados
inmutables con fecha UTC, origen, tamaño, orden, disponibilidad, última validación
y su fecha. El listado ordena fecha descendente, después orden descendente e ID.
`createLocalBackupCatalog()` compone el adaptador desde app sin recibir un store:
se puede usar antes de abrir SQLite y con una activa ilegible. `read()` verifica
metadatos, existencia, tamaño y hash sin abrir SQLite de las copias; una validación
histórica se conserva como tal, no sustituye la revalidación antes de borrar.

- `read()`: devuelve `ready`, `recovered`, `empty`, `incompatible` o `unavailable`.
  Incidencias sin descriptor fiable aparecen separadas, con origen desconocido
  salvo intent verificable. `empty` nunca representa un error de almacenamiento.
  Si falla persistir una reparación, conserva el listado diagnóstico conocido
  en un resultado `unavailable`, informa del fallo y deshabilita la poda.
- `maintainAfterRestore(restoreOperationId, outcome, protectedBackupIds)`: el
  **coordinador de MA-TSK-055/056** solo pasa `confirmed` después de instalar,
  reabrir, validar y confirmar duraderamente el éxito. Los demás resultados no
  podan. Esta API no realiza ni certifica por sí misma una restauración.
- `deleteExplicitly(backupId, protectedBackupIds)`: acción expresa por ID;
  permite baja de manuales con otra copia integralmente verificada disponible.
  Bloquea una copia en uso o la última válida.
- `retryPendingDeletions(protectedBackupIds)`: reintenta exclusivamente bajas
  duraderas verificadas; vuelve a comprobar tres automáticas supervivientes
  para retención y una superviviente para una baja expresa antes de borrar.
  No decide nuevas bajas por antigüedad.

El coordinador indica las copias en uso mediante `protectedBackupIds` y resuelve
sus diarios antes de pedir poda. Mientras `local-backups/restore` contenga trabajo
no resuelto, se suspende cualquier nueva baja y su reintento. No se interpreta el
formato del diario futuro ni se asume que sus archivos pueden borrarse. Si queda
una baja pendiente, debe reintentarse expresamente antes de nuevas podas.

## Recuperación y mantenimiento

El adaptador usa el mismo bloqueo nativo por instalación que MA-TSK-052.
`BackupStorage` comparte comprobaciones de rutas y escritura duradera del
catálogo con creación; la captura consistente y su validador permanecen intactos.

Se elige la generación válida mayor. Un slot dañado se aísla en `diagnostics`
antes de repararlo, manteniendo el slot confirmado utilizable. Ambos slots
dañados o conflictivos se aíslan y se reconstruyen desde manifiestos y bajas:
entradas `pending`, epoch nuevo y contraste requerido. Un formato futuro o un
error al leer un slot se conserva, sin sobrescribirlo desde la generación vieja.
No se consulta Drive ni se modifica la señal de contraste de un catálogo sano.

Los finales completos no registrados se incorporan como `pending`. Archivos
ausentes conservan los metadatos conocidos; cambios de bytes revocan la
validación histórica. Sidecars, manifiestos dañados, enlaces, órdenes repetidos,
origen ambiguo, intenciones incompletas y snapshots huérfanos se conservan y
notifican. Se reserva el máximo orden de entradas, intenciones y bajas legibles
más uno, sin renumerar artefactos publicados. Los `.next` del catálogo son
escrituras no confirmadas: se conservan como `catalogWritePending` y nunca se
adoptan como generación ni autorizan una baja. No impiden completar una baja
autorizada por un tombstone verificado.

Tras un éxito confirmado se revalidan las automáticas con la política integral
SQLite existente. Se mantienen las tres válidas de mayor orden de creación,
independientemente del reloj, y se podan las anteriores válidas de más antigua
a más reciente. Antes de cada baja se revalidan de nuevo las tres supervivientes,
sus manifiestos y el candidato. Dañadas y manuales no se usan para aparentar la
cuota de tres ni se eliminan automáticamente. Con datos incompatibles,
inaccesibles o ambiguos se aplaza la poda; un exceso seguro puede permanecer.

Cada baja escribe y relee primero el tombstone del contrato, confirma
`deletionPending`, elimina únicamente los dos archivos esperados y el directorio
vacío, y confirma la retirada de la entrada. No hay borrado recursivo. Las bajas
se conservan indefinidamente para impedir resurrección desde slots antiguos o
escaneos. Una baja corrupta/contradictoria nunca autoriza borrado. Si falta
espacio o falla un borrado/commit, se notifica; se conservan manuales,
supervivientes y la información necesaria para reintentar.

En Windows se verifica el resultado de eliminar cada archivo. En Android/Linux
se confirma también el directorio mediante `fsync`; la baja duradera protege
contra resurrección si un borrado físico no persiste tras una interrupción.
Esto no acredita resistencia a pérdida eléctrica de un dispositivo.

## Verificación y límites

`test/synchronization/local_backup_catalog_test.dart` usa archivos y SQLite
reales con datos sintéticos. Cubre listado con activa dañada sin invocar el
validador, orden por fechas/contadores, R01/R02/R04–R08, bajas expresas protegidas,
fallos de espacio y borrado, reinicio en las fases de baja, catálogo viejo,
reconstrucción, formato futuro, intenciones, huérfanos, conflictos de orden,
tombstones corruptos/contradictorios, enlaces y cambios durante revalidación.
Las pruebas anteriores de creación siguen verificando la primitiva y el bloqueo
entre procesos. No se llena físicamente el disco: los fallos se inyectan.

`integration_test/local_backup_catalog_test.dart` prepara soporte privado real,
cuatro automáticas, una manual, evento fallido sin poda, evento confirmado con
fallo de borrado, nuevo propietario, reintento y listado con activa ilegible.
El evento confirmado es el punto de entrada de mantenimiento, **no una
restauración ejecutada**. CI ejecuta este recorrido en Windows y Android x86_64
junto con las integraciones existentes. Android ARM requiere ejecución propia.

La restauración integral, la interpretación del diario de intercambio, su señal
posterior de divergencia y la pantalla siguen en MA-TSK-054–058. Este ticket
no implementa controles visibles y no requiere aprobar un nuevo mockup.

### Evidencia local · 2026-10-02

- Flutter 3.47.0 / Dart 3.13.0, `check-toolchain.ps1` y dependencias con
  `pub get --enforce-lockfile` comprobados sin cambios de versiones.
- Los comandos de calidad necesitan permisos revisados para acceder a pub.dev
  y resolver rutas/enlaces del directorio privado; el sandbox los bloquea.
- Builds intentados: Windows bloqueado por falta de Visual Studio C++;
  Android bloqueado por ausencia de Android SDK. No se ha ejecutado aquí la
  integración dentro de la app ni Android; tampoco se afirma el resultado de CI.

- `scripts/check-quality.ps1`: 92 archivos con formato correcto, análisis sin
  incidencias, **516 pruebas correctas** y cuatro variantes adicionales de
  arranque correctas. Después del ajuste final de supervivientes al reintentar
  bajas, se repitieron formato, análisis y las **39 pruebas del catálogo**, todas
  correctas (incluida una nueva regresión de ese ajuste).
- `actionlint` del workflow, `git diff --check` y las cifras de referencia de
  EP-001 correctos. En Windows se ejecutaron archivos SQLite reales, bloqueo,
  movimientos duraderos, bajas y protección de un junction sintético; no se
  ejecutó el intercambio de restauración de los tickets posteriores.
