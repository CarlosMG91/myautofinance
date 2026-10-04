# MA-TSK-084 · Selectores y lecturas del árbol actual

## Evidencia y alcance

Se consultó `GET http://localhost:4310/api/data`, tablero **My autofinance**,
el 2026-10-04. MA-TSK-084 estaba `in-progress`, MA-TSK-083 terminado y las
tareas funcionales de EP-009 bloqueadas. Se revisaron los contratos de
[EP-001](../ep-001/especificacion.md), [casos L/M](../ep-001/casos-referencia.md),
[lecturas EP-004](../ep-004/consultas-lectura.md) y
[entrega de interfaz](interfaz-categorias.md).

Se conserva Gestión → Categorías y las rutas `/categorias`,
`/categorias/nueva` y `/categorias/:id`. No se modifica el router, los destinos
financieros ni la navegación de EP-009. El selector es una ruta secundaria
local sobre el origen; no registra un nuevo destino de Gestión. Los cambios
concurrentes de sincronización, README y prototipo quedan fuera del commit.
No se finaliza administrativamente la épica: aún tiene otros tickets.

## Interfaz para consumidores

`app/category_selector_navigation.dart` entrega:

```dart
final chosen = await selectCategory(
  context,
  loadManagement: session.categories,
  selectedId: draft.categoryId,
);
if (chosen != null) {
  // Persistir exclusivamente chosen.node.id; chosen.path es presentación actual.
}
```

El resultado es `CategoryDetails`: `node.id` (UUID estable), `path`, estado y
tipo efectivo. Un resultado null significa cancelación: el consumidor mantiene
su selección y todos los demás campos del borrador. Cancelar, Escape y Back
devuelven null. La creación usa el formulario aprobado y vuelve al selector
con el nuevo UUID seleccionado; el consumidor lo aplica al pulsar Seleccionar.
Cancelar el alta conserva la selección que había antes de abrirla.

El widget `CategorySelector` recibe por constructor un loader, el UUID actual,
`onReturn` y `onCreate`. App lo compone; las funcionalidades no importan app ni
widgets internos de otros módulos. Si otra épica necesita un selector, app
inyecta un callback con el resultado de dominio público de `movements.dart`.
No hace falta modificar el grafo de módulos para añadir una pantalla.

Las opciones excluyen archivadas, desambiguadas con ruta, tipo y UUID.
La selección histórica archivada se presenta con su ruta y marca Archivada:
se puede conservar esa misma referencia o sustituirla por una activa; no se
ofrece para nuevas asignaciones. SQLite vuelve a validar al guardar.
No se ofrece «Sin clasificar» como categoría: un consumidor de movimientos
puede implementar su acción independiente de limpiar el UUID.

Carga, vacío, errores y reintento tienen estados explícitos. Mientras se
recarga no se confirma una ruta obsoleta. Las respuestas de cargas anteriores
se descartan. El alta pendiente impide duplicar la navegación. Los controles
y rutas largas se ajustan con texto al 200 % en 320/412/1440 px.

## Invalidación y agrupación

`LocalBackupSession.categoryInvalidation` es compartido por todas las instancias
de gestión que resuelve `session.categories()`, incluso tras reabrir SQLite.
`CategoryManagement.invalidation` expone la misma señal. Las mutaciones de
gestión se invocan como operaciones completas: ya tienen su propia unidad de
trabajo. Si cambia dataset/revisión, notifican **después** de confirmar la
transacción. Un no-op o un rechazo no notifican. La señal es conservadora
durante acciones de recuperación local, que pueden sustituir la base.

La entrada pública de movimientos exporta `CategoryReadInvalidation`, con
`generation`, `changes` (`Stream<int>`), `invalidate()` y `close()`.
La sesión posee su duración; no cerrar la señal desde un selector o servicio
temporal. Suscriptores cancelan su suscripción al salir. Un importador futuro
que escriba mediante repositorios debe invalidar desde app **después** de su
commit; no se implementa ese importador aquí.

El árbol y el selector se suscriben antes de leer y resuelven de nuevo el
servicio para cada lectura. El árbol pospone la recarga mientras su editor
está abierto, conservando expansión, filtro, scroll y foco al volver.
Los informes futuros reciben la señal por inyección desde app (puede ser
solo el Stream, sin añadir dependencias entre funcionalidades). Ante un evento
descartan árbol, rutas, tipo efectivo, agregados e ingresos presupuestados;
mantienen año/mes/filtros del usuario y releen los puertos EP-004. Se suscriben
antes de la primera lectura, capturan generación y descartan una respuesta
si cambió durante su carga. Las señales no son revisiones SQLite persistentes.

`CategoryGrouping` es una proyección inmutable del árbol actual, publicada en
`movements.dart`. `categories` permite resolver detalles por UUID y
`aggregate(directCents)` suma cada importe directo una vez por ancestro,
incluyendo archivadas y conservando signos. Recrear la proyección después de
una invalidación. Las entradas son sumas de registros explícitos por UUID;
no pasar totales ya agregados. El total general se calcula desde esos registros
directos, incluyendo aparte los movimientos sin clasificar: no sumar todas
las filas agregadas del árbol. Una categoría ausente o un ciclo falla de forma
explícita, sin ocultar registros ni producir totales parciales.

Las consultas SQL existentes ya recorren el árbol vigente y no necesitan
migración: `MovementRepository.readMonth/readYear(categoryId: ...)` devuelve
nodo y descendientes una sola vez; `BudgetRepository.list/readYear` conserva
partidas originales; `readYear(incomeOnly: true)` adopta la marca de la nueva
raíz, también en años anteriores, con negativos, ceros y archivadas.
El indicador continúa usando activos líquidos / (ingresos anuales / 12).
No se añaden fórmulas ni pantallas de Estado, Real, Presupuesto o Indicadores.

## Verificación

Datos exclusivamente sintéticos. `category_consumer_reads_test.dart` usa SQLite
real para commits/no-op/rollback, señales entre servicios, movimientos directos
en padre e hijo, lecturas mensuales/anuales, presupuestos de doce meses,
ingresos antes/después del traslado, renombre de ancestro, archivo/reactivación,
promoción con tipo heredado y solapamiento histórico con cero.

`category_selector_test.dart` cubre UUID/rutas duplicadas, cancelación/Escape,
alta y cancelación con router/formulario reales, Back conservando el resultado
anterior, referencia archivada, actualización de ruta/tipo entre servicios,
error/reintento, árbol abierto que recibe un renombre y layout al 200 %.
La regresión de MA-TSK-083 comprueba foco, scroll, filtro y expansión. Sus
esperas de alta y foco comprueban el resultado de la navegación asíncrona;
las aserciones se mantienen. La devolución de foco espera al fin de la
transición y programa un frame incluso si SQLite termina después del anterior.

`./scripts/check-quality.ps1` completado con Flutter 3.47.0 / Dart 3.13.0:
lockfile exigido sin cambios, formato correcto (154 archivos), análisis sin
incidencias, **849 pruebas correctas** y las cuatro variantes
development/test/production/invalid-synthetic correctas. La suite incluye el
trabajo concurrente de sincronización, que no se incorpora al commit.
`node docs/ep-001/verificar-casos.mjs` correcto, incluidos L/M y signos.
`git diff --check` correcto.

`flutter build windows --release --no-pub --dart-define=APP_ENV=test` correcto
con el código final: bundle en `build/windows/x64/runner/Release/`.

La resolución inicial dentro del sandbox falló al consultar avisos de pub.dev;
la ejecución autorizada del verificador resolvió el lockfile correctamente.
Las pruebas de archivos SQLite se ejecutaron fuera del sandbox; las pruebas
nuevas usan también SQLite real en memoria con claves foráneas activadas.

Android: se intentó `flutter build apk --debug --no-pub --dart-define=APP_ENV=test`;
falla con «No Android SDK found». El APK y el recorrido nativo Android quedan
sin verificar. La prueba de widgets no acredita recorrido táctil ni lector de
pantalla físico, ni sustituye el recorrido completo reservado a MA-TSK-085.
