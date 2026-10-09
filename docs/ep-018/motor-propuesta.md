# MA-TSK-150 · Motor y contrato de propuesta presupuestaria

Implementa el ticket completo facilitado en la conversación para EP-018. Usa
EP-001 §3 y caso H, el flujo de propuesta de EP-002, las lecturas completas de
EP-010 (`MovementRepository.readYear`) y el árbol actual de EP-008
(`CategoryManagement.list`). No depende de EP-016 ni de una matriz anual.

## API pública y composición

Importar `features/budget/budget.dart`. `BudgetProposalCalculator.calculate`
recibe un año fuente entre 1 y 9998 y devuelve `BudgetProposalDraft` para
fuente + 1. El año 9999 produce el error tipado `invalidSourceYear` con el
mensaje «El año 9999 no tiene un año siguiente válido.». No hay cálculo parcial
ante un error de lectura o desbordamiento.

`app/budget_proposal_factory.dart` conecta repositorios y unidad de trabajo
SQLite sobre la misma conexión. Categorías, reales, partidas destino y estado
del dataset se leen en una sola transacción. El cálculo no crea, modifica ni
borra registros ni incrementa la revisión. Conserva `budget → movements`, ya
declarada por EP-011, sin modificar el grafo ni los repositorios compartidos.

Por cada raíz activa genera doce filas, ordenadas por ruta/UUID y mes:

- `sourceRows`: UUID y ruta actuales, tipo de raíz, mes fuente/destino,
  real fuente, importe propuesto, cantidad de reales y aviso de signo.
- `allocations`: `BudgetInput` de la raíz por mes destino; cero es una
  asignación explícita. No asigna partidas a descendientes ni categorías archivadas.
- `includedScopes`: raíz/mes que delimita la futura sustitución. Quitar un
  padre durante el desglose no elimina su ámbito de sustitución.
- `excludedReals`: registros fuente sin categoría o bajo raíz archivada,
  con UUID, fecha, importe, UUID de categoría, ruta cuando existe y motivo.
  Son avisos no bloqueantes: no se atribuyen a otra raíz ni se borran.
- `basis`: instantánea comparable de los datos pertinentes al cálculo y al
  futuro plan de sustitución. Todas las colecciones copian sus entradas y
  son inmutables, también las listas del plan de guardado.

## Reglas de cálculo

El mes procede de la fecha de valor. Cada real se atribuye exactamente una
vez a su raíz actual, incluidos reales directos y de descendientes de hasta
tres niveles. Un descendiente archivado bajo raíz activa sigue aportando al
real de su raíz; nunca recibe una nueva partida. Una raíz archivada excluye
su rama completa del destino. Sin clasificar conserva categoría `null`.

Se suman ingresos, salidas, ahorro, transferencias y abonos algebraicamente,
sin tratamientos especiales por concepto, cuenta o signo individual. La suma
usa `BigInt`; tras agregar se redondea `ceil(abs(neto)/1000)*1000` céntimos y
se recupera el signo. No usa coma flotante ni redondea movimientos por separado.
El real neto y el propuesto deben caber en int64; se rechaza `overflow` si
el agregado o su redondeo no cabe. Los intermedios pueden exceder int64 y
cancelarse antes de validar el resultado final. Los múltiples exactos y cero
se conservan. La cantidad de reales permite distinguir ausencia de un neto cero
por compensación; ambos producen una partida de cero.

Solo el signo del neto de la raíz determina `requiresSignReview`: ingreso
negativo o salida positiva. `signsReviewed` nace falso; calcular no equivale
a aprobar los signos. La revisión de datos excluidos no añade un bloqueo.

## Traspaso independiente a T02 y T03

T02 puede construir otra instancia de `BudgetProposalDraft`, manteniendo
`sourceRows`, `basis` y el ámbito, con nuevas `allocations` y revisión explícita
de signos. Al desglosar debe retirar la asignación padre de ese mes. Este ticket
entrega el modelo; no implementa comandos de edición ni reglas de validación
del editor. El constructor no certifica que un borrador editado sea guardable.

T03 dispone de `BudgetProposalSavePlan` con borrador, `before` y `after`:
`before` contiene las partidas originales, incluidas retiradas; `after` contiene
las nuevas asignaciones, incluidos ceros. Construir el plan no escribe ni
confirma la sustitución. T03 debe calcular la comparación anterior/nueva/retirada,
validar categorías activas, año/ámbito, duplicados y padre/descendiente, exigir
revisión de signos y confirmación, y aplicar todo en una transacción atómica.
No debe usar las doce filas raíz como sustituto de las asignaciones editadas.

`basis.targetBudgets` contiene partidas del año destino en las raíces activas
incluidas, también de descendientes archivados: se necesitan para comparar y
detectar solapamientos. No incluye partidas de raíces archivadas excluidas.
Si T02/T03 permite seleccionar menos ámbitos, T03 debe restringir comparación,
revalidación destino y escritura a esa selección explícita.

`BudgetProposalBasis.hasSameRelevantData` compara dataset, año fuente, árbol
actual completo, UUID/fecha/categoría/importe de cada real fuente y datos completos
de partidas destino del ámbito inicial. Ordena por UUID, sin depender del orden
de consultas. Detecta incluso cambios que conservan el mismo neto. La revisión
global se expone como información; no basta para aceptar ni rechazar el guardado.
Cambiar presupuesto fuente, reales de otros años, fotos o concepto/cuenta de
un real no altera la comparación. Cambiar árbol, reales fuente, datos excluidos
revisados o partidas destino exige releer/revisar la propuesta. El árbol completo
se compara de manera conservadora porque define raíces, rutas y destinos
disponibles para desglose. T03 debe releer y comparar dentro de su transacción
de guardado, antes de escribir, incluso si la revisión global no cambió.

La interfaz y el guardado quedan para sus tickets; la UI de EP-018 espera
aprobación explícita de su mockup y la entrega de edición y guardado. No se añaden
inflación, porcentajes, movimientos editables, Drive ni nuevos informes.

## Verificación

`test/budget/budget_proposal_calculator_test.dart` usa SQLite en memoria y datos
sintéticos. Cubre el CSV EP-001 completo y caso H, ingreso/salida, ahorro y
transferencias, tres niveles y suma antes de redondear, UUID con nombres iguales,
histórico archivado, exclusiones visibles, neto cero/ausencia, signos atípicos,
límites civiles, intermediarios superiores a int64, desbordamientos de agregado
y redondeo, datos para revalidar y errores de lectura. Compara todas las tablas
SQLite antes/después en casos normales y rechazos para comprobar ausencia de
escrituras. Las pruebas de arquitectura verifican las fronteras de módulos.

Verificación final del 2026-10-09:

- Flutter 3.47.0/Dart 3.13.0 comprobados con `flutter --version` y
  `scripts/check-toolchain.ps1`; dependencias resueltas con
  `flutter pub get --enforce-lockfile`, sin modificar SDK ni lockfile.
- Ejecución dirigida: 13 pruebas del motor y 2 de arquitectura correctas.
- `scripts/check-quality.ps1`: correcto; formato sin cambios, análisis sin
  incidencias, 1.440 pruebas correctas y las cuatro variantes de `APP_ENV`
  verificadas. Los cinco avisos de estilo del primer análisis se corrigieron.
- `git diff --cached --check`: sin errores de espacios.

No se requieren compilaciones nativas: no se modifican plataformas, plugins ni
pantallas. No se afirma verificación visual ni guardado atómico de T03.

Los cambios preexistentes de sincronización, README y otros prototipos no forman
parte de la entrega. Se respeta la rama configurada `ticket/ma-tsk-113`; no se
fuerza la subida ni se incluyen archivos de otros tickets.
