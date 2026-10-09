# MA-TSK-152 · Comparación y guardado atómico de la propuesta

Implementa el ticket completo facilitado en la conversación, sobre el
[contrato del motor](motor-propuesta.md), el [editor de sesión](edicion-borrador.md),
EP-001 §3/caso H y la [confirmación de EP-002](../ep-002/entrega-flutter.md).
Reutiliza `BudgetRepository`, `UnitOfWork` y la validación de EP-011. No cambia
SQLite, sus migraciones ni sus repositorios. No hay conector Epic Board disponible
en esta sesión; no se ha leído ni modificado el estado del tablero.

## API e integración

Importar `features/budget/budget.dart`. `createBudgetProposalSaver` en
`app/budget_proposal_factory.dart` conecta motor, repositorio y unidad de trabajo
sobre la misma conexión. Crear un coordinador por sesión de propuesta.

```dart
final saver = createBudgetProposalSaver(
  database: database,
  invalidation: categoryInvalidation,
);
final review = await saver.review(editor.validatedDraft());
// Mostrar review.changes y review.confirmationLabel. Cancelar no llama a save.
// Invocar únicamente tras pulsar expresamente la acción indicada:
final result = await saver.save(
  review,
  confirmation: review.requiredConfirmation,
);
```

`review` valida y relee antes de entregar una comparación inmutable. No modifica
datos financieros ni incrementa la revisión. Rechaza un borrador ya obsoleto;
no recalcula silenciosamente sus asignaciones editadas. El consumidor conserva
el borrador y comunica que debe calcular y revisar una propuesta nueva.

`BudgetProposalReview.plan` reutiliza `BudgetProposalSavePlan`: `before` incluye
todas las partidas existentes de las raíces/meses seleccionados, también padres,
descendientes de hasta tres niveles y descendientes archivados; `after` incluye
las asignaciones editadas, incluidos ceros. `changes` une ambos conjuntos por
UUID de categoría y mes, ordenado por mes, ruta completa y UUID. Expone
`added`, `updated`, `unchanged` y `removed`, con anterior/nuevo y `null` para
ausencia. Dos rutas iguales mantienen identidades distintas. Una retirada nunca
se presenta como un cero nuevo.

Sin partidas existentes la acción es **Guardar propuesta** (`saveProposal`).
Si existe cualquier partida afectada, incluso con el mismo importe, exige
**Sustituir partidas** (`replaceItems`). No hay confirmación por defecto; una
acción incorrecta se rechaza sin cambios. El constructor de la revisión es
privado y una revisión de otro coordinador no autoriza escribir. Construir el
plan público del motor tampoco permite guardar.

## Transacción, alcance y concurrencia

`save` abre una sola unidad de trabajo que abarca relectura, validación,
retiradas, actualizaciones y altas. El motor relee dentro de esa transacción
mediante las transacciones anidadas existentes; no se reutiliza una caché.
Se comprueban identidad del dataset, árbol completo, UUID/fecha/categoría/importe
de todos los reales fuente y datos completos de partidas destino en los ámbitos
incluidos. Cambios que conservan el neto, o que no incrementan la revisión global,
también invalidan. Una fuente que ahora desborda exige revisión nueva.

La comparación destino se restringe a `includedScopes`, incluso si el consumidor
selecciona menos raíces/meses que el cálculo inicial. Retirar un padre del
borrador no retira su ámbito de sustitución. Meses y raíces ajenos, presupuesto
del año fuente, otros años de reales, cuentas y fotos no se sustituyen. Cambiar
concepto/cuenta/procedencia de un real no cambia su aporte financiero. El árbol
y los reales fuente completos se comparan conservadoramente según MA-TSK-150,
incluidos los excluidos que se muestran para revisión no bloqueante.

Se vuelve a ejecutar `BudgetProposalDraftValidator` dentro de la transacción:
año y ámbito, categorías y ascendencia activas, duplicados, padre/descendiente
y revisión explícita de signos. Se usan además las filas fuente recién calculadas
para impedir que un borrador construido manualmente oculte avisos de signo.
Se validan conceptos y los repositorios/triggers existentes validan cada escritura.
No se permiten nuevas asignaciones archivadas ni inversiones de signo CSV.

Las retiradas se borran primero para liberar padre/descendientes. Las partidas
del mismo nodo/mes conservan ID, fecha de alta, concepto, discrecionalidad y
procedencia CSV exactos; solo se modifica el importe. Los registros sin cambio
no se escriben ni cambian timestamps. El borrado conserva filas/lotes de
importación, por lo que repetir el CSV no resucita retiradas.

Drift SQLite inicia `BEGIN IMMEDIATE`: otra conexión no puede confirmar una
escritura entre la relectura y el commit. Los cambios confirmados antes de entrar
se rechazan como `staleReview`, sin sobrescribirlos. Una revisión invalidada
permanece invalidada aunque después se restauren las cifras anteriores; se
necesita una revisión nueva.

Un fallo revierte todas las escrituras y el incremento de revisión. La revisión
y el borrador siguen intactos para reintento manual ante fallo técnico. Las
mutaciones efectivas del guardado incrementan la revisión del dataset una sola
vez; un plan completamente idéntico no incrementa ni modifica timestamps.

El doble envío de una misma revisión comparte la operación pendiente. Tras un
éxito, el reintento devuelve el mismo acuse `BudgetProposalSaveResult` sin escribir,
incluso si luego se editan partidas. Dos revisiones distintas del mismo destino
no duplican: la segunda queda obsoleta tras el primer commit. Los acuses viven
solo en la sesión, igual que el borrador; tras reiniciar se calcula/revisa de
nuevo y las partidas existentes exigen confirmación de sustitución.

Los errores públicos tienen mensaje español y código: `staleReview`,
`invalidReview`, `confirmationRequired`, `persistence`. Los errores de validación
del editor, presupuesto y cálculo conservan sus tipos. No se exponen SQL ni datos
técnicos en los mensajes de guardado.

## Verificación y alcance de entrega

`test/budget/budget_proposal_saver_test.dart` contiene 32 pruebas con datos
exclusivamente sintéticos y SQLite de fichero:

- Caso H/CSV completo, edición a −370 EUR, desglose, signos y ceros explícitos;
  conservación de 2026, movimientos y fotos; reapertura.
- Comparación de partidas añadidas, actualizadas, iguales y retiradas, rutas
  repetidas, tres niveles y partidas archivadas; confirmación y selección parcial.
- Identidad, metadatos, alta y origen CSV conservados; repetición segura tras
  retirada; ninguna renormalización de signos al guardar.
- Fallos SQLite después de DELETE, UPDATE, INSERT y registro final de revisión:
  comparación de todas las tablas y revisión antes/después, reintento correcto.
- Quince variantes de cambios desde otra conexión (fuente, excluidos, mismo neto,
  árbol, destino, metadatos e identidad del dataset), sin sobrescritura.
- Cambio sin incremento global, invalidación permanente y desbordamiento fuente;
  cambios ajenos aceptados; carrera WAL con escritor bloqueado dentro del guardado.
- Doble envío, acuse repetido, edición posterior y dos revisiones simultáneas;
  validación de signos, borradores inválidos y sesión de revisión distinta.

No se añaden pantallas; la UI de EP-018 mantiene su requisito de aprobación
explícita del mockup y entrega de edición/guardado. No cambian plataformas o
plugins y no se requieren builds nativos. No se afirma verificación visual.
No se cierra la épica completa con este ticket.

Comprobaciones del 2026-10-09, Flutter 3.47.0/Dart 3.13.0:

- `flutter --version` y `scripts/check-toolchain.ps1` correctos; dependencias
  resueltas con `flutter pub get --enforce-lockfile`, sin cambiar SDK ni lockfile.
- 81 pruebas dirigidas correctas: guardado (32), motor (13), editor (20),
  gestión de partidas (9), repositorio (5) y arquitectura (2).
- `scripts/check-quality.ps1`: formato de 319 archivos sin cambios y análisis
  sin incidencias. La batería general termina con 1.490 correctas y dos fallos
  en archivos existentes no modificados: timeout de 45 s al cerrar
  `categoryInvalidation` en `budget_lifecycle_test.dart` (Android), y ausencia
  temporal del texto «Pendientes: Z Deuda sintética» en
  `wealth_photo_screen_test.dart`. No se declara la batería general correcta.
- Repetición de ambos archivos con `flutter test --no-pub --concurrency=1`:
  17 pruebas correctas, incluidos los dos casos que fallaron en la ejecución
  general. No se modifica el código de esos recorridos.
- Cuatro variantes de `APP_ENV` verificadas separadamente (development, test,
  production e invalid-synthetic), todas correctas, porque el fallo general
  detuvo el script antes de ese paso.
- `git diff --cached --check`: sin errores de espacios.

Se respeta la rama configurada `ticket/ma-tsk-113`. README, sincronización y otros
prototipos preexistentes pertenecen a otros tickets y quedan fuera del commit.
