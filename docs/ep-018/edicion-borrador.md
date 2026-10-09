# MA-TSK-151 · Edición y desglose del borrador de propuesta

Implementa el ticket completo facilitado por el usuario sobre el contrato de
[MA-TSK-150](motor-propuesta.md), EP-001 §3/caso H y el formulario de propuesta
de EP-002. No hay conector Epic Board disponible en esta sesión; no se ha leído
ni modificado el estado del tablero. La interfaz de EP-018 sigue esperando la
aprobación explícita de su mockup y la entrega del guardado.

## API de sesión

Importar `features/budget/budget.dart`. Crear una instancia de
`BudgetProposalEditor` con el resultado de `BudgetProposalCalculator.calculate`.
El editor no recibe repositorios, unidad de trabajo, almacenamiento ni callbacks
de guardado. Conserva una instantánea inmutable en memoria; cada operación
aceptada sustituye esa instantánea y cada rechazo conserva la anterior completa.

- `draft`: instantánea actual, con fuente, ámbitos, exclusiones y `basis`
  conservados. Editar una asignación no modifica el real fuente ni el importe
  originalmente calculado de `sourceRows`.
- `editAmount(month, categoryId, amountCents)`: edición exacta por UUID y mes,
  con signo y cero válido. No redondea, cambia de categoría ni crea reales;
  conserva concepto y discrecionalidad si la entrada los tenía.
- `splitOptions(month, parentCategoryId)`: descendientes activos de ese padre,
  con UUID y ruta completa, ordenados por ruta/UUID. Nombres e incluso rutas
  iguales no confunden identidades. Las opciones pertenecen al árbol de `basis`;
  el guardado deberá releer el árbol actual.
- `split(month, parentCategoryId, allocations, explicitlyEditedTotalCents)`:
  retira exclusivamente la asignación padre de ese mes e inserta descendientes
  elegidos, sin cambiar su ámbito de sustitución. Los hijos heredan el mes.
- `setSignsReviewed(bool)`: representa la casilla «He revisado los signos
  señalados», incluida la posibilidad de desmarcarla.
- `validatedDraft()`: valida estructura y revisión y devuelve la instantánea
  para preparar el guardado; no escribe ni confirma la sustitución.
- `cancel()`: descarta la referencia de sesión y cierra el editor. Puede
  repetirse; cualquier lectura u operación posterior produce `sessionClosed`.
  Una sesión nueva comienza con un cálculo nuevo, sin recuperar ediciones.

## Desglose y validación

Cada destino debe ser un descendiente estricto del padre retirado, de su misma
raíz, dentro de tres niveles y con toda su ascendencia activa. Se rechazan
desconocidos, archivados, padre propio, otra rama y desglose vacío. Cero se
mantiene como asignación explícita.

La suma algebraica de hijos se calcula con `BigInt`, sin coma flotante ni
ajustes automáticos. Debe caber en int64 y conservar el total actual del padre.
Si cambia, el consumidor debe aportar `explicitlyEditedTotalCents` con el nuevo
total que la persona haya editado expresamente; la suma debe coincidir exactamente.
También se puede editar primero el padre y después distribuir su nuevo importe.
Una aprobación genérica de la diferencia no equivale a editar ese total.

`BudgetProposalDraftValidator.validate` es una validación pura pública para el
traspaso a T03. Comprueba año fuente/destino, ámbito raíz/mes, categorías activas,
profundidad, duplicados nodo/mes y padre/descendiente. Permite hermanos y niveles
distintos entre meses, y hojas de nivel tres junto a una categoría de nivel dos
de otra subrama. Todas las operaciones del editor ejecutan esta validación antes
de publicar la nueva instantánea. Los fallos son `BudgetProposalEditFailure`
con código estable y mensaje español.

## Signos y traspaso al guardado

`BudgetProposalDraft.signWarnings` expone avisos inmutables con origen
`sourceReal`/`allocation`, mes, UUID, ruta e importe firmado. Ingreso negativo o
salida positiva usa siempre el tipo de la raíz. Un desglose puede introducir
un aviso individual aunque su total conserve el signo habitual. Los avisos de
real fuente permanecen aunque se corrija manualmente la propuesta; el real
fuente no se convierte en esa edición.

`requiresSignReview` incluye fuente y asignaciones actuales. Si hay avisos,
`validatedDraft()` y el validador por defecto exigen `signsReviewed`. Los reales
excluidos de MA-TSK-150 siguen visibles y no añaden bloqueo de signos.

El contrato del motor tiene una sola casilla global: cualquier cambio efectivo
de importe o distribución invalida esa revisión global, incluso si la suma se
conserva o permanece el mismo conjunto de avisos. Repetir el mismo importe es
una operación sin cambios y conserva la revisión. Un rechazo tampoco la invalida.
La casilla nunca se marca automáticamente tras una edición o desglose.

El constructor público de `BudgetProposalDraft` no certifica un guardado. T03
debe usar las asignaciones editadas, comparar partidas anteriores/nuevas/retiradas,
exigir confirmación, releer los datos relevantes de `basis` y revalidar dentro de
la transacción de escritura. Esta sesión no implementa persistencia, detección
de concurrencia, sustitución de partidas ni una pantalla. No introduce
inflación, porcentajes, edición de reales, Drive o informes.

## Verificación y entrega

Datos exclusivamente sintéticos. Las 19 pruebas unitarias del editor cubren
edición firmada/cero, conservación de fuente/metadatos, desglose por mes hasta
nivel tres, identidad por UUID, totales, errores sin mutación, duplicados,
padre/descendiente, cuarto nivel, ascendencia archivada, límites int64, signos,
invalidación de revisión, cierre y nueva sesión. La prueba integrada adicional
usa el CSV EP-001/caso H y compara todas las tablas SQLite y su revisión después
de editar, desglosar, revisar, validar, cancelar y recalcular: ninguna escritura.

El motor de MA-TSK-150 y las fronteras de arquitectura se verifican junto al editor.
Se ha comprobado Flutter 3.47.0/Dart 3.13.0 y resuelto dependencias con
`flutter pub get --enforce-lockfile`, sin cambios de SDK ni lockfile.
El análisis estático dirigido no encontró incidencias.

Comprobación completa del 2026-10-09 con `scripts/check-quality.ps1`: correcta;
formato sin cambios, análisis sin incidencias, 1.460 pruebas correctas y las
cuatro variantes de `APP_ENV` verificadas. `git diff --cached --check` no detecta
errores de espacios.
No se requieren builds nativos: no cambian plataformas, plugins o pantallas.
No se afirma verificación visual ni guardado de T03.

Se respeta la rama configurada `ticket/ma-tsk-113`; únicamente los archivos de
MA-TSK-151 pertenecen a esta entrega. Los cambios concurrentes de sincronización,
README y prototipos quedan fuera del commit. No se cierra la épica completa con
este ticket.
