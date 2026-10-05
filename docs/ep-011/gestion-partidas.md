# MA-TSK-100 · Gestión de partidas mensuales

`budget.dart` publica `BudgetManagement`, `BudgetFailureCode` y
`BudgetConflict`. La composición inyecta el `BudgetRepository` existente y
su `UnitOfWork` sobre la misma conexión. No se añade persistencia, esquema,
cuentas ni movimientos al presupuesto.

## Uso por los consumidores

```dart
final management = BudgetManagement(
  repository: budgetRepository,
  unitOfWork: database,
);
final record = await management.create(
  month: BudgetMonth(2026, 1),
  categoryId: categoryId,
  amountCents: -35025,
);
await management.edit(record.id, month: BudgetMonth(2026, 2), amountCents: 0);
// Tras la confirmación explícita de borrado en la interfaz:
await management.delete(record.id);
```

El importe es un entero firmado en céntimos; cero crea o corrige una partida,
nunca la borra. `edit` modifica únicamente mes, categoría e importe
suministrados. Conserva ID, concepto y discrecionalidad exactos, fecha de alta,
fila de origen, lote y ordinal CSV. Lee y escribe en una única unidad de
trabajo. Repetir una edición ya aplicada no modifica timestamps ni revisión.
La API inferior `BudgetRepository.edit` sigue siendo una sustitución completa
de `BudgetInput`, para consumidores que necesiten editar también sus textos.

Los consumidores distinguen `BudgetFailure.code`, sin interpretar el mensaje:

| Código | Significado |
|---|---|
| `duplicateCategoryMonth` | Ya existe una partida en esa categoría y mes. |
| `ancestorDescendantConflict` | Hay partidas en un ancestro o descendientes del mismo mes. |
| `categoryNotFound` / `categoryArchived` | Destino inexistente o nueva asignación a un nodo archivado. |
| `notFound` | La partida ya no existe, también en un segundo borrado. |
| `invalidMonth` / `invalidAmount` / `invalidConcept` | Mes inválido, signo CSV imposible de normalizar o concepto vacío en la API inferior. |
| `persistence` | Fallo técnico; la gestión entrega un mensaje español sin exponer SQL. |

Cada elemento de `conflicts` contiene el mes solicitado, categoría y ruta
completa solicitadas, y el ID, categoría y ruta completa de una partida
existente. Se devuelven todos los conflictos, incluidos ceros y referencias
archivadas, bajo el árbol actual. Los UUID distinguen nombres duplicados.
El mensaje explica el rechazo; la operación no borra, reparte ni sustituye
otras partidas. Hermanos y meses diferentes siguen siendo válidos.

Archivar conserva referencias. Una corrección puede mantener su categoría
archivada; crear o cambiar a una categoría archivada se rechaza. El borrado
conserva `import_rows` e `import_batches`: repetir la huella CSV sigue dando
«ya importado» y no resucita la partida. No hay reintentos automáticos.

## Verificación

`test/budget/budget_management_test.dart` usa SQLite de fichero y datos
sintéticos: céntimos extremos, cero, hermanos, ambos sentidos del conflicto,
duplicados y contexto completo, edición CSV parcial, conservación de todas
las columnas históricas y reapertura, rechazo y corrección sin duplicados,
archivo, borrado y repetición CSV. Un trigger temporal provoca un aborto
después del UPDATE y comprueba rollback de datos y revisión, seguido de un
reintento manual correcto.

También se verifican las pruebas existentes del repositorio, las lecturas
financieras A–G y la reorganización de categorías de EP-008, además de las
fronteras de arquitectura. Se conserva el esquema y sus triggers SQLite.
No se implementan pantallas; su aprobación y entrega pertenecen a los tickets
correspondientes de EP-011. Este cambio no afecta plataformas, por lo que no
se ejecutan builds ni pruebas nativas Windows/Android.

No hay conector Epic Board disponible en esta sesión: se utiliza el ticket
completo facilitado por el usuario y no se cambia el estado del tablero.

Resultado local del 2026-10-05, Flutter 3.47.0 / Dart 3.13.0:

- Dependencias resueltas con `--enforce-lockfile`, sin modificar lockfile ni SDK.
- 35 pruebas dirigidas correctas (nueve nuevas de gestión, presupuesto,
  lecturas de referencia, reorganización y arquitectura).
- `scripts/check-quality.ps1`: formato sin cambios y análisis sin incidencias;
  batería general con 1.010 pruebas correctas y un fallo al esperar el aviso
  temporal «2 movimientos categorizados» del recorrido Android de EP-010.
  El archivo `movement_lifecycle_test.dart` repetido aisladamente pasa sus
  dos recorridos Windows/Android. No se modifica ese código ajeno al ticket.
- Las cuatro variantes de arranque `APP_ENV` se verifican separadamente
  porque el fallo anterior detuvo el script antes de esa fase.
- `git diff --check` sin errores en los archivos del ticket.

Las pruebas con SQLite requieren ejecutarse fuera del sandbox local para
permitir los bloqueos de fichero de recuperación. La prueba dentro del
sandbox falla al abrir el store, también para el repositorio preexistente;
no se altera la política de bloqueos para evitar esa limitación del entorno.
