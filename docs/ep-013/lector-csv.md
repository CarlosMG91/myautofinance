# MA-TSK-116 · Lector histórico CSV estricto

Ticket y épica consultados el 2026-10-07 mediante lectura de
`http://localhost:4310/api/data`, tablero **My autofinance**. El lector aplica
el [contrato CSV aprobado](../ep-001/contrato-csv.md) y sus
[casos de referencia](../ep-001/casos-referencia.md), sin modificar EP-012.

## API y alcance

`HistoricalCsvReader` en `features/importing/data/historical_csv_reader.dart`
recibe los bytes completos mediante `read(List<int>)`. Es síncrono y puro:
solo depende de Dart y de los tipos propios del formato. No accede al disco,
SQLite, catálogos, motor, huella ni servicios. La entrada
`features/importing/historical_csv.dart` publica los tipos de dominio; app o el
futuro adaptador importan el lector desde data, respetando las capas.

La salida inmutable `HistoricalCsvReadResult` contiene registros intermedios
y diagnósticos. Si hay cualquier diagnóstico, `records` está vacío: no existe
un subconjunto válido que se pueda importar accidentalmente. Los registros
conservan tipo, fecha ISO civil, concepto, ruta de hasta tres nombres, cuenta,
discrecionalidad e importe **CSV** exacto en céntimos. La versión del formato es
`historicalCsvVersion = '1'` y es independiente del contrato común de EP-012.

Los campos originales son una lista ordenada de nombre/valor y línea física
de inicio. Conservan espacios, grafía, ceros negativos y saltos LF/CRLF; el
valor está desentrecomillado conforme al CSV (comillas duplicadas se convierten
en una comilla). Los valores tratados aplican `trim()` y conservan espacios
interiores. La cabecera se compara sin trim ni conversión de mayúsculas.

`sourceOrdinal` empieza en 2, avanza una vez por registro lógico y distingue
reales iguales. La línea física avanza dentro de campos entrecomillados. Un
diagnóstico contiene código estable, motivo en español, ordinal y nombre de
campo cuando se conocen, y línea física de inicio del campo para validaciones
o de detección para errores de sintaxis. UTF-8 inválido tiene diagnóstico de
archivo y desplazamiento de byte, sin inventar ordinal ni línea.

## Reglas y frontera con el adaptador

- UTF-8 estricto con/sin BOM; separador `;`; cabecera de nueve nombres exactos;
  campos entrecomillados estándar, comillas duplicadas, LF y CRLF. Un CR aislado,
  comilla en campo sin entrecomillar o texto después de cerrar comillas falla.
  Se eliminan espacios en valores ya interpretados, no se repara sintaxis CSV.
- Fechas del calendario entre 0001 y 9999, presupuesto en día 1, concepto
  obligatorio, tipo sin distinción de mayúsculas, jerarquía sin saltos,
  cuenta REAL obligatoria y presupuesto sin cuenta/con categoría.
- Importes `-?[0-9]+\.[0-9]{2}` después de trim, sin double ni redondeos:
  se construyen con BigInt y se comprueba el rango antes de convertir a int.
  REAL admite int64 completo excepto cero. PRESUPUESTO admite cero positivo
  o negativo; excluye int64 mínimo porque el signo interno no cabría al negarlo.
- Un salto final no crea fila. Dos saltos finales sí contienen un registro
  vacío rechazado. Una cabecera sola es estructuralmente válida y entrega cero
  registros; la regla común de lote no vacío corresponde a EP-012.
- Se acumulan errores de todos los campos y registros con delimitación válida,
  incluidas columnas incorrectas y filas vacías. UTF-8 inválido, cabecera
  incorrecta o sintaxis que impide delimitar registros detienen la lectura:
  no se reconstruyen filas ni se adivina dónde empieza otro registro.

MA-TSK-119 debe convertir estos intermedios a las entradas comunes de EP-012:
usar `ImportAmount.economic(csvAmountCents)` para REAL y
`ImportAmount.historicalBudget(csvAmountCents)` para PRESUPUESTO. El lector
**no invierte** el signo, evitando una doble inversión al adaptar. Nunca deduce
la marca de ingreso ni crea una categoría para Sin clasificar.

Resolver cuentas/categorías, unicidad de presupuestos y conflictos de padre y
descendiente exige las asignaciones e identidades vigentes y corresponde al
núcleo común. Tampoco se implementan selector, pantalla, totales internos,
confirmación, huella, historial, SQLite ni XLS en este ticket.

## Verificación

- Flutter 3.47.0 / Dart 3.13.0 comprobados con `flutter --version` y
  `scripts/check-toolchain.ps1`; `flutter pub get --enforce-lockfile` correcto,
  sin modificar SDK, paquetes ni lockfile.
- 82 pruebas propias del lector y dos de arquitectura correctas. Cubren BOM,
  LF/CRLF, salto final, Unicode válido e inválido, comillas, multilínea,
  ordinal/línea, cabecera/columnas/filas vacías, errores completos, calendario,
  obligatoriedad, jerarquía, espacios, inmutabilidad, signos, ceros e int64.
- La plantilla EP-001 produce 48 presupuestos y 10 reales; enero real
  `+122975` céntimos, real anual `+232965` y presupuesto CSV anual `-1320000`
  (interno esperado al adaptar: `+1320000`). Dos Café conservan ordinales 54/55.
- `node docs/ep-001/verificar-casos.mjs`: OK, resultados financieros conservados.
- `scripts/check-quality.ps1` completo: formato sin cambios, análisis sin
  incidencias, 1.234 pruebas correctas y las cuatro variantes `APP_ENV`
  aprobadas. Se ejecutó con los cambios concurrentes presentes en el checkout;
  esos archivos no pertenecen a este ticket ni se incluyen en su commit.
  Dependencias y pruebas de bloqueo SQLite se ejecutaron fuera del sandbox.
- `git diff --cached --check`: sin errores; entrega limitada a los cinco
  archivos propios de lector, tipos, entrada, pruebas y esta guía.

No se necesitan builds Windows/Android: el cambio es parsing Dart y no altera
plataformas. La integración con EP-012 y el recorrido de importación de la
aplicación pertenecen a tickets posteriores; no se acreditan en esta entrega.
