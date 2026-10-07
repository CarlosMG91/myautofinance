# MA-TSK-107 · Contrato común de importación v1

Ticket y dependencias contrastados el 2026-10-07 mediante lectura de
`http://localhost:4310/api/data`, tablero **My autofinance**. Se mantienen
[EP-001](../ep-001/especificacion.md), su [contrato CSV](../ep-001/contrato-csv.md),
los [casos de referencia](../ep-001/casos-referencia.md) y los contratos entregados
de [movimientos](../ep-010/contrato-movimientos.md) y
[presupuesto](../ep-011/gestion-partidas.md). No se cambia el estado del tablero.

## Entrada pública y capas

`features/importing/importing.dart` publica archivo, interpretación, filas,
referencias, sesión, revisión, solicitud/resultados y puertos. Dominio depende
solo de Dart y de las entradas públicas de movements/budget. App inyecta
`Sha256ImportFingerprint`, de `importing/data`, que utiliza la dependencia
crypto ya fijada. No se exporta ese adaptador desde la entrada del dominio.
MA-TSK-107 no cambia grafo, esquema SQLite, SDK ni lockfile. MA-TSK-109 amplía
compatiblemente estos puertos con planes de alta y candidatos pendientes;
su [contrato de previsualización](previsualizacion.md) registra la dependencia
adicional de los tipos públicos de wealth para las cuentas.

`importContractVersion = '1'` versiona la estructura común. El lector declara
además `ImportInterpretation.formatVersion`, no vacía: identifica la versión
del formato interpretado, que alimenta el `contractVersion` del repositorio
actual. Una versión común desconocida bloquea la sesión. Cambios incompatibles
exigen revisar consumidores y versionar el contrato; extensiones compatibles
pueden añadir campos opcionales.

## Archivo, filas y errores

- `ImportFile.fromBytes` copia los bytes e inyecta el cálculo SHA-256. La huella
  incluye BOM, saltos y todos los bytes; el nombre no participa. Se exige nombre
  sin ruta privada y huella hexadecimal minúscula de 64 caracteres. Los bytes
  permanecen únicamente en memoria durante la sesión; no van a tablas ni logs.
- Cada fila conserva ordinal de origen, campos originales como lista ordenada
  de nombre/valor (incluidos nombres repetidos), concepto, discrecionalidad y
  un `ImportAmount`. El lector conserva los valores originales sin trim y
  entrega aparte los valores internos interpretados. No guarda el archivo
  completo dentro de los campos originales.
- `InterpretedMovement` exige fecha civil válida, referencia de cuenta e importe
  económico distinto de cero. Categoría nula significa Sin clasificar.
  `ImportAccountReference.selectedAccount()` significa **cuenta pendiente de
  elección**, para lectores bancarios sin cuenta en cada fila; nunca autoriza
  un real sin cuenta. Una referencia nombrada vacía es inválida.
- `InterpretedBudget` exige mes civil y ruta de categoría. Su API no admite
  cuenta ni categoría nula. Cero es una partida explícita válida. La ruta tiene
  de uno a tres niveles no vacíos. No existe un UUID para Sin clasificar.
- `ImportAmount.economic` conserva el signo. `historicalBudget` conserva el
  importe CSV e invierte una vez al producir el interno; rechaza int64 mínimo
  antes de negarlo. Una sesión CSV exige esa convención para presupuestos y
  una bancaria rechaza presupuestos, conforme al repositorio existente.
  Los campos originales conservan también la representación textual del
  importe, incluidos ceros negativos o grafías propias del formato.
- `toMovementInput` / `toBudgetInput` reciben las identidades resueltas y usan
  directamente el importe interno. **No** volver a invocar
  `BudgetInput.fromHistoricalCsv` al resolver o confirmar.
- `ImportIssue` contiene código, ordinal, campo y motivo legible. Ordinal nulo
  significa problema del archivo/lote; campo nulo, problema general de fila.
  El lector transforma los errores de parsing/construcción en estos resultados
  y recorre todo el archivo. Una fila inválida sin tipo se representa con su
  error, no con una fila ficticia ni descartándola silenciosamente.

La sesión añade errores por versión desconocida, lote vacío, ordinal < 2 y
ordinal repetido entre cualquiera de los tipos. El ordinal sigue el convenio
existente: empieza en 2; identifica un registro, no una línea física de un campo
multilínea. Dos reales idénticos con ordinal distinto se conservan.
Construir una sesión no tiene acceso a persistencia; los errores permanecen en
memoria y bloquean la solicitud de confirmación de **todo** el lote.

## Puertos y revisión

`ImportAdapter.interpret(file)` recibe bytes inmutables y devuelve
`ImportInterpretation`; declara el origen que soporta y rechaza otros orígenes.
No recibe repositorios, catálogos ni conexión SQLite. Los futuros lectores
CSV/Openbank implementarán este puerto en EP-013/EP-014.

`ImportPreviewer.preview(session, bindings: ...)` es un puerto de solo lectura.
Las vinculaciones explícitas usan referencias como claves y UUID como valores;
se aplican a todas las filas que comparten referencia. Comparan nombres sin
mayúsculas ni espacios externos por nivel, sin borrar acentos, puntuación o
espacios interiores. Nombres coincidentes no garantizan identidad: el resolutor
debe consultar UUID y devolver ambigüedades, nunca escoger al azar.

`ImportReview` conserva sesión, bindings, errores, referencias pendientes y
avisos de solapamiento. Una revisión con referencias obligatorias sin vincular
no puede solicitar confirmación, incluso si se omite por error la lista de
pendientes. Conteos y totales originales/internos se separan por tipo; los
totales utilizan BigInt para evitar overflow al acumular muchas filas.

`ImportConfirmationRequest` exige revisión sin errores/pendientes y todas las
referencias obligatorias vinculadas. Además exige las claves de **todos** los
solapamientos revisadas explícitamente. Las claves identifican ordinal y UUID
del movimiento existente; no se elimina ninguna fila. Este guardado de intención
en memoria no sustituye revalidación ni representa un permiso permanente.

`ImportConfirmer.confirm` devuelve uno de tres resultados:

| Resultado | Significado |
|---|---|
| `ImportConfirmed` | Lote confirmado y conteos de reales/presupuestos. |
| `ImportAlreadyImported` | Lote ya existente por los mismos bytes; cero altas de cualquier entidad, también tras editar/borrar registros. |
| `ImportRejected` | Motivos estructurados no vacíos; cero cambios persistidos. |

El contrato del confirmador exige recalcular huella, revalidar asignaciones,
restricciones y nuevos solapamientos con la base vigente y confirmar todo en
una transacción con una revisión local. Los originales y metadatos se conservarán
sin binario completo, sin intentos fallidos persistidos y sin deshacer.

## Ejemplo de composición y conversión

```dart
final file = ImportFile.fromBytes(
  bytes: receivedBytes,
  fingerprint: const Sha256ImportFingerprint(), // app importa data
  source: adapter.source,
  originalName: selectedName,
);
final session = ImportSession(
  file: file,
  interpretation: await adapter.interpret(file),
);
final review = await previewer.preview(session, bindings: selectedBindings);
// Después de resolver los errores y revisar expresamente los avisos:
final request = ImportConfirmationRequest(
  review: review,
  reviewedOverlapKeys: explicitlyReviewedKeys,
);
final result = await confirmer.confirm(request);

// Frontera con EP-004 para filas ya resueltas:
final importedReal = ImportedMovement(
  real.sourceOrdinal,
  real.toMovementInput(accountId: accountUuid, categoryId: categoryUuid),
);
final importedBudget = ImportedBudget(
  budget.sourceOrdinal,
  budget.toBudgetInput(categoryId: budgetCategoryUuid), // no invierte
);
```

[Pruebas del contrato](../../test/importing/import_contract_test.dart) incluyen
implementaciones mínimas compilables de lector y previsualizador, exclusivamente
en test. [Pruebas de compatibilidad](../../test/importing/import_repository_compatibility_test.dart)
usan SQLite real y convierten entradas al repositorio existente. El ejemplo no
constituye el motor de producción ni un lector de archivos.

## Traspaso de alcance

MA-TSK-109 implementa validación completa contra catálogos, conflictos y resolución
de ambigüedades; incorpora los planes de creación y sus parámetros de dominio,
incluida marca de ingreso explícita en raíces nuevas. `accounts` y `categories`
siguen representando exclusivamente UUID existentes. `newAccounts` y
`newCategories` contienen decisiones en memoria, sin UUID ficticios ni altas
persistidas. El lector mantiene su separación de la resolución.

MA-TSK-110 implementa el confirmador y amplía el repositorio SQLite para conservar
originales y crear referencias aprobadas atómicamente. El repositorio actual
ya confirma lotes mixtos y conserva ordinales, pero todavía no persiste los campos
originales añadidos por este contrato. MA-TSK-111 añade historial/procedencia;
MA-TSK-108/112, aprobación e interfaz; MA-TSK-113, adaptador sintético integrado.
Este ticket no conecta esos puertos al arranque, ni implementa sus motores,
pantallas, lectores, persistencia nueva o historial.

## Verificación

Resultados locales del 2026-10-07 con Flutter 3.47.0 / Dart 3.13.0:

- `flutter --version`, `check-toolchain.ps1` y resolución con
  `--enforce-lockfile` correctos; lockfile sin cambios.
- 19 pruebas dirigidas correctas: contrato, compatibilidad SQLite y fronteras
  de arquitectura. Cubren huella conocida, BOM/saltos/nombre, copias inmutables,
  referencias, originales, signos/ceros/int64, versión, ordinal transversal,
  errores, pendientes, revisión explícita, conteos/totales y resultados.
- SQLite real en memoria con claves foráneas activadas: instantánea de todas
  las tablas y revisión idénticas antes/después de sesión/previsualización;
  lote mixto compatible con el repositorio actual, dos reales iguales
  conservados por ordinal, presupuesto invertido una vez, revisión única y
  rechazo de lote vacío sin cambios.
- `scripts/check-quality.ps1` completo: formato sin cambios, análisis sin
  incidencias, 1.055 pruebas correctas y cuatro variantes `APP_ENV` aprobadas.
  Se ejecuta fuera del sandbox para permitir los bloqueos de fichero de las
  pruebas existentes de SQLite y la resolución de dependencias.
- `node docs/ep-001/verificar-casos.mjs`: resultados financieros conservados.
- `git diff --cached --check`: sin errores; solo ocho archivos propios en la
  entrega. Cambios concurrentes en Drive y documentación quedan fuera.

No se ejecutan builds ni pruebas nativas Windows/Android: el cambio es un
contrato Dart sin cambios de plataformas. Las implementaciones del motor,
lectores, persistencia de originales e interfaz quedan para los tickets
indicados, y no se acreditan aquí.
