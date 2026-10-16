# MA-TSK-200 · Regresión de servicios financieros EP-001

Auditoría del 2026-10-16. Consulta de solo lectura de Epic Board mediante
`http://localhost:4310/api/data`: tablero **My autofinance**, workspace de este
repositorio, MA-EPIC-196 y MA-TSK-200 coinciden con la petición, sin adjuntos.
MA-TSK-183 y MA-TSK-184 constan como `done`; su proveedor y cálculo EP-023
están disponibles y se verifican integrados. No se modifica el tablero.

## Contrato y cobertura reutilizada

Los valores esperados proceden exclusivamente de los
[casos sintéticos aprobados EP-001](../ep-001/casos-referencia.md), la
[especificación](../ep-001/especificacion.md) y el
[contrato CSV](../ep-001/contrato-csv.md). «Referencia Excel» designa ese
contrato, sin usar extractos, bases ni cifras personales. Las cantidades de la
tabla están en EUR; las aserciones persistentes usan céntimos enteros.

Cada fila identifica pruebas ejecutables existentes; solo se amplía la
aceptación compartida del indicador para cubrir su integración con la variante
histórica D y sustituir la simplificación de febrero por la foto aprobada.
No se crean copias de las pruebas suficientes ni otro motor de fórmulas.

| Caso / criterio | Prueba y escenario | Resultado esperado |
|---|---|---|
| A: importación, signos, repetición y Café | [historical_csv_import_adapter_test.dart](../../test/importing/historical_csv_import_adapter_test.dart), «Plantilla: altas aprobadas, una transacción, historial y repetición renombrada» | 48 presupuestos y 10 reales; presupuesto normalizado; Café conserva ordinales 54/55. Reimportar bytes idénticos renombrados devuelve `ImportAlreadyImported` y deja todas las tablas, incluida revisión, iguales: cero altas. |
| B/C: estado mensual | [monthly_status_query_test.dart](../../test/monthly_status/monthly_status_query_test.dart), «EP-001 B/C: céntimos firmados, duplicados y ausencia de foto» | Enero previsto +1.100,00, real +1.229,75, diferencia +129,75; febrero previsto +1.100,00, real +1.099,90, diferencia −0,10. Ocio sin presupuesto conserva dos reales y −20,00. |
| D: foto original, ausencia, parcial, cero, corrección | [wealth_reading_test.dart](../../test/wealth/wealth_reading_test.dart), «Caso D: magnitudes, parcial, cero y corrección del mismo mes» | Enero líquidos 9.000,00 y neto 14.000,00. Febrero ausente/parcial: totales y líquidos nulos; pendientes ahorro/cartera. Completar con ahorro 0,00 y cartera 10.500,00: líquidos 6.200,00 y neto 11.900,00. Corregir principal a 6.300,00: neto 12.000,00, misma foto, enero intacto. |
| D: liquidez histórica y valores inmutables | [liquidity_management_test.dart](../../test/wealth/liquidity_management_test.dart), «Caso D por servicio: cambio y corrección conservan fotos y enero» | Cartera líquida desde febrero: líquidos 16.700,00 y neto 11.900,00; enero líquidos 9.000,00. Corrección a media: líquidos 6.200,00; mismos registros de valoraciones. |
| D: periodos inválidos | [account_repository_test.dart](../../test/persistence/account_repository_test.dart), «SQLite rechaza solapes INSERT/UPDATE…», «Fallo al insertar tras dividir revierte periodos y alta completa» y «Una base con huecos no se abre…»; [liquidity_management_test.dart](../../test/wealth/liquidity_management_test.dart), «Límites, baja inclusiva, cambios posteriores y cobertura exacta» | Se rechazan solapes y operaciones fuera de vigencia; fallos transaccionales conservan periodos, valores y revisión. La apertura rechaza huecos sin alterar bytes. |
| E: presupuesto anual | [annual_budget_query_test.dart](../../test/budget/annual_budget_query_test.dart), «EP-001 E: CSV sintético, doce totales +1100 EUR y anual +13200 EUR» | Doce meses +1.100,00; anual +13.200,00 y 48 partidas identificables, sin doble cómputo de padres. |
| F: real anual | [annual_actual_query_test.dart](../../test/actual_spending/annual_actual_query_test.dart), «EP-001 F: diez originales, doce meses, firmas y lectura inmutable» | Enero +1.229,75; febrero +1.099,90; diez meses cero; anual +2.329,65, 10 movimientos. Incluye Ocio −20,00 y agregados por raíz. |
| G y D: indicador integrado | [indicator_acceptance_test.dart](../../test/indicators/indicator_acceptance_test.dart) ejecuta [indicator_acceptance.dart](../../test/support/indicator_acceptance.dart) en dos tamaños de pantalla | Proveedor SQLite, `IndicatorEngine` y `EmergencyCushionCalculation` de producción: enero 3,00, febrero 2,07 y corregido 2,10 meses. La foto completa D tiene deuda 4.800,00 y cartera 10.500,00; se acreditan netos 11.900,00/12.000,00 y enero 14.000,00 intacto. |
| G: motivos sin dato | La misma aceptación; complementan [emergency_cushion_calculation_test.dart](../../test/indicators/emergency_cushion_calculation_test.dart) e [indicator_input_provider_test.dart](../../test/indicators/indicator_input_provider_test.dart) | `foto_ausente`, `foto_incompleta` con ahorro/cartera pendientes, `ingresos_incompletos` con marzo pendiente, `ingresos_nulos`, `ingresos_negativos`; prioridad foto antes que ingresos y numerador cero válido. |
| D/G: carencia integrada completada | Ampliación de la misma aceptación | Cartera media hasta febrero exclusivo y líquida desde febrero: enero sigue 3,00, febrero pasa a 5,57 meses (razón exacta 167/30). Corrección histórica explícita a media: 2,07; valores SQLite idénticos. Sin foto, media y líquida siguen dando `foto_ausente`. |
| A/H: padre y descendiente, atomicidad | [budget_repository_test.dart](../../test/persistence/budget_repository_test.dart), «Padre y descendiente en ambos órdenes, duplicados y edición atómica» y «Lotes mixtos, signo normalizado, procedencia y reversión completa»; conflictos del CSV en [historical_csv_import_adapter_test.dart](../../test/importing/historical_csv_import_adapter_test.dart) | Rechazo en ambos órdenes. La edición conserva mes/importe anterior; el lote mixto fallido no deja lote, partidas, movimientos ni procedencias parciales. El CSV con Vivienda en enero se bloquea sin alterar tablas. |

## Aislamiento y ejecución

La aceptación ampliada recibe `LocalDatabase(NativeDatabase.memory(...))` y
reutiliza `seedRecoveryReference`: fixture sintético existente A–G ya
normalizado. Las consultas de flujos e importación leen el CSV aprobado del
repositorio y ejecutan lector, importador, repositorios y consultas reales.
Las pruebas que necesitan disco inyectan un directorio nuevo de
`Directory.systemTemp.createTemp`; no usan la resolución del directorio de
datos de la instalación. Los escenarios de corrupción solo alteran esas bases
desechables. Ninguna comprobación requiere abrir la base activa del usuario.

Cada evaluación de aceptación compara antes/después `total_changes()`,
revisión y tablas de esquema, presupuestos, movimientos, cuentas, periodos y
fotos. Consultar el indicador y mostrarlo debe ser solo lectura. Las escrituras
explícitas entre evaluaciones preparan variantes sintéticas; no son reparaciones.

Las diferencias de estas aserciones fallan la regresión. No se pasan importes
esperados ficticios al ejecutor de diagnóstico de producción ni se emiten
hallazgos sobre datos personales. [sqlite_diagnostic_executor_test.dart](../../test/diagnostics/sqlite_diagnostic_executor_test.dart)
ya distingue meses sin presupuesto válidos, duplicados legítimos y coincidencias
entre lotes como avisos; no se duplica esa cobertura aquí.

Reproducción desde la raíz, con la toolchain fijada:

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
node docs/ep-001/verificar-casos.mjs
flutter test --no-pub test/indicators/indicator_acceptance_test.dart
./scripts/check-quality.ps1
```

La última orden incluye toda la matriz anterior, análisis, formato y las cuatro
variantes de `APP_ENV`. Los tamaños Windows/Android de la aceptación son
widgets en el host; no equivalen a ejecutar runners nativos ni a aprobación
visual. Este ticket solo cambia pruebas y documentación: no requiere cambios
de plataforma, builds ni una nueva aceptación visual.

## Resultado de verificación

- Flutter 3.47.0 / Dart 3.13.0 y `check-toolchain.ps1`: correctos.
  `flutter pub get --enforce-lockfile` completado con acceso de red; SDK,
  `toolchain.json` y `pubspec.lock` sin cambios.
- Comprobador original `node docs/ep-001/verificar-casos.mjs`: **OK**.
- Formato global: 477 archivos, cero cambios. Análisis global: sin incidencias.
  Análisis del soporte final del indicador: sin incidencias. Las cuatro
  variantes `APP_ENV` (`development`, `test`, `production`,
  `invalid-synthetic`) se ejecutaron por separado y pasaron (1 prueba cada una),
  porque la pasada global no alcanzó esa fase del script.
- Matriz financiera aislada, doce archivos y concurrencia 1: **159 pruebas
  correctas, cero fallos**. Incluye la aceptación ampliada en ambos tamaños de
  pantalla. Todos los criterios financieros de MA-TSK-200 quedan verificados.
- `check-quality.ps1` se ejecutó, pero **la calidad global no está verde**:
  alcanzó 1.955 pruebas correctas y cinco fallos observados; se interrumpió
  tras quedar sin progreso, sin completar el resto de esa pasada.
  Dos fallos son `pending_lifecycle_test.dart`, Windows/Android:
  `StateError: No element` en `pending_lifecycle_journey.dart:144`, al buscar
  `PopupMenuButton<String>` desde Real anual. Se reproducen ejecutando solo
  ese archivo (0 correctas / 2 fallos). Esos archivos, Real anual y navegación
  están intactos respecto a `HEAD` y no importan el soporte del indicador.
  Otros tres fallos observados pertenecen a restauración: «igual revisión
  también exige contraste local» (`recoveryRequired` en lugar de `restored`),
  «bloqueo nativo compartido rechaza una segunda operación» (archivo temporal
  en uso) y recuperación tras `journal-004.json` (timeout/archivo en uso).
  No se atribuye una causa definitiva a estos tres fallos de la pasada global.
  No se modifica sincronización, donde ya había trabajo concurrente.
- Sin builds ni ejecución nativa: el cambio está limitado a pruebas y esta
  documentación. La aprobación visual permanece fuera de MA-TSK-200.

Reproducción de la matriz aislada:

```powershell
$financialRegressionTests = @(
  'test/importing/historical_csv_import_adapter_test.dart'
  'test/monthly_status/monthly_status_query_test.dart'
  'test/budget/annual_budget_query_test.dart'
  'test/actual_spending/annual_actual_query_test.dart'
  'test/wealth/wealth_reading_test.dart'
  'test/wealth/liquidity_management_test.dart'
  'test/persistence/account_repository_test.dart'
  'test/persistence/budget_repository_test.dart'
  'test/indicators/indicator_acceptance_test.dart'
  'test/indicators/emergency_cushion_calculation_test.dart'
  'test/indicators/indicator_input_provider_test.dart'
  'test/diagnostics/sqlite_diagnostic_executor_test.dart'
)
flutter test --no-pub --concurrency=1 $financialRegressionTests
```

Los registros locales de esta sesión se conservan en
`ma-tsk-200-matrix.log`, `ma-tsk-200-quality.log` y `ma-tsk-200-pending.log`
(ignorados por Git). No son necesarios para reproducir los casos.
