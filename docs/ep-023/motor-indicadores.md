# MA-TSK-182 · Motor y catálogo de indicadores

Contrato de dominio de EP-023 conforme a EP-001 §6.1. Entrada pública:
`lib/features/indicators/indicators.dart`. El módulo mantiene el grafo existente
`indicators → wealth, budget`; no modifica schema, movimientos, presupuestos,
fotos, rutas ni UI. No se persisten indicadores ni se interpretan fórmulas.

## Registro y resultados

`IndicatorDefinition` declara ID estable, nombre visible, versión positiva,
entradas requeridas, periodo, unidad y motivos en orden de precedencia.
`IndicatorCatalog` recibe definiciones en código, conserva su orden y rechaza
IDs duplicados incluso si tienen otra versión. Las colecciones se copian y
son inmutables.

`IndicatorCatalog.v1()` publica exclusivamente `colchon_emergencia`, versión 1,
nombre «Colchón de emergencia», periodo mensual y unidad `meses`. La foto es
del mes elegido y el presupuesto del año de ese mismo mes. Motivos y textos:

| Precedencia | Código | Texto |
|---|---|---|
| 1 | `foto_ausente` | sin dato: falta foto patrimonial |
| 2 | `foto_incompleta` | sin dato: foto patrimonial incompleta |
| 3 | `ingresos_incompletos` | sin dato: presupuesto anual de ingresos incompleto |
| 4 | `ingresos_nulos` | sin dato: ingresos presupuestados nulos |
| 5 | `ingresos_negativos` | sin dato: ingresos presupuestados no positivos |

`IndicatorResult` es sellado: `CalculatedIndicator` contiene valor exacto,
precisión de presentación y unidad; `UnavailableIndicator` contiene motivo
(código/texto) y `IndicatorMissingDetail` con fichas pendientes (ID y nombre)
y meses pendientes (1–12). El periodo y la definición acompañan el resultado
en `IndicatorEvaluation`. No se extraen datos del texto visible.

`IndicatorValue` conserva una razón de dos `BigInt`, reducida y con denominador
positivo; rechaza denominador cero. Evita desbordamientos del producto por 12
y pérdidas de precisión al dividir céntimos. El cero es un valor calculable.
El cálculo del colchón usará `líquidosCents * 12 / ingresosAnualesCents`, sin
redondear el promedio mensual. Su precisión de presentación será 2; el
formateo es-ES y el redondeo final corresponden a presentación, sin convertir
el valor exacto a texto dentro del motor.

## Contrato compartido para T02 y T03

T02 implementará `IndicatorInputProvider.read(month, requiredInputs)`:

- `IndicatorInput.monthlyWealth`: `IndicatorInputs.wealth` reutiliza directamente
  `WealthReading` de EP-009/017. Incluye `month`, `status`, `pending` y
  `liquidAssetsCents`. Los líquidos solo están disponibles con foto completa,
  sin restar deudas ni arrastrar otra foto. `absent` e `incomplete` son estados
  financieros válidos, también cuando ya se hayan valorado todos los líquidos.
- `IndicatorInput.annualIncomeBudget`: `IndicatorInputs.annualIncome` contiene
  `AnnualIncomeBudget(year, totalCents, presentMonths)`. `totalCents` es `BigInt`
  firmado, con el signo interno ya normalizado; `presentMonths` es un conjunto
  de números 1–12. `pendingMonths` devuelve los ausentes ordenados y
  `isComplete` requiere los doce. Un cero explícito cuenta como presencia.
  Varias partidas del mismo mes solo completan ese mes, aunque sean doce filas.
  Se seleccionan las ramas por la marca de la raíz actual, no por el signo.
  `BudgetRepository.readYear(year, incomeOnly: true)` de EP-011 ya permite esa
  selección, con las reglas del árbol EP-008 y sin depender de la matriz EP-021.
- El proveedor entrega una lectura coherente de las entradas solicitadas. Una
  entrada no solicitada puede ser null. Una foto ausente se representa con un
  `WealthReading` de estado `absent`, nunca con null. Un presupuesto vacío se
  representa con total cero y conjunto de meses vacío.
- `IndicatorReadFailure` es una excepción técnica, fuera de `IndicatorResult`.
  El proveedor no convierte errores SQLite/lectura en `foto_ausente`. El motor
  conserva esta excepción y envuelve otros fallos de lectura conservando causa
  y stack. Valida entradas requeridas y periodos; una lectura omitida o de otro
  mes/año produce `invalidInputs`, sin ejecutar el cálculo.

T03 implementará `IndicatorCalculation.calculate(IndicatorInputs)` sin IO,
aplicando la fórmula y la precedencia declaradas. Se conecta por constructor:

```dart
final catalog = IndicatorCatalog.v1();
final engine = IndicatorEngine(
  catalog: catalog,
  inputs: provider, // Implementación T02.
  calculations: {'colchon_emergencia': calculation}, // Implementación T03.
);
final evaluation = await engine.evaluate('colchon_emergencia', selectedMonth);
```

El motor exige correspondencia exacta entre catálogo y cálculos al componerse.
Rechaza resultados con unidad o código/texto de motivo ajenos a la definición.
Un fallo del cálculo se propaga como error técnico/de programación, sin
transformarlo en «sin dato». La elección del primer motivo aplicable pertenece
al cálculo: este ticket fija sus metadatos y orden; T03 verifica las condiciones
y precedencias financieras. No se inyecta un cálculo simulado en producción.

## Extensibilidad y límites

La prueba `indicador sintético se añade solo en test sin cambiar entidades base`
añade otra definición y cálculo sobre la misma `WealthReading`, en EUR y sin
requerir ingresos. Demuestra que el motor no tiene ramas por ID ni asume una
unidad o lista de motivos única. Esa definición y cálculo solo existen en
`test/indicators/indicator_engine_test.dart`; el catálogo v1 conserva una entrada.

No hay editor de fórmulas, plugins, umbrales, consejos financieros, resultados
persistidos ni indicadores adicionales de producto. El proveedor real, la
fórmula de producción, sus casos financieros, el formateo y la UI quedan en
sus tickets de EP-023. La UI posterior seguirá EP-026 T04/T05 y su aprobación;
esta entrega no cambia apariencia ni navegación.

## Verificación de la entrega

Se usa el ticket completo facilitado por el usuario. No hay conector de Epic
Board disponible en esta sesión; no se ha consultado ni actualizado el tablero.
Los cambios concurrentes de sincronización y documentación ajena quedan fuera
de la entrega. Los datos de prueba son sintéticos.

Comprobaciones locales del 2026-10-15:

- Flutter 3.47.0 / Dart 3.13.0 verificados con `flutter --version` y
  `scripts/check-toolchain.ps1`.
- `flutter pub get --enforce-lockfile`: correcto, sin cambiar el lockfile.
  El primer intento sin acceso de red falló al consultar pub.dev; se repitió
  con acceso permitido y se resolvieron las versiones fijadas.
- `flutter test --no-pub test/indicators test/architecture_test.dart`:
  16 pruebas correctas (14 del motor y 2 de arquitectura).
- `scripts/check-quality.ps1`: formato de 431 archivos sin cambios y análisis
  estático completo sin incidencias. La batería general terminó con 1.787
  pruebas correctas y tres fallos ajenos al motor, por `Bad state: No element`
  al buscar controles de navegación que las pruebas antiguas esperan:
  `movement_lifecycle_test.dart` (Android) y `pending_lifecycle_test.dart`
  (Windows y Android). Por ello el script completo no queda verde.
- Los tres fallos se reprodujeron en una copia aislada con tests de `696641c`,
  `indicators.dart` original de ese commit y el estado compartido de `lib`
  necesario para compilar sincronización. El `HEAD` puro no compilaba porque
  esa entrega concurrente depende de archivos aún sin confirmar. El contraste
  ejecutó solo los casos afectados, sin conectar el motor nuevo; no se
  modifican los archivos de sus propietarios.
- Las cuatro variantes `APP_ENV` del script se ejecutaron por separado:
  `development`, `test`, `production` e `invalid-synthetic`, todas correctas
  (una prueba cada una). El fallo general impidió llegar a esa fase del script.
- `git diff --cached --check`: sin errores de espacios.

No se ejecutan builds ni validación visual nativa: el cambio es exclusivamente
de dominio y no afecta a plataformas. No se afirma verificado el proveedor
SQLite, el cálculo financiero de producción ni la UI de sus siguientes tickets.
