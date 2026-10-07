# MA-TSK-114 · Integración de EP-013 / EP-014

El núcleo común está entregado en EP-012. Los lectores históricos CSV (EP-013)
y bancarios XLS (EP-014) deben implementar `ImportAdapter` y usar revisión,
confirmación e historial existentes. Esta guía no incorpora ninguno de esos
lectores ni habilita su selección en producción. El contrato financiero sigue
siendo [EP-001](../ep-001/especificacion.md), con el
[contrato CSV](../ep-001/contrato-csv.md) y sus
[casos de referencia](../ep-001/casos-referencia.md).

## Responsabilidades y composición

| Componente | Responsabilidad |
|---|---|
| Selector de EP-013/014 | Obtener los bytes completos y un nombre sin ruta privada; elegir el lector y origen compatibles. |
| `ImportFile.fromBytes` | Copiar bytes inmutables y calcular SHA-256 con `Sha256ImportFingerprint`, inyectado desde app/data. |
| `ImportAdapter.interpret` | Interpretar todo el contenido en memoria y entregar filas, originales y errores estructurados; sin SQLite ni catálogo. |
| `ImportSession` | Validar versión común, origen, ordinales y lote no vacío. |
| `ValidatingImportPreviewer` | Resolver identidades, planes, vigencia, conflictos y solapamientos mediante el puerto de lectura. No escribir. |
| `ImportController` / `ImportReviewScreen` | Mantener decisiones en memoria, revisión expresa de avisos y consentimiento final; bloquear dobles envíos. |
| `ImportConfirmer` | Recalcular SHA, revalidar con reserva SQLite y registrar todo en una transacción. |
| `ImportHistoryRepository` | Consultar solo lotes confirmados, sus originales inmutables y destinos actuales o borrados. |

Importar tipos por `features/importing/importing.dart`. El lector pertenece a
`features/importing/data`; las bibliotecas de parsing se elegirán en su ticket,
sin modificar incidentalmente SDK ni lockfile. App compone servicios usando
`LocalBackupSession.imports()`; su loader resuelve la base activa por operación,
también después de restauración. No retener una conexión anterior. El grafo y
las fronteras se comprueban en `test/architecture_test.dart`.

Ejemplo de flujo sin interfaz, útil para pruebas de contrato del futuro lector:

```dart
final file = ImportFile.fromBytes(
  bytes: selectedBytes,
  fingerprint: const Sha256ImportFingerprint(),
  source: adapter.source,
  originalName: selectedName,
);
final session = ImportSession(
  file: file,
  interpretation: await adapter.interpret(file),
);
final services = await localSession.imports();
final review = await services.previewer.preview(session, bindings: decisions);
// Solo tras resolver errores/pendientes y revisar cada aviso expresamente:
final request = ImportConfirmationRequest(
  review: review,
  reviewedOverlapKeys: explicitlyReviewedKeys,
);
final result = await services.confirmer.confirm(request);
```

`decisions` es un `ImportReferenceBindings`: UUID existentes en `accounts` /
`categories`, o planes aprobados en `newAccounts` / `newCategories`. Un plan
no es una identidad persistida. Un hijo puede apuntar a un padre preparado;
una raíz nueva exige `isIncome` explícito. No crear referencias desde el lector
ni desde un selector. Resolver una referencia afecta a todas sus filas.

## Salida exigida a los lectores

- Declarar `source` y una `formatVersion` no vacía, estable y específica del
  formato. `importContractVersion` es la versión común, actualmente `1`;
  no sustituirla por la del parser.
- Asignar ordinal único a cada registro desde `2`, incluso entre REAL y
  PRESUPUESTO. Un campo multilínea no es varios registros. Conservar dos
  registros legítimos iguales con ordinales distintos.
- Conservar `originalFields` como lista ordenada de nombre/valor textual,
  incluidos nombres repetidos, espacios, saltos y representaciones del importe.
  No introducir los bytes completos del archivo dentro de un campo ni logs.
- Producir `ImportIssue` por error, con ordinal y campo cuando se conozcan.
  Recorrer todo el archivo y devolver todos los errores; no omitir filas
  defectuosas silenciosamente ni importar el subconjunto válido.
- Usar fechas civiles e importes exactos en céntimos int64. No usar `double`
  para interpretar dinero ni inferir categorías de ingreso por el signo.

| Regla | EP-013 CSV histórico | EP-014 XLS bancario |
|---|---|---|
| REAL | `ImportAmount.economic`, cuenta nombrada obligatoria; categoría opcional. | `ImportAmount.economic`; `ImportAccountReference.selectedAccount()` si no identifica cuenta por fila. Requiere selección antes de confirmar. |
| PRESUPUESTO | `ImportAmount.historicalBudget`: invertir el signo original exactamente una vez; mes y categoría obligatorios, sin cuenta. Cero permitido. | No admitido. Devolver error que bloquee todo el lote. |
| Referencias | Ruta de 1–3 niveles, UUID resuelto en revisión; ambigüedad requiere decisión. | Mismo contrato. Categoría nula en REAL representa Sin clasificar. |

La conversión `toBudgetInput` ya contiene el importe interno normalizado.
No llamar después a `BudgetInput.fromHistoricalCsv` ni invertir en confirmación.
REAL cero es inválido. Presupuestar padre y descendiente en el mismo mes es
inválido aunque uno valga cero, también contra partidas existentes y archivadas.
Los nombres se comparan por nivel sin mayúsculas ni espacios externos;
no eliminar acentos, puntuación ni espacios interiores para resolver referencias.

## Entrada de pantalla y estados

La entrada actual `ImportReviewLaunch` en `/importaciones/revision` es exclusiva
de `APP_ENV=test`; development/production la ignoran. EP-013/014 deberán añadir
expresamente su lanzamiento productivo desde la selección de archivo, con su
ticket y revisión de navegación. No habilitar `allowTestLaunch` en producción
ni copiar el adaptador de `test/support` a `lib/`. Reutilizar la pantalla común,
los retornos de periodo y el loader de servicios, evitando otra confirmación.

Leyendo → Revisión/Error → Confirmando → Importado/Ya importado/Error. Resolver
referencias y cancelar consentimiento/sesión no escriben. Durante Confirmando
se bloquean salidas y dobles acciones; no se promete cancelar la transacción.
Un rechazo conserva la sesión y presenta nueva revisión; las aprobaciones de
solapamientos se borran y deben hacerse otra vez. No llamar al `create` heredado
del repositorio: `confirm` es la frontera que conserva originales y revalida.

| Resultado del confirmador | Tratamiento |
|---|---|
| `ImportConfirmed` | Anunciar persistencia local, conteos y enlaces al lote/origen/periodo. |
| `ImportAlreadyImported` | Anunciar cero altas; el SHA global identifica los bytes incluso renombrados o después de editar/borrar destinos. No restaurar registros. |
| `ImportRejected` | Mostrar motivos; cero altas parciales. Conservar decisiones para revisión/reintento, sin registrar intento fallido. |

El solapamiento es un aviso por cuenta, fecha de valor, importe y concepto
normalizado contra registros de otro archivo. La revisión se identifica por
ordinal/UUID (`ImportOverlap.key`) y es explícita por pareja. Bytes distintos
pueden importar movimientos coincidentes tras aprobar avisos; nunca borrarlos.
Una coincidencia nueva entre revisión y confirmación exige revisar otra vez.
Los algoritmos de nombres y de concepto son distintos; no sustituirlos en el lector.

## Persistencia y consulta

Confirmar crea referencias, lote, identidades de origen, originales y registros
de ambos tipos atómicamente e incrementa revisión una vez. Un fallo revierte
también referencias, metadatos y revisión. El historial conserva ordinales,
nombre, SHA, origen, versiones, fecha y conteos originales; no el archivo entero.
La procedencia sobrevive a edición/borrado del destino. Un lote antiguo puede
carecer de originales/versión de lector: mostrar ausencia sin reconstruirlos
desde valores actuales. No hay deshacer ni almacenamiento de intentos fallidos.

`listBatches` y `listRows` usan cursores estables y límites 1–500; la pantalla
usa 50. Continuar hasta cursor nulo cuando se requiera el total; no validar solo
la página visible. Restaurar o sustituir la base exige recargar contexto.

## Pruebas mínimas para cada lector

Reutilizar el [recorrido integrado](../../test/support/import_lifecycle_journey.dart)
y el [informe de verificación](verificacion-integral.md). Añadir fixtures propios
del formato con parsing completo, encoding/BOM/saltos, campos multilínea,
columnas repetidas, dinero/fecha inválidos y versiones. Para CSV verificar los
48 presupuestos/10 reales y totales de EP-001. Para XLS usar únicamente muestras
sintéticas equivalentes al formato aprobado en EP-014, sin extractos personales.

Comprobar huella sobre bytes originales, rechazo completo, referencias/planes,
cuenta pendiente, Sin clasificar, signos y cero, ambigüedades, conflictos,
repetición renombrada, ordinales iguales de valor, solapamientos y revalidación,
rollback, doble envío, historial tras reapertura y edición/borrado. Ejecutar
calidad, builds fijados y recorrido nativo de ambas plataformas. Registrar
separadamente automatización, build y pruebas manuales: ninguno acredita los otros.
