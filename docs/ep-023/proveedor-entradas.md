# MA-TSK-183 · Entradas patrimoniales y presupuestarias

`RepositoryIndicatorInputProvider` implementa el puerto de MA-TSK-182 y se
exporta desde `features/indicators/indicators.dart`. Recibe por constructor
`WealthManagement`, `BudgetRepository` y una unidad de trabajo de lectura.
`createIndicatorInputProvider(database: ...)` conecta las tres lecturas a la
misma conexión SQLite con `SqliteReadUnitOfWork`.

## Lectura y trazabilidad

- `monthlyWealth` reutiliza `WealthManagement.readMonth` y `WealthReading`,
  sin volver a calcular patrimonio en indicadores. Consulta exactamente el
  día 1 del mes elegido. EP-009/017 resuelve las fichas vigentes y la liquidez
  histórica efectiva; no se arrastran fotos ni se incluyen fichas futuras o
  dadas de baja antes del mes. La baja es inclusiva.
- Los estados `absent`/`incomplete`, las valoraciones de origen y las fichas
  pendientes se conservan. Los líquidos solo están disponibles con foto
  completa, incluso si las fichas pendientes son deudas o activos no líquidos.
  No se resta deuda ni se suman activos de liquidez media/no líquida. Un cero
  explícito es una valoración registrada.
- `annualIncomeBudget` usa `BudgetRepository.readYear(year, incomeOnly: true)`
  con el año del mes elegido. La consulta existente selecciona las ramas por
  la marca de su raíz actual, incluidas categorías archivadas y referencias
  históricas. Un traslado posterior cambia la selección al releer. El signo
  no determina si una partida es ingreso.
- Se suman una vez las partidas originales, sin agregar otra vez los padres,
  repartir importes ni consultar la matriz EP-021. La exclusión mensual de
  padre/descendiente sigue en presupuesto y sus validaciones existentes.
  Los signos internos del CSV ya fueron normalizados al importar.
- `AnnualIncomeBudget.totalCents` acumula con `BigInt`: admite sumas firmadas
  superiores a int64, sin redondeo ni desbordamiento intermedio. La presencia
  se determina por cada mes con alguna partida explícita, también cero o con
  suma neta cero. `pendingMonths` conserva los meses ausentes ordenados.
- `AnnualIncomeBudget.sourceBudgets` añade la lista inmutable completa de
  partidas seleccionadas con ID, mes, categoría, céntimos, concepto y
  procedencia de importación disponible. No se limita a doce filas. La nueva
  propiedad es opcional para conservar compatibilidad con los consumidores
  del contrato MA-TSK-182; el proveedor real siempre la rellena.
- `IndicatorInputs.datasetState` añade la identidad y revisión de la lectura.
  Es opcional para implementaciones sintéticas anteriores del puerto, y el
  proveedor real siempre la incluye. Las entradas no solicitadas quedan null.

## Coherencia y errores

La transacción empieza leyendo `database_state`; foto, fichas, periodos de
liquidez y selección del presupuesto por catálogo se consultan dentro de ese
mismo snapshot. La transacción nativa de Drift adquiere el bloqueo de escritura
al empezar (`BEGIN IMMEDIATE`): otro escritor espera o recibe `SQLITE_BUSY`,
sin introducir una revisión intermedia en la lectura. No se mantiene una caché
ni se escriben resultados, revisiones o controles de mutación.

Para cumplir la lectura sin escrituras se cambia únicamente
`SqliteWealthRepository.read` a `database.transaction`, conservando sus
consultas y reglas. Las mutaciones patrimoniales siguen usando
`writeTransaction`. La prueba compara `total_changes()` antes/después, además
de comprobar identidad y revisión: detectaría también escrituras auxiliares.

`WealthReading` conserva sus cantidades públicas int64 y comprueba sus sumas
con `BigInt` antes de convertirlas. Si una magnitud no cabe, lanza
`WealthFailure`; los totales de activos y patrimonio neto también comprueban
el rango al consultarse. La suma y resta del neto no desbordan en pasos
intermedios. El proveedor no duplica este cálculo ni publica líquidos envueltos.

Los errores técnicos se propagan como `IndicatorReadFailure(read)` conservando
causa y stack. Un año ajeno o un ID repetido devuelto por presupuesto se rechaza
como `invalidInputs`. Ningún fallo técnico se convierte en foto ausente,
presupuesto vacío o un motivo financiero de «sin dato».

`LocalBackupSession.indicatorInputs()` resuelve la conexión activa por visita,
siguiendo los otros servicios de sesión. Tras restaurar, el consumidor debe
volver a resolverlo; no se conserva un proveedor de la conexión cerrada. La
prueba restaura una copia real y contrasta patrimonio, presupuesto y revisión.

## Alcance y verificación

Se utiliza el ticket completo aportado por el usuario: no hay conector Epic
Board en esta sesión y no se modifica el estado del tablero. No se implementan
la fórmula, el formateo ni la UI de los siguientes tickets de EP-023. No hay
cambios de plataforma ni aceptación visual asociada a esta entrega.

Las pruebas usan exclusivamente datos sintéticos y el CSV de referencia
EP-001. Cubren foto exacta, pendientes, vigencia, liquidez histórica,
presencia mensual, signos, varios hermanos/raíces, archivo/traslado, origen
CSV, cantidades extensas, límites de año, errores y desbordamientos,
snapshot de dos conexiones, ausencia de escrituras y restauración real.

Comprobaciones locales del 2026-10-15:

- Flutter 3.47.0 y Dart 3.13.0 comprobados con `flutter --version` y
  `scripts/check-toolchain.ps1`. `flutter pub get --enforce-lockfile` correcto,
  sin cambiar el lockfile. La consulta a pub.dev precisó acceso de red permitido.
- `scripts/check-quality.ps1`: 435 archivos con formato correcto y análisis
  completo sin incidencias. La batería general terminó con 1.805 pruebas
  correctas y cuatro fallos; el script completo no queda verde.
- Tres fallos de navegación: `movement_lifecycle_test.dart` en Android y
  `pending_lifecycle_test.dart` en Windows y Android, por `Bad state: No element`
  al buscar controles. Se reproducen en una copia aislada de `265df7d`, sin
  ninguno de los cambios de MA-TSK-183. Esa copia conserva los archivos de
  sincronización concurrentes necesarios para compilar, igual que el checkout
  compartido; no se atribuye el resultado a un HEAD puro.
- El cuarto fallo fue `wealth_photo_screen_test.dart`, caso «Ruta conserva
  febrero, Atrás protegido y guardado actualiza origen con pendientes»: la
  etiqueta «Foto completa» no apareció dentro de la espera de la prueba.
  El caso pasa por separado con el código anterior. Con el código actual
  pasa el archivo completo de fotos en la ejecución dirigida siguiente.
  Se registra la intermitencia observada; no se afirma corregida ni se cambia
  la UI o sus esperas en este ticket.
- `flutter test --no-pub test/indicators test/wealth/wealth_reading_test.dart
  test/wealth/wealth_reading_overflow_test.dart
  test/wealth/wealth_photo_screen_test.dart test/architecture_test.dart`:
  57 pruebas correctas. Incluye las 19 pruebas nuevas (14 del proveedor y
  cinco de desbordamientos), el motor existente, las lecturas patrimoniales,
  toda la pantalla de fotos y las fronteras de arquitectura.
- Las cuatro variantes del arranque (`development`, `test`, `production` e
  `invalid-synthetic`): correctas, una prueba cada una. Se ejecutan por separado
  porque los fallos generales impiden alcanzar esa fase del script.
- `git diff --cached --check`: sin errores de espacios. Se confirman únicamente
  los archivos propios del ticket; los cambios concurrentes quedan fuera.

No se ejecutan builds Windows/APK ni validación visual nativa: esta entrega
no cambia plataformas ni UI y no sustituye la aceptación visual de EP-026.
