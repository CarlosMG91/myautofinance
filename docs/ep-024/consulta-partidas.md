# MA-TSK-190 · Consulta común de partidas

El contrato público se exporta desde `features/budget/budget.dart` y amplía
`BudgetListQuery` y `BudgetListReader`, ya utilizados por MA-TSK-162/170.
No incorpora otra lista, editor, ruta ni motor financiero. La navegación y los
filtros visibles continúan en sus tickets propietarios. Para aplicar el
contrato sin romper esos consumidores, Inicio y Estado desactivan la apertura
presupuestaria de Sin clasificar; su diálogo de diferencia ofrece solo los
movimientos reales. El resto de las aperturas conserva su implementación.

## Filtros

- `BudgetListQuery(month: ...)`: mes civil `BudgetMonth`.
- `BudgetListQuery.annual(year, focusedMonth: ...)`: enero–diciembre. El foco
  conserva el contexto de captura, sin reducir los registros al mes enfocado.
- `BudgetListQuery.range(month: ..., firstMonth: ..., lastMonth: ...)`:
  extremos inclusivos, incluso entre años. `month` es contexto de captura;
  los límites efectivos siempre son `firstMonth` y `lastMonth`.
- `categoryId: null`: todas las categorías. UUID selecciona una categoría;
  `MovementCategoryScope.direct` consulta sus partidas propias y `branch`
  incluye sus descendientes en el árbol actual, también archivados.

No hay filtro de cuenta. `unclassified` se conserva en la firma para detectar
llamadas/enlaces anteriores, pero `true` se rechaza con `BudgetFailure`:
«El presupuesto no admite Sin clasificar». Un UUID inválido, una categoría
inexistente o un intervalo invertido también producen errores de presupuesto.

## Resultado y paginación

```dart
final result = await reader.readResult(
  BudgetListQuery.range(
    month: BudgetMonth(2026, 10),
    firstMonth: BudgetMonth(2025, 12),
    lastMonth: BudgetMonth(2026, 2),
    categoryId: categoryId,
  ),
);
final firstPage = result.page(limit: 100);
final nextPage = result.page(offset: 100, limit: 100);
// result.totalCount y result.subtotalCents corresponden a todo el resultado.
```

`BudgetListResult` conserva los filtros, registros originales con su
procedencia, categoría con nombre/ruta y UUID, contador y subtotal firmado
`BigInt` en céntimos. No se convierte a coma flotante ni se desborda int64 al
sumar o cancelar importes. Cada partida aparece una vez; no se crean ceros,
no se suman filas agregadas del informe y no se reparte una partida padre.
Un resultado vacío y uno con partidas de neto cero tienen el mismo subtotal,
pero distinto contador/origen. Orden: mes, ruta actual y UUID de partida.
Los nombres o rutas iguales conservan identidades distintas.

La paginación es **en memoria** sobre una lectura completa e inmutable del
ámbito. Cada página tiene entre 1 y 200 como límite solicitado, por defecto
100; un desplazamiento fuera del resultado devuelve vacío. Las páginas no
consultan de nuevo la base ni recalculan un subtotal independiente. El coste
de memoria depende del ámbito completo: no es paginación SQL ni una garantía
de memoria constante para históricos grandes.

Se reutiliza `BudgetRepository.list` para un mes y `readYear` una vez por año
del intervalo; no se amplía el puerto de persistencia. Árbol, estado de base y
registros se leen dentro de la misma `UnitOfWork` de lectura, compartiendo
conexión. Se conservan `datasetState` y `categoryGeneration`; una invalidación
del árbol durante la operación rechaza el resultado completo. Errores del
repositorio o registros duplicados/inconsistentes no devuelven listas parciales.

`read(query)` continúa devolviendo la lista completa para los consumidores
existentes y delega en la misma consulta. Después de guardar, importar,
restaurar o cambiar el árbol hay que releer y obtener páginas del resultado
nuevo. La lectura anterior no promete reflejar escrituras posteriores ni
mantener la igualdad con la cifra de origen si cambió la base. Las rutas
existentes codifican rangos de un mismo año; ampliar esa navegación queda en
la integración de EP-024, sin limitar el contrato de consulta entre años.

## Verificación

`test/budget/budget_list_result_test.dart` usa SQLite sintético y un decorador
del repositorio que rechaza escrituras y cuenta lecturas. Cubre límites
inclusivos entre años, mes/año/rango, directo/rama/todas, padre sin reparto,
archivo y traslado histórico, rutas repetidas, vacío/cero/neto cero, 205
partidas en páginas de 200 y 5, subtotal global, inmutabilidad, relectura tras
borrado, sumas fuera de int64, años 1/9999 y errores de filtros. Comprueba que
dataset y revisión no cambian al consultar.

Las pruebas anteriores de la consulta conservan cobertura de fallos de
almacenamiento, invalidación, UUID de partida duplicado y datos de otro año.
Las de referencia comparan los orígenes y totales con el caso E de EP-001 y
la matriz anual. Las pruebas de aperturas exigen el rechazo de Sin clasificar
y comprueban que sus movimientos siguen accesibles, tanto en el widget como
en el recorrido SQLite de Estado para Windows y Android.

### Resultado local del 2026-10-15

- Flutter 3.47.0 / Dart 3.13.0 y `check-toolchain.ps1` correctos;
  `flutter pub get --enforce-lockfile` resuelto sin cambios del lockfile.
- Formato de 451 archivos sin cambios; análisis estático final sin incidencias;
  `git diff --check` correcto.
- Diez pruebas específicas de consulta/resultados correctas. La regresión de
  presupuesto, Estado y arquitectura obtuvo 253 pruebas correctas y dos
  incidencias: timeout en el recorrido presupuestario Android y desplazamiento
  antes de terminar una invalidación en el fixture de Estado Android. Se añadió
  la espera explícita de ese fixture; los cuatro recorridos completos de ambos
  módulos, Windows y Android, pasaron al repetirlos secuencialmente.
- Arranque comprobado con `APP_ENV` development/test/production/invalid-synthetic.
- Se ejecutó `check-quality.ps1`: formato y análisis pasaron; su ejecución de
  pruebas tuvo 1881 correctas y seis fallos. Tres correspondían a la antigua
  apertura presupuestaria de Sin clasificar, corregida y comprobada después.
  Los otros tres son ajenos a esta consulta: `pending_lifecycle_test.dart`
  Windows/Android no encuentra el menú esperado en Real anual y
  `movement_lifecycle_test.dart` Android no encuentra la navegación esperada.
  Se reprodujeron los mismos tres fallos y ubicaciones en una copia del estado
  inicial, sin los cambios de MA-TSK-190; no se afirma que toda la suite esté verde.

La copia de control usa HEAD `fbc7dbe` más los ocho archivos de sincronización
modificados/no seguidos que ya estaban presentes al iniciar. HEAD por sí solo
no compila las pruebas de aplicación porque referencia archivos de esa entrega
de sincronización todavía pendientes de seguimiento. Esos cambios ajenos no
se incluyen en MA-TSK-190. Los logs y la copia de control permanecen en `.tools`
fuera del commit. No se ejecutaron builds nativos ni aceptación visual humana:
no hay cambios específicos de plataforma y las pruebas Flutter no sustituyen
la aceptación visual de EP-026.
