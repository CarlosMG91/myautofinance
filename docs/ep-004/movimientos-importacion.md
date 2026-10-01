# MA-TSK-035 · Movimientos y procedencia

El esquema físico v4 añade `movements`, `import_batches` e `import_rows`,
índices por fecha/cuenta/categoría y triggers de vigencia y procedencia.
Conserva los snapshots publicados v1–v3. Creación y migraciones desde v0
sintética y v1/v2/v3 conservan dataset_id, revisión y datos existentes;
LocalDatabaseStore guarda el respaldo consistente antes de migrar.

`MovementRepository` se publica desde movements y `ImportBatchRepository`
desde importing. Los adaptadores en app/data/sqlite reciben LocalDatabase
por constructor; no cambian arranque, pantallas ni grafo de módulos.

- `create`, `get`, `edit`, `setDiscretion` y `delete` implementan CRUD.
  Importe firmado INTEGER en céntimos, no cero; cuenta obligatoria de tipo
  account y vigente en el mes de la fecha civil. Categoría y discrecionalidad
  son opcionales. No se deduce ingreso, saldo ni transferencia por el signo.
- `edit` conserva discrecionalidad, UUID y procedencia; `setDiscretion`
  permite modificar o retirar expresamente ese texto. Una categoría archivada
  puede conservarse al corregir un movimiento existente, sin nuevas asignaciones.
- `list` exige rango [from,until), admite filtros combinados por cuenta/categoría
  y consulta sin clasificar. Orden (value_date,id), cursor exclusivo, límite
  predeterminado 100 y máximo 500. Fin abierto solo para el año 9999.
  La categoría se filtra exactamente; no calcula informes ni agregados de ramas.
- La confirmación de lote recibe SHA-256 de los bytes originales y filas ya
  interpretadas. No calcula la huella de una representación normalizada ni
  analiza CSV/XLS. Exige metadatos válidos, nombre sin ruta privada, lote no
  vacío y ordinal único >= 2. Confirma lote, identidades de fila y movimientos
  en una sola transacción; un fallo revierte todo. La huella es única globalmente.
- Dos filas idénticas con ordinal distinto son dos movimientos distintos.
  La identidad transversal `import_rows` reserva también el tipo budget para
  su ticket. Triggers verifican el tipo destino y congelan procedencia y lotes.
  Borrar un movimiento conserva fila y lote, impidiendo reimportar para resucitarlo.
- CHECK/FK/UNIQUE protegen fechas gregorianas reales, UUID, importes, ordinales
  y referencias. Se rechazan cambios de vigencia que dejen movimientos fuera.
  Apertura y validación de copia comprueban también cuenta/vigencia/tipo de origen.

Las fotos patrimoniales y presupuestos siguen en sus tickets. La revisión
central de escrituras corresponde a su ticket; esta implementación conserva
el comportamiento previo y no añade incrementos parciales de revisión.

## Verificación local · 2026-10-01

Flutter 3.47.0 / Dart 3.13.0 verificados. Lockfile sin cambios, generación Drift
y snapshot v4 exportados. Calidad: formato, análisis sin incidencias, 54 pruebas de host y cuatro
variantes APP_ENV. Pruebas SQLite reales cubren CRUD/reapertura, duplicados,
filtros/cursor, int64 extremos, discrecionalidad, cuenta/tipo/vigencia, fechas,
archivo de categoría, procedencia inmutable, SHA repetida, ordinal repetido,
rollback de lote y conservación de fotos mediante fixture sintético.
EXPLAIN QUERY PLAN confirma el índice cuenta/fecha. Las pruebas previas cubren
migraciones v0/v1/v2 y rollback intermedio; se añade v3→v4 y comparación exacta
con snapshot v4. El comprobador EP-001 conserva todas las cifras originales.

Integración nativa ampliada con dos movimientos importados idénticos y lectura
de procedencia/discrecionalidad tras reapertura. Se intentó Windows: no pudo
compilar por falta de soporte de enlaces simbólicos para plugins. No hay
dispositivo Android conectado; no se acredita ejecución nativa ni éxito remoto.
No cambian plataformas ni dependencias; no se repiten builds de distribución.

Se usa el ticket íntegro facilitado por el usuario. No hay conector Epic Board
disponible para consultar o modificar el estado administrativo.
