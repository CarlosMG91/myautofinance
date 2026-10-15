# MA-TSK-184 · Cálculo puro del colchón de emergencia

`EmergencyCushionCalculation` implementa `IndicatorCalculation` y se exporta
desde `features/indicators/indicators.dart`. Recibe las entradas acordadas en
MA-TSK-182/183; no consulta SQLite, movimientos, la matriz EP-021 ni servicios
externos. Tampoco cambia entidades, catálogo, proveedor ni navegación.

## Regla y estados

Se calcula la razón exacta `BigInt(líquidosCents) * 12 / ingresosAnualesCents`
mediante `IndicatorValue`. El producto ocurre después de convertir a `BigInt`,
sin desbordar int64 ni redondear el promedio mensual. `WealthReading` aporta
los líquidos de la foto completa del día 1: no se restan deudas ni se incluyen
activos medios/no líquidos. El cero líquido produce un valor calculado si
los ingresos son completos y positivos.

El cálculo aplica la precedencia de EP-001 §6.1:

1. `foto_ausente`, conservando las fichas pendientes de la lectura.
2. `foto_incompleta`, conservando ID/nombre de las fichas pendientes, incluso
   si ya están valorados todos los activos líquidos.
3. `ingresos_incompletos`, con los meses pendientes ordenados del año elegido.
4. `ingresos_nulos`, cuando la suma anual firmada es cero.
5. `ingresos_negativos`, cuando la suma anual firmada es negativa.

Los textos se toman de la definición v1 existente, sin duplicarlos. Se adjuntan
los pendientes del motivo prioritario; los estados de ingresos no ocultan
una foto ausente/incompleta. La presencia mensual se recibe del proveedor:
doce ceros explícitos completan el año pero producen `ingresos_nulos`; un
presupuesto vacío produce `ingresos_incompletos` con los doce meses pendientes.

Las entradas omitidas o de otro mes/año son `IndicatorReadFailure` de código
`invalidInputs`, también al invocar directamente el cálculo. No se disfrazan
de ausencia financiera. La función no modifica sus entradas.

## Presentación y composición

`formatCalculatedIndicator` es una función de presentación sin widgets. Usa
la precisión/unidad del resultado y división/resto de `BigInt`. Redondea una
sola vez mediante **half-up decimal** (empates alejándose de cero), agrupa
millares con punto y usa coma decimal, sin conversión a `double` ni cero
negativo. Para el colchón la precisión es dos: `3,00 meses`, `2,07 meses`.
La razón exacta permanece intacta después de formatearla.

La composición por constructor del motor existente queda disponible para
el ticket de UI, sin introducir aquí pantallas ni conectar un marcador:

```dart
final engine = IndicatorEngine(
  catalog: IndicatorCatalog.v1(),
  inputs: provider,
  calculations: {'colchon_emergencia': const EmergencyCushionCalculation()},
);
final evaluation = await engine.evaluate('colchon_emergencia', selectedMonth);
```

## Alcance de la verificación

Se usa el ticket completo facilitado por el usuario; no hay conector de Epic
Board disponible en esta sesión y no se actualiza el tablero. Se conservan
los cambios concurrentes ajenos y se entregan únicamente los de MA-TSK-184.
Todos los datos de prueba son sintéticos.

Las pruebas cubren la matriz de precedencia con estados simultáneos, fichas
y meses pendientes, los casos D/G de EP-001, cero explícito, ingresos firmados,
numerador cero, razones periódicas, promedio mensual sin redondear, producto
y suma superiores a int64, errores de periodo y composición con el motor.
El formateador comprueba empates y valores inmediatamente a ambos lados,
acarreo a la parte entera, cifras muy grandes y precisión interna intacta.

No se ejecutan builds Windows/APK ni aceptación visual: el ticket no cambia
plataformas ni incorpora UI. La aceptación visual de EP-026 sigue independiente.

Comprobaciones locales del 2026-10-15:

- Flutter 3.47.0 y Dart 3.13.0 comprobados con `flutter --version` y
  `scripts/check-toolchain.ps1`.
- `flutter pub get --enforce-lockfile`: correcto, sin cambios en el lockfile.
  La consulta a pub.dev requirió acceso de red fuera del sandbox.
- El primer recorrido dirigido dentro del sandbox terminó con 76 pruebas
  correctas y un fallo al abrir la sesión local de la prueba de restauración
  de MA-TSK-183. Esa misma prueba pasa en la batería general ejecutada fuera
  del sandbox.
- `scripts/check-quality.ps1`: formato de 439 archivos sin cambios y análisis
  completo sin incidencias. La batería general terminó con 1.853 pruebas
  correctas y tres fallos de navegación por `Bad state: No element`:
  `movement_lifecycle_test.dart` en Android y `pending_lifecycle_test.dart`
  en Windows y Android. Son los mismos casos y errores ya documentados en
  las entregas MA-TSK-182/183; no se modifican sus archivos ni se afirma que
  el script completo pase. El contraste anterior está descrito en
  `motor-indicadores.md` y `proveedor-entradas.md`; aquí no se repite.
- Tras añadir dos casos finales de prueba (empate a través del cálculo real
  y activo no líquido positivo), `flutter test --no-pub test/indicators
  test/architecture_test.dart`: **79 pruebas correctas**, incluidas las
  49 nuevas de este ticket y la restauración de sesión existente.
- Las cuatro variantes de arranque (`development`, `test`, `production` e
  `invalid-synthetic`): correctas, una prueba cada una. Se ejecutan por separado
  porque el fallo general impide llegar a esa fase del script.
- Análisis estático final completo sin incidencias y formato final de los
  13 archivos de indicadores/pruebas sin cambios.
