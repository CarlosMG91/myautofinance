# MA-TSK-036 · Presupuestos mensuales persistidos

Esquema físico v5: `budgets` separado de `movements`, sin cuenta, con mes
civil (día 01), categoría obligatoria, INTEGER firmado en céntimos (incluido
cero explícito), concepto/discrecionalidad opcionales y procedencia por
`import_rows`. Las consultas devuelven únicamente partidas existentes.

`BudgetRepository`, publicado por `budget`, ofrece alta, edición, borrado,
consulta individual y listado mensual. `SqliteBudgetRepository` se inyecta
con la misma `LocalDatabase` que los demás adaptadores. Conserva identidad
y procedencia al editar; el borrado explícito conserva fila de origen y lote.

La validación de repositorio y los triggers SQLite rechazan duplicados y
ancestros/descendientes en un mismo mes, también en ediciones. Hermanos y
meses independientes se permiten. La categoría archivada admite corrección
de partidas existentes, pero no nuevas asignaciones. La entrega original
rechaza cambiar padre o marca de ingreso de una rama con presupuestos.
EP-008 / MA-TSK-079 sustituye ese bloqueo de padre por traslado que conserva
referencias y signos, hereda la nueva raíz y rechaza atómicamente solapamientos
padre/descendiente en cualquier mes afectado. El cambio directo de marca de una
raíz usada sigue bloqueado. Véase el [traspaso](../ep-008/arbol-categorias.md);
este ticket documental no modifica los triggers ni el repositorio entregados.

`SqliteImportBatchRepository.create` admite presupuestos solos o combinados
con movimientos. Comparte transacción, huella y unicidad de ordinal entre
ambos tipos: un conflicto revierte lote, procedencia y todas las altas.
Recibe importes internos ya normalizados; `BudgetInput.fromHistoricalCsv`
invierte el signo CSV y rechaza el mínimo int64 antes de negarlo. No interpreta
archivos ni calcula informes. Concepto y discrecionalidad se conservan.

La migración añade los cinco objetos de presupuesto después de los pasos
previos sin recrear datos. La política de apertura reconoce v0 sintética y
v1–v4 y valida esquema, FK, integridad, procedencia y solapamientos en v5.
Los snapshots anteriores permanecen intactos; se añade `drift_schema_v5.json`.

## Verificación

Datos sintéticos y SQLite real: cero/ausencia, hermanos, tres niveles,
ancestro/descendiente en ambos órdenes, duplicados, meses independientes,
edición rechazada sin cambios, CRUD/reapertura, int64, signos CSV, metadatos,
lotes mixtos y reversión íntegra, ordinal transversal, borrado e idempotencia,
restricciones SQL directas, archivo e historia de categorías y migración v4→v5.
Las pruebas previas de migración comparan el esquema completo contra v5.

No se implementan pantallas, parseo CSV/XLS, cálculos ni Drive. No se ejecutan
builds Windows/Android porque no se modifican plataformas; las pruebas son de
host y no acreditan ejecución nativa en dispositivos. No hay herramienta Epic
Board disponible: se usa el ticket completo facilitado por el usuario y no
se cambia el estado del tablero.

Calidad local (2026-10-01): Flutter 3.47.0 / Dart 3.13.0; lockfile sin cambios, formato correcto, análisis sin incidencias, 59 pruebas y cuatro variantes APP_ENV correctas. Generación Drift y snapshot v5 exportados; git diff --check correcto.
