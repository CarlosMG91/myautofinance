# MA-TSK-110 · Confirmación atómica y repetible

Ticket y MA-TSK-107 contrastados el 2026-10-07 en Epic Board,
tablero **My autofinance**, mediante lectura de `/api/data`. Se reutilizan
los contratos entregados de EP-004, EP-008/009, EP-010/011 y la
[previsualización](previsualizacion.md), sin modificar las reglas de EP-001.

## Contrato y composición

`ImportBatchRepository` incorpora el puerto `ImportConfirmer`.
`SqliteImportBatchRepository(database)` implementa ambos sobre la conexión
existente. Los tipos de lote se separan en `import_batch.dart` y se reexportan
desde la entrada pública anterior, para conservar los imports sin ciclos.

```dart
final repository = SqliteImportBatchRepository(database);
final previewer = ValidatingImportPreviewer(SqliteImportPreviewSource(database));
final review = await previewer.preview(session, bindings: decisions);
final request = ImportConfirmationRequest(
  review: review,
  reviewedOverlapKeys: explicitlyReviewedKeys,
);
final result = await repository.confirm(request);
```

La previsualización, las altas propuestas y construir/descartar la solicitud
no escriben. No se conecta un lector sintético al producto ni se implementan
lectores CSV/XLS, pantallas, historial o deshacer. La composición visual y
las consultas paginadas corresponden a los siguientes tickets.

## Transacción y revalidación

La confirmación usa `LocalDatabase.writeTransaction`. Recalcula SHA-256 con
los bytes completos de la copia inmutable de la sesión y rechaza una huella
falsa, incluso si un proveedor de huellas anterior la produjo.

Antes de consultar las referencias reserva la escritura mediante un UPDATE
sin cambio de la revisión en `database_state`. SQLite mantiene el bloqueo
de escritura hasta acabar la transacción; otro escritor no puede intercalar
cambios entre revalidación y altas. Ante contención que SQLite no pueda
resolver se devuelve un rechazo de persistencia y se puede reintentar.

Primero busca la huella global, independiente del nombre y del origen. Si
ya existe devuelve `ImportAlreadyImported`, conservando el nombre y metadatos
del lote confirmado. Revierte incluso el estado temporal de seguimiento;
no crea referencias ni registros, no incrementa revisión y no restaura
movimientos/partidas corregidos o borrados. La regla se conserva tras reiniciar
y para lotes anteriores al esquema nuevo.

Para bytes nuevos repite la validación completa con las vinculaciones UUID y
planes aprobados, contra la misma transacción SQLite. No vuelve a elegir por
nombre una referencia aprobada que desapareció. Comprueba vigencia de cuentas,
categorías activas, planes de antecesores, versiones, ordinales, restricciones
presupuestarias entre filas y contra la base, y los solapamientos vigentes.
Un aviso nuevo exige nueva revisión; las claves aprobadas deben pertenecer
también a los avisos de la revisión original. Devuelve errores por ordinal,
campo y motivo, sin eliminar automáticamente ningún movimiento.

Solo después crea las cuentas con sus periodos de liquidez y las categorías
con sus antecesores en orden de dependencia. La marca de ingreso de una raíz
nueva es explícita; los hijos la heredan. Inserta lote, identidades de origen,
movimientos, presupuestos, originales y metadatos en la misma transacción.
REAL conserva cuenta, signo y categoría opcional; presupuesto no tiene cuenta
y su importe ya normalizado no se invierte otra vez. Dos reales iguales con
ordinal distinto generan dos UUID y dos filas de origen.

Las escrituras de originales y metadatos comprueban `changes()`: un IGNORE
es un fallo de carga completa. Se refuerza el cierre transaccional de EP-004
con esa misma comprobación para el incremento de revisión. Una carga correcta
incrementa revisión una vez; cualquier fallo revierte altas, timestamps,
metadatos, estado temporal y revisión. Un doble envío/reintento no duplica
la carga: la reserva y la restricción única de SHA protegen su identidad.

## Esquema v8 y traspaso a MA-TSK-111

Se mantienen intactos los snapshots publicados v1–v7. La migración transaccional
v7→v8 y los pasos previos añaden dos tablas complementarias:

| Tabla | Contenido |
|---|---|
| `import_batch_metadata` | `batch_id` PK/FK, `format_version`, `movement_count`, `budget_count` originales |
| `import_row_originals` | `import_row_id` PK/FK, `payload` JSON objeto versionado |

Ambas tienen triggers que impiden UPDATE/DELETE. Sus inserciones participan
en el seguimiento central de mutaciones. El payload versión 1 contiene:

- `fields`: lista ordenada de objetos `{name, value}`, conservando columnas
  repetidas, espacios, saltos y representación textual original.
- `concept`, `discretion`, `originalCents`, `internalCents`,
  `amountConvention` y `categoryPath` (nula para REAL sin clasificar).
- REAL: `valueDate` y `accountName` (nulo para selección bancaria global).
- PRESUPUESTO: `month`, sin cuenta.

Los importes son cadenas decimales exactas para no perder int64 en consumidores
JSON. `import_rows` conserva ordinal y tipo; `import_batches` conserva SHA,
nombre, origen, versión del contrato y fecha de confirmación. Ninguna tabla
almacena los bytes del archivo ni intentos fallidos/cancelados.

Los lotes previos, y la frontera heredada `create` para filas ya resueltas,
no disponen de estos originales ni versión de lector: no se reconstruyen
desde registros actuales. `ImportBatch.formatVersion` es nula en ese caso.
Los conteos del modelo se consultan sobre `import_rows`, que sobrevive al
borrado de los registros. Los lectores nuevos deben usar `confirm`.

El identificador y versión del formato viven en
`core/persistence/local_database_format.dart`; `schema_policy.dart` conserva
su reexportación compatible. Los servicios de copia consultan estas constantes
y la política de restauración reconoce v8, manteniendo la lectura de copias
anteriores y el rechazo de futuras. Se actualizan únicamente los fixtures de
esquema afectados; el formato de manifiestos y la sincronización manual no cambian.

## Verificación

Las pruebas SQLite de `sqlite_import_confirmation_test.dart` utilizan archivos
temporales y datos sintéticos. Cubren cancelación previa sin escrituras,
alta mixta, Sin clasificar, presupuesto normalizado/cero, campos repetidos,
inmutabilidad, reapertura/copia, repetición renombrada tras corrección/borrado,
bytes distintos con avisos aprobados, SHA falso, referencias obsoletas y
conflictos/avisos nuevos. Inyectan ABORT e IGNORE en referencias, lote, filas,
ambos destinos, originales, metadatos e incremento de revisión; comparan
todas las tablas y estado temporal, y comprueban el reintento.

Incluyen envíos simultáneos en la misma conexión y dos conexiones independientes,
cambios de vigencia desde otra conexión, migración v7 con respaldo y
conservación de dataset/revisión/huella. Las pruebas previas comprueban también
migraciones anteriores y su rollback. No se acredita aquí una ejecución nativa
Windows/Android ni builds de plataformas; EP-012 MA-TSK-114 los cubre en su
integración completa. No cambian SDK, lockfile ni código de plataformas.

Resultados finales locales del 2026-10-07 con Flutter 3.47.0 / Dart 3.13.0:

- `flutter --version`, `check-toolchain.ps1` y dependencias con
  `--enforce-lockfile`: versiones fijadas correctas, lockfile sin cambios.
- 33 pruebas nuevas de confirmación SQLite; 201 pruebas dirigidas de importación,
  arquitectura y regresiones de copia/restauración aprobadas. La suite final
  incluye además el escenario ampliado de rollback de la migración v7→v8.
- `scripts/check-quality.ps1` completo correcto: formato sin cambios,
  análisis sin incidencias, 1.114 pruebas y las cuatro variantes APP_ENV correctas.
- `node docs/ep-001/verificar-casos.mjs`: resultados financieros conservados.
- `git diff --cached --check`: sin errores; entrega limitada a 24 archivos propios.

Se ejecuta calidad fuera del sandbox para permitir acceso a pub.dev y los
bloqueos de fichero de SQLite en datos sintéticos. La ejecución inicial detectó
límites de esquema 7 en copias y un fixture de restauración; se corrigieron y
la verificación final completa pasó. Los cambios concurrentes de Drive,
README y diseño EP-008 quedan fuera de esta entrega.
