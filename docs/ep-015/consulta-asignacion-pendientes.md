# MA-TSK-134 · Consulta y asignación segura de pendientes

Ticket y dependencias contrastados el 2026-10-08 mediante
`GET http://localhost:4310/api/data`, tablero **My autofinance**. Se reutilizan
EP-004 y EP-010; no se cambia esquema, SDK, lockfile ni semántica de las
operaciones generales de Movimientos. La implementación no añade pantallas.

## Contratos para la bandeja

La entrada pública `features/movements/movements.dart` exporta
`PendingMovementRepository`, `PendingMovementQuery`, `PendingMovementPage`,
`PendingMovementSelection` y `PendingMovementManagement`. El mismo
`SqliteMovementRepository` implementa los dos puertos; no abre otra conexión.
La composición `createPendingMovementManagement(database: db)` reutiliza la
base activa y su unidad de trabajo.

```dart
final service = createPendingMovementManagement(database: db);
final filters = PendingMovementQuery(batchId: batchId, concept: 'cafe');
final page = await service.readPage(query: filters);
// Mostrar page.totalCount, separado de page.records.length.
final selection = page.selectPage(); // O page.select([uuidVisible]).
// Después de confirmar cantidad y categoría activa:
await service.assignCategory(selection, activeCategoryId);
final updated = await service.readPage(query: filters);
```

Solo se consultan filas de `movements` con `import_row_id IS NOT NULL` y
`category_id IS NULL`. Quedan excluidos los manuales y los presupuestos,
incluso si estos pertenecen al mismo lote. La procedencia utiliza los UUID y
ordinales ya existentes de EP-004; no necesita nuevos lectores de importación.

Sin filtros se abarcan todos los periodos, incluidos 0001 y 9999. Los filtros
de lote, cuenta, fechas y concepto se intersectan. El periodo técnico es
`[from, until)`, con ambos extremos opcionales. La UI que muestre una fecha
«hasta» inclusiva debe convertirla al siguiente día civil; para 9999-12-31
utiliza `until: null`, sin desbordar. Las cuentas históricas siguen consultables.
Los UUID de lote/cuenta y los periodos invertidos se validan antes de leer.
Un UUID de lote sin coincidencias devuelve cero pendientes.

La búsqueda reutiliza `conceptSearchKey` de EP-010: subcadena literal,
NFD/eliminación de marcas y case-fold Unicode. Se recortan los extremos;
puntuación, espacios internos, `%`, `_`, comillas y barras conservan su valor.
Todos los valores de consulta se parametrizan.

El orden y cursor reutilizan EP-010: fecha de valor descendente, UUID
ascendente en empate y cursor exclusivo. Tamaño 100 por defecto, entre 1 y
500; SQL lee como máximo `limit + 1`. `totalCount` procede de `COUNT(*)` con
los mismos predicados y sin cursor/límite, en la misma transacción de lectura
que la página. No se cargan los resultados completos en Dart ni se calcula
un subtotal monetario innecesario. Una página agotada puede estar vacía y
conservar el contador total filtrado.

## Selección, transacción y cambios de base

`select(ids)` comprueba que los UUID sean visibles, deduplica, rechaza vacío
y captura una lista inmutable; `selectPage()` captura únicamente esa página.
El contrato admite también construir una selección de UUID explícitos con
la identidad leída, para consumidores que conserven selecciones explícitas.
No existe operación que seleccione mediante filtros o contador.

La selección incluye `databaseIdentity` (objeto de conexión, local y no
serializable) y `datasetId`. El repositorio contrasta ambos dentro de
`LocalDatabase.writeTransaction`, antes de modificar movimientos. Reabrir o
restaurar la misma imagen invalida la identidad anterior aunque conserve
UUID, dataset y revisión. El cambio de dataset también invalida la selección.
El consumidor debe obtener la composición de la **conexión activa** al confirmar,
como EP-010; no reutilizar servicios de una conexión cerrada tras restaurar.

Dentro de la misma transacción se exige que cada UUID siga existiendo, sea
importado y tenga categoría NULL, y que el destino exista y esté activo.
Ya categorizado se rechaza incluso si su categoría coincide con el destino.
El UPDATE repite el predicado de elegibilidad y exige una fila afectada;
cualquier rechazo, fallo o escritura ignorada revierte el lote entero.
La protección se aplica también si se llama al repositorio directamente.
Las operaciones generales `assignCategory`/`setCategoryBatch` de EP-010 siguen
permitiendo reemplazar una categoría; no se modifica su comportamiento.

El éxito solo modifica `category_id` y `updated_at`, con una revisión local
para todo el lote. Se conservan UUID, importe/signo, fecha, concepto, cuenta,
discrecionalidad, procedencia, huella y originales de importación; presupuestos
y fotos permanecen intactos. No se compara la revisión capturada: una edición
ajena que no cambie la elegibilidad no bloquea la asignación.

Para MA-TSK-135: tras éxito, limpiar selección y reiniciar lectura con los
mismos filtros; al cambiar filtros, limpiar selección y cursor. Tras cambiar
base, descartar toda selección antigua. Los enlaces desde Gestión y resultado/
historial de lote corresponden a MA-TSK-136 y a las entregas de EP-012.

## Verificación

`test/movements/pending_movement_test.dart` usa archivos SQLite y datos
sintéticos: origen manual/importado/presupuesto, lotes CSV/XLS, cuentas y nombres
duplicados, duplicados legítimos, varios meses y límites 0001/9999; filtros,
Unicode/literales, páginas de 1/2/100/500 y contador global de 528 registros.
Compara todas las tablas persistentes y el resto de campos de Movimientos.

Cubre asignación individual/página, selección capturada/deduplicada, destino
archivado/desconocido, UUID ausente/manual/categorizado/eliminado, inyección de
ABORT/IGNORE y fallo al registrar revisión. Con dos conexiones reales verifica
ediciones anteriores a la confirmación y dos asignaciones simultáneas: solo
una gana, sin reemplazo y con una revisión. Sustituye una copia por la misma
imagen y exige nueva selección; también comprueba cambio de dataset.
Un caso EP-012 conserva originales/metadatos/huella y repite el archivo tras
categorizar sin duplicar ni borrar categorías.

Resultados finales del 2026-10-08, Flutter 3.47.0 / Dart 3.13.0:

- Suite inicial dirigida: 46 pruebas aprobadas (19 nuevas y 27 de regresión).
- Tras añadir conservación de originales EP-012, `check-quality.ps1` completo:
  formato correcto, análisis sin incidencias, 1.322 pruebas aprobadas
  (incluidas las 20 de pendientes) y cuatro variantes de `APP_ENV` aprobadas.
- `node docs/ep-001/verificar-casos.mjs`: OK, cifras financieras conservadas.
- `git diff --check`: correcto; toolchain y lockfile sin cambios.

Los intentos restringidos de resolución de dependencias y SQLite se bloquearon
por el sandbox; resolución y pruebas finales terminaron con permiso de ejecución.
La comprobación global incluye el checkout compartido; el commit se limita a
los siete archivos de este ticket, sin incorporar cambios concurrentes de
sincronización, mockups ni fixtures ajenas.
No se modifican plataformas; este ticket no acredita UI ni ejecución nativa
Windows/Android, y no requiere compilar proyectos nativos.
