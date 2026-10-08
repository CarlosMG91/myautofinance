# MA-TSK-119 · Adaptador CSV al núcleo común

Ticket, épica y dependencias consultados el 2026-10-08 mediante lectura de
`http://localhost:4310/api/data`, tablero **My autofinance**. MA-TSK-107 y
MA-TSK-116 figuran completados. Se respetan el
[contrato CSV](../ep-001/contrato-csv.md), los
[casos de referencia](../ep-001/casos-referencia.md), el
[lector puro](lector-csv.md) y la [guía de EP-012](../ep-012/guia-lectores.md).

## Composición y salida

`HistoricalCsvImportAdapter` implementa el puerto público `ImportAdapter` en
`features/importing/data/historical_csv_import_adapter.dart`. App importa esa
implementación desde data; el dominio común sigue consumiéndose por
`features/importing/importing.dart`. No se cambia el contrato ni el motor
EP-012, la navegación, las pantallas, el selector, las dependencias o el esquema.

```dart
const adapter = HistoricalCsvImportAdapter();
final file = ImportFile.fromBytes(
  bytes: selectedBytes,
  originalName: selectedName,
  source: adapter.source,
  fingerprint: const Sha256ImportFingerprint(),
);
final session = ImportSession(
  file: file,
  interpretation: await adapter.interpret(file),
);
final review = await services.previewer.preview(session, bindings: decisions);
// Tras resolver todas las referencias y revisar cada solapamiento:
final request = ImportConfirmationRequest(
  review: review,
  reviewedOverlapKeys: explicitlyReviewedKeys,
);
final result = await services.confirmer.confirm(request);
```

`services` procede del loader común `LocalBackupSession.imports()`; las
asignaciones y planes son `ImportReferenceBindings`. La selección y el
lanzamiento productivo de este flujo pertenecen a MA-TSK-120.

- Origen `ImportSource.historicalCsv`, formato CSV `historicalCsvVersion = '1'`
  y versión común `importContractVersion`, independientes. Otro origen entrega
  error de archivo y cero filas, incluso con contenido CSV válido.
- REAL usa `ImportAmount.economic`, fecha civil `ValueDate`, cuenta nombrada
  obligatoria y categoría opcional. Ruta vacía produce categoría nula,
  Sin clasificar; no crea un nodo con ese nombre.
- PRESUPUESTO usa `ImportAmount.historicalBudget`, mes `BudgetMonth` y categoría
  obligatoria; su tipo no contiene cuenta. Esta es la única inversión. Resolver,
  convertir a `BudgetInput` y confirmar emplean directamente el importe interno.
- Concepto y discrecionalidad conservan los valores tratados por el lector,
  incluido texto vacío opcional. Los campos originales conservan nombres, orden
  y valores desentrecomillados sin trim, incluidos espacios, comillas, saltos
  y representación monetaria. El ordinal lógico se copia sin agrupar ni
  eliminar registros idénticos.
- Cada diagnóstico se transforma en `ImportIssue` conservando ordinal, campo
  y motivo. Los errores estructurales usan `invalidFile`; los de validación de
  valores, `invalidField`. El contrato común no tiene propiedades de línea
  física, desplazamiento de byte ni código específico del lector; esos detalles
  siguen disponibles en la API del lector puro. No se inventan filas erróneas.
  Cualquier error del lector entrega cero filas y bloquea la sesión completa.

El adaptador no calcula SHA ni totales, no consulta catálogos ni escribe SQLite.
`ImportFile` conserva la huella de los bytes originales y `ImportReview` calcula
conteos y totales firmados por tipo con `BigInt`. EP-012 resuelve referencias
desconocidas/ambiguas, aplica una asignación a todas sus filas, valida planes de
creación aprobados, presupuesto y solapamientos, revalida al confirmar y guarda
todo atómicamente con originales e historial.

## Verificación

[Pruebas del adaptador](../../test/importing/historical_csv_import_adapter_test.dart)
usan el contrato público real, un doble de lectura ya utilizado por EP-012 para
catálogos ambiguos y los servicios SQLite reales con datos sintéticos.

- 28 pruebas propias y 112 dirigidas junto al lector y arquitectura, correctas.
  Signos económicos y presupuesto, cero positivo/negativo, int64 y sumas BigInt,
  origen/versiones, campos tratados/originales, Unicode, multilínea y ordinal,
  Sin clasificar, errores completos y bloqueo de confirmación parcial.
- Plantilla EP-001: 10 REAL, CSV/interno `+232965` céntimos; 48 PRESUPUESTO,
  CSV `-1320000`, interno `+1320000`. Enero real `+122975`; los dos Café
  conservan ordinales 54/55. Los mismos importes se comprueban en SQLite.
- Revisión sin escrituras; altas aprobadas, lote mixto e historial de las 58
  filas confirmados con una sola revisión local. Reimportar los mismos bytes
  renombrados devuelve `ImportAlreadyImported` y conserva todas las tablas.
- Ambigüedades resueltas expresamente para todas las filas; conflictos de
  presupuesto entre padre/hijo y mismo nodo, también con cero. Dos filas Café
  de otro archivo generan cuatro avisos contra los dos Café previos; cada aviso
  exige revisión expresa y ambos movimientos nuevos se conservan.
- Un conflicto aparecido después de revisar se rechaza al confirmar sin cambios.
  Un fallo de escritura mediante trigger SQLite revierte referencias, lote,
  filas, originales e incremento de revisión.
- `flutter --version`, `scripts/check-toolchain.ps1` y
  `flutter pub get --enforce-lockfile`: versiones fijadas correctas, sin cambios
  de SDK, paquetes ni lockfile. La resolución necesitó acceso de red fuera del
  sandbox.
- `node docs/ep-001/verificar-casos.mjs`: OK; cifras financieras conservadas.
- `scripts/check-quality.ps1` completo: formato sin cambios, análisis sin
  incidencias, 1.275 pruebas correctas y las cuatro variantes `APP_ENV` aprobadas.
  Se ejecutó fuera del sandbox para la red y los bloqueos de fichero SQLite,
  con los cambios concurrentes presentes, que no pertenecen a este commit.
- `git diff --cached --check`: sin errores; entrega limitada al adaptador,
  sus pruebas y esta guía.

No se requieren builds Windows/Android: el cambio convierte datos en Dart y
no modifica plataformas. No se acredita selección ni recorrido nativo desde
la aplicación, que corresponden a integración y verificación posteriores.
Los cambios concurrentes de Drive, README y mockup de categorías quedan fuera
de la entrega de este ticket.
