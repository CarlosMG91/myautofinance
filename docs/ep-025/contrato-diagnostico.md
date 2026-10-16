# MA-TSK-197 · Contrato de diagnóstico financiero v1

## Alcance y propiedad

Consulta de solo lectura de `http://localhost:4310/api/data` el 2026-10-16:
tablero **My autofinance**, workspace de este repositorio, MA-EPIC-196 y
MA-TSK-197/198. Ticket y criterios coinciden con la petición; sin adjuntos.
No se cambia el estado administrativo del tablero.

`lib/features/diagnostics/diagnostics.dart` publica el dominio propietario
EP-025. Se registra como noveno módulo técnico sin ejecutar controles al
arrancar. No se alojan reglas financieras en core ni se altera EP-001.
MA-TSK-198 aportará el ejecutor y sus consultas consistentes por constructor;
MA-TSK-199/201 conservan el diseño aprobado y su implementación. Este ticket
no implementa SQL nuevo, lectores, UI ni reparación y no abre bases personales.

## Catálogo y ejemplos de clasificación

Los códigos son literales explícitos (`DiagnosticRule.code`), independientes
del índice/nombre del enum. La severidad pertenece a la regla: error para
invariantes incumplidas, aviso para coincidencias que requieren revisión
humana y pendiente para información permitida aún por completar. Ninguna
severidad autoriza escrituras.

| Código estable | Severidad / ámbito | Evidencia y ejemplo sintético | Acción tipada |
|---|---|---|---|
| `integridad_local` | error / base | `IntegrityEvidence`: código del control y detalle identificable; `integrity_check` informa de una página dañada. Incluye invariantes de árbol, vigencia, liquidez o procedencia que no sean referencias o conflictos específicos. | `OpenLocalRecovery` |
| `referencia_invalida` | error / base | `BrokenReferenceEvidence`: tipo/ID propietario, campo y tipo/ID destino inexistente. Real `real` con `category_id = ausente`, ID no encontrado. | `OpenDiagnosticCatalog` del tipo destino; nunca enlazar al UUID roto. |
| `presupuesto_solapado` | error / base | `BudgetOverlapEvidence`: las dos partidas con IDs, categorías, importes y mes. `padre` en raíz y `hijo` en descendiente, ambos en enero de 2026, incluso con importes cero. El ejecutor acredita la ascendencia con el árbol actual. | `OpenBudgetMonth(enero, padre)`; ambas partidas están en evidencia. |
| `importacion_repetida_persistida` | error / base | `RepeatedImportEvidence`: dos lotes persistidos distintos y misma SHA-256 de bytes originales. Corrupción sintética: lotes `a` y `b`, huella `aaaa…` de 64 caracteres. | `OpenImportBatch(a)`; los demás IDs se conservan. |
| `coincidencia_entre_lotes` | aviso / base | `ImportCoincidenceEvidence`: dos reales con IDs, lotes distintos y fila/ordinal. Mismo Café de 5 de enero, cuenta e importe −10 EUR. No demuestra duplicidad. | `OpenImportBatch(a, ordinal: 2)`; segundo origen en evidencia. |
| `movimiento_sin_categoria` | pendiente / base | `UncategorizedMovementEvidence`: real con categoría nula, cuenta válida y −10 EUR; puede ser manual, sin lote. | `OpenPendingMovement(real)` hacia bandeja EP-015. |
| `foto_ausente` | pendiente / mes elegido | `WealthPhotoEvidence`: estado absent de enero, fichas vigentes pendientes, sin inventar ID de foto. Si no hay fichas vigentes, ausencia sigue siendo sin dato. | `OpenWealthPhoto(enero)` |
| `foto_incompleta` | pendiente / mes elegido | `WealthPhotoEvidence`: estado incomplete de enero, IDs de ahorro/deuda pendientes. Conserva valores y pendientes, aunque los líquidos estén valorados. | `OpenWealthPhoto(enero)` |
| `indicador_sin_dato` | pendiente / mes elegido y su año de ingresos | `UnavailableIndicatorEvidence`: evaluación original EP-023, ID/versión, mes y causa prioritaria con detalle. Enero sin salario de marzo: `ingresos_incompletos`, mes pendiente 3. | `OpenWealthPhoto` para foto; `OpenIncomeBudget(año)` para ingresos. |

`test/diagnostics/diagnostic_contract_test.dart` contiene un ejemplo y prueba
de clasificación por regla, severidad, ámbito e identidad de sus acciones.
Las listas propias del contrato son inmutables. La evidencia usa registros
inmutables de sus dominios, no nombres como identidades ni texto formateado.
Construir evidencia representa un hecho acreditado; no ejecuta búsquedas ni
certifica por sí solo corrupción SQLite.

## Controles reutilizados y nuevas comprobaciones retrospectivas

`DiagnosticControl.existingValidation` identifica controles ya existentes:

- Integridad/referencias: EP-004, `LocalDatabase._checkIntegrity`,
  `schema_policy.dart`, `integrity_check`, `foreign_key_check` y consultas
  `categoryIntegrityErrors`, `movementIntegrityErrors`, `wealthIntegrityErrors`,
  `accountCoverageErrors`, `budgetIntegrityErrors`. El adaptador T02 vivirá
  junto al acceso SQLite; dominio no importa app/data ni Drift.
- Presupuesto: EP-004/011/012, unicidad y ascendencia, `BudgetConflict` y
  validación existente. T02 identificará ambos registros persistidos.
  Duplicar mismo nodo/mes es fallo de unicidad/integridad; esta regla específica
  describe padre/descendiente. Incluir años históricos y categorías archivadas.
- Repetición exacta: SHA-256 única global de EP-004/012, repositorio de lotes
  y `ImportAlreadyImported`. No exigir archivo original no conservado ni
  confundir un destino borrado con procedencia inválida.
- Coincidencias: criterio de `ValidatingImportPreviewer` EP-012, reutilizado
  por CSV EP-013 y el contrato de adaptadores EP-014: misma cuenta, fecha de
  valor, céntimos y concepto `trim().toLowerCase()`. Categoría/discrecionalidad
  no participan. T02 acreditará ese criterio sin otro lector/comparador; el
  constructor exige dos procedencias de lotes distintos.

La exposición retrospectiva sobre toda la base será nueva en T02; aquí no
se reimplementan validadores. `retrospectiveCheck` identifica los pendientes
de categoría, fotos e indicador: nuevas comprobaciones de diagnóstico que
reutilizan estados/lecturas de sus propietarios, sin restringir datos válidos.
EP-014 aporta el contrato común de origen; este ticket no acredita lector XLS.

## Ausencias y casos válidos

- Categoría nula es pendiente; ID no nulo inexistente es referencia inválida.
  Una referencia archivada/histórica conservada no está rota: no exigir que
  esté activa hoy. Vigencia se evalúa en el mes propio del registro.
- Dos reales idénticos del mismo lote con ordinales distintos son legítimos,
  se conservan y no producen coincidencia entre lotes. Una repetición segura
  rechazada con cero altas no tiene evidencia de duplicación persistida.
  Dos lotes distintos coincidentes solo generan aviso: nunca borrar/fusionar.
- Presupuesto cero es válido y participa en la restricción padre/descendiente.
  No tiene cuenta. Meses y ramas sin presupuesto son válidos: no hay regla de
  «falta presupuesto» general ni se vuelve a normalizar el signo del CSV.
  Ingresos incompletos pueden impedir el indicador sin ser error estructural.
- Foto completa con valores cero es válida; ausencia no es cero. No conciliar
  saldos con movimientos ni arrastrar fotos. Solo evidencia del mes elegido,
  usando `WealthRepository.read` y fichas vigentes (alta/baja inclusivas).
  Se rechazan pendientes con fichas futuras o ya dadas de baja en ese mes.
  No recorrer doce meses para generar pendientes patrimoniales.

Estas excepciones se contrastan también con las regresiones existentes de
repositorios/importación/indicador; no se escribe un motor paralelo para probarlas.

## Compatibilidad con EP-023

Se recibe `IndicatorEvaluation` y su `UnavailableIndicator` original,
conservando ID/versión, causa y detalle, sin fórmula ni suma de entradas.
La precedencia pertenece al catálogo/cálculo EP-023: foto ausente, incompleta,
ingresos incompletos, nulos, negativos. Se muestra únicamente el resultado
prioritario recibido. Se comprueba que código/texto pertenecen a la definición
y se reconocen sus destinos v1; las fichas y meses pendientes se conservan.

Líquidos cero con ingresos completos positivos es indicador calculado.
Doce presupuestos de ingreso cero dan `ingresos_nulos`, pendiente sin invalidar
esas partidas. Un fallo técnico, proveedor ausente o causa futura sin adaptar
no se inventa como causa financiera: la regla queda no ejecutada con motivo.
No se depende de la UI del indicador.

## Resultados de sesión y traspaso a T02

`DiagnosticRuleResult.completed` solo se construye tras ejecutar íntegramente
la regla: vacío es `conformant`, con evidencias es `findings`. `notRun` exige
motivo `notRequested`, `dependencyUnavailable`, `cancelled` o `readFailure`;
nunca equivale a conforme ni inventa severidad. Las reglas omitidas quedan
no ejecutadas. Cancelación/error/dependencia ausente impiden conformidad global.

`DiagnosticReport` conserva fecha, mes y `DiagnosticRevision` (dataset_id,
revisión y generación local de conexión). Las reglas constan una vez;
se rechazan evidencias patrimoniales/indicador de otro mes. El ámbito
estructural es toda la base: un conflicto histórico conserva su propio mes
en evidencia/acción aunque la pantalla consulte octubre de 2026.

T02 capturará marcador antes/durante/después de una lectura coherente y
descartará o marcará obsoleta una ejecución mezclada. App cambiará la generación
al restaurar/reemplazar/reabrir la base aunque dataset_id/revisión coincidan.
`isObsolete` compara esos tres componentes y el mes. `isConformant` describe
la ejecución almacenada en memoria; presentarla como vigente requiere además
`!isObsolete`. El contrato no consulta revisión ni inicia repeticiones.

Si una base ilegible impide leer el marcador, T02 no inventará uno para crear
informe conforme: devolverá fallo de sesión con `OpenLocalRecovery` y dejará
dependientes sin ejecutar. Una comprobación que obtiene evidencia real de
integridad fallida se conserva como error. No abrir editores de IDs inexistentes:
app resolverá el catálogo/recuperación y comprobará disponibilidad al navegar.
Los destinos usan funciones existentes; dominio no depende de rutas/GoRouter.
Sin persistencia de diagnósticos, historial, exportación ni reparación automática.

Los casos sintéticos EP-001 solo se usan en pruebas aisladas, nunca para
compararlos con cifras personales como hallazgos.

## Verificación de esta entrega

Comprobaciones locales del 2026-10-16:

- Flutter 3.47.0 / Dart 3.13.0 y `scripts/check-toolchain.ps1`: correctos.
  `flutter pub get --enforce-lockfile` correcto al habilitar acceso a pub.dev;
  lockfile sin cambios. El sandbox bloqueó inicialmente esa consulta de red.
- Análisis estático completo: sin incidencias.
- Contrato y arquitectura: 31 pruebas correctas, 29 nuevas y dos existentes.
- Regresión dirigida secuencial: **162 pruebas correctas**, incluyendo las
  anteriores, `budget_repository_test`, `category_reorganization_test`,
  `movement_repository_test`, `wealth_repository_test`, `import_contract_test`,
  `import_preview_test`, `sqlite_import_confirmation_test` y
  `emergency_cushion_calculation_test`. La primera ejecución bajo sandbox
  tuvo 100 correctas y 62 fallos de apertura protegida de las bases sintéticas;
  la misma batería fuera del sandbox pasó completa. No se modifica la
  protección de apertura ni se accede a la base activa.
- `node docs/ep-001/verificar-casos.mjs`: correcto, 48 presupuestos y diez
  reales; resultados y signos EP-001 conservados.

| Criterio | Evidencia verificada |
|---|---|
| Ejemplo por regla, severidad y destinos | 29 pruebas nuevas del contrato y catálogo documentado arriba. |
| Categoría nula pendiente; referencias archivadas válidas | Contrato; regresión de movimientos y reorganización N/O, sin confundir archivo con inexistencia. |
| Repetición segura y dos filas legítimas del mismo lote | Guardas del contrato y confirmación/importación existentes: SHA global, cero altas y ordinales diferentes conservados. |
| Entre lotes solo aviso | Clasificación del contrato y revisión EP-012; se conservan ambos reales al confirmar. |
| Cero, ausencia de presupuesto y partida sin cuenta válidos | Repositorio de presupuesto (primer caso, CRUD/reapertura y esquema sin `account_id`), fotos y cálculo EP-023; no hay regla general de presupuesto ausente. |
| Fotos solo del mes y fichas vigentes | Contrato rechaza otro mes/fichas fuera de vigencia; repositorio patrimonial conserva cero, altas/bajas y ausencias. |
| Causas del indicador y precedencia EP-023 | Pruebas nuevas reciben el cálculo de producción para las cinco causas; se conserva el mismo resultado/detalle y numerador cero calculado. |
| No ejecutada distinta de conforme | Cuatro motivos probados, omisiones nunca verdes; obsolescencia por edición/base/restauración/mes probada. |

- `scripts/check-quality.ps1`, fuera del sandbox: formato de 464 archivos sin
  cambios y análisis sin incidencias. La batería general terminó en 11 min 45 s
  con **1.930 pruebas correctas y dos fallos**, ambos en
  `test/movements/pending_lifecycle_test.dart`, Windows/Android, por
  `Bad state: No element` al buscar un control desde
  `pending_lifecycle_journey.dart:144`. Estos mismos fallos están documentados
  y contrastados antes de esta entrega en
  [MA-TSK-182](../ep-023/motor-indicadores.md) y
  [MA-TSK-183](../ep-023/proveedor-entradas.md). No se modifican sus archivos.
  El script completo **no queda verde**; el fallo detiene la fase APP_ENV.
  La consulta de pub.dev impidió el primer intento dentro del sandbox.

- Las cuatro variantes APP_ENV (`development`, `test`, `production`,
  `invalid-synthetic`) pasan por separado, una prueba cada una. Se ejecutan
  con los mismos permisos que la batería general para acceder a la caché
  nativa de Flutter; el intento bajo sandbox no pudo borrar su DLL de SQLite.
- `git diff --cached --check`: correcto. Solo se incluyen los once archivos
  propios del contrato, registro del módulo, documentación y pruebas;
  README, sincronización y artefactos concurrentes quedan fuera del commit.

Todos los criterios del contrato T01 tienen evidencia en la tabla anterior.
No se requieren builds nativos: contrato Dart y registro técnico, sin cambios
de plataforma/pantalla. La aceptación visual EP-026 sigue independiente;
este ticket no acredita ejecutor T02 ni recorrido integrado T05/T06.
