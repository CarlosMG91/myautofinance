# MA-TSK-162 · Origen de las cifras mensuales

Ticket y dependencias consultados el 2026-10-10 mediante la API local de Epic
Board, tablero **My autofinance**. MA-TSK-159 consta terminado con aprobación
humana de la propuesta visual. Se reutilizan EP-001 §5.1 y casos B/C/J/K/L,
la entrega EP-002, MovementLinks/EP-010, formularios EP-011 y sesión EP-016.
Los cambios ajenos presentes al empezar no forman parte de esta entrega.

## Contrato para Estado PC y Android

`features/monthly_status/monthly_status.dart` publica `MonthlyFigureDetail`
y `MonthlyStatusDetailCallbacks`, sin Flutter y sin depender de
`MonthlyStatusQuery` ni de su resultado. La entrada tiene `BudgetMonth`,
UUID opcional, `MovementCategoryScope` directo/rama y `unclassified`.
UUID nulo con `unclassified=false` representa el total del mes;
`unclassified=true` representa exclusivamente categoría NULL. La combinación
UUID y Sin clasificar se rechaza. Todas las cuentas participan, sin búsqueda.

| Cifra | Callback y alcance |
|---|---|
| Real directo | `onMovements`, UUID del nodo y `direct` |
| Real agregado | `onMovements`, UUID del nodo y `branch` |
| Previsto agregado | `onBudgets`, UUID del nodo y `branch` |
| Diferencia agregada | `onDifference`, UUID del nodo y `branch`; ofrece «Ver movimientos reales» y «Ver partidas previstas» |
| Sin clasificar | Mismos callbacks con `unclassified=true`; partidas vacías |
| Total | Mismos callbacks sin UUID ni Sin clasificar; todos los registros del mes una vez |

App inyecta `createMonthlyStatusDetailCallbacks(context: ..., origin: ...,
session: ...)`. `origin` devuelve el `NavigationContext` vigente al pulsar,
no la ruta inicial del widget. La diferencia captura el mismo origen antes
de mostrar su diálogo; cancelar, Escape o cerrar no consulta ni escribe.
La interfaz consumidora relee Estado al terminar el callback tras una edición.
Los tickets de tabla y tarjetas conectarán estas acciones; esta entrega no
implementa sus vistas ni sustituye el marcador técnico de Estado.

`MonthlyStatusOrigin` valida destino Estado, vista mensual, periodo, UUID,
alcance, posición finita no negativa y foco. El filtro `abiertas` contiene UUID
de ramas desplegadas separados por coma; el foco es un token del consumidor
(por ejemplo `UUID:previsto`). Serializa `a`, `m`, `rama`, `alcance`, `abiertas`,
`posicion` y `foco`. Conserva también `concepto` de los contextos históricos
EP-016 sin aplicarlo como filtro nuevo de Estado. Rechaza duplicados,
parámetros desconocidos, URLs externas,
fragmentos y valores inválidos. No guarda estado en SQLite ni Drive.

Movimiento reutiliza `MovementLinks.list`: rango civil inicio incluido y fin
exclusivo, incluidos diciembre y año 9999. La ruta transmite origen y scope;
la lista existente conserva su consulta y abre sus formularios. El rango
explícito prevalece sobre el mes de navegación conforme a EP-016; Estado
siempre genera el rango del mes elegido. Se rechazan representaciones
simultáneas de la categoría. Una categoría
UUID inexistente produce error de lectura en la lista y no una cifra vacía.

## Partidas y retorno

`BudgetLinks` entrega lista, alta y detalle en `/presupuesto/partidas`,
`/presupuesto/partidas/nueva` y `/presupuesto/partidas/UUID`, con mes,
UUID/Sin clasificar, alcance y origen de Estado. Valida antes de cargar fuentes.
`BudgetEditorOrigin` mantiene compatibilidad con los consumidores de EP-011
y añade la ruta inmediata de lista para el retorno sin pila.

`BudgetListReader` recibe repositorio, gestión de categorías e unidad de
trabajo por constructor. App usa `SqliteReadUnitOfWork` en la misma conexión:
lee árbol actual completo y partidas originales de ese mes sin modificar
revisión o tablas. Filtra por ascendencia UUID, conserva archivo, homónimos,
cero explícito y procedencia. No crea partidas hijas, no prorratea padres,
no mezcla otros meses y descarta una lectura invalidada por cambios del árbol.
Los errores de almacenamiento se muestran como error, sin sustituirlos por
ausencia o cero. Los totales de la lista suman sus registros con BigInt.

La lista mínima muestra fuentes, importe y acceso al formulario existente.
Una lista vacía muestra «Sin presupuesto» y «Crear partida»; la creación es
explícita. En Sin clasificar y total el formulario exige elegir una categoría
existente: presupuesto nunca recibe una categoría NULL. Cancelar no crea nada.
No se incorpora editor nuevo, matriz anual, gráficos ni filtros de cuenta.

Push/pop conserva Estado y su contexto; sin pila, las listas reconstruyen la
ruta y pasan la instantánea validada al observador EP-016. Guardar/cancelar
vuelve al detalle inmediato y relee los registros. La lista de partidas
conserva scroll y foco del botón de origen. La composición restaura periodo,
ramas abiertas, posición y foco de Estado al terminar. Los formularios
conservan protección de borrador, identidad de conexión y «Ver mes» para
una edición fuera del mes original; el aviso solo aparece tras el commit.

## Evidencia de verificación

- `monthly_figure_detail_test.dart`: SQLite real, tres niveles, UUID, cuentas,
  NULL, rango civil, total único, transferencias netas cero, partida padre,
  cero explícito, archivo y traslado bajo el árbol actual, sin fotos ni writes.
- `monthly_status_links_test.dart`: contrato sin consulta/presentación de
  Estado, round-trip del contexto completo, límites y rutas ambiguas/externas.
- `budget_list_query_test.dart`: doubles que prohíben escrituras, selección
  directa/rama, ausencia, error de persistencia e invalidación durante lectura.
- `monthly_status_detail_navigation_test.dart`: diálogo de ambas fuentes,
  cancelar, alta explícita/cancelación, edición de partida y real fuera del
  origen, acción «Ver mes», retorno con/sin pila y errores anteriores a cargar.
  Lista y formularios probados también a 320 px con texto 200 %.
- Regresión de enlaces de Movimientos y arquitectura: correctas; los módulos
  mantienen entradas públicas y grafo acíclico. Comprobador EP-001: `OK`.

Verificación final del 2026-10-10:

- Flutter 3.47.0 y Dart 3.13.0; `check-toolchain.ps1` y resolución con
  `--enforce-lockfile` correctos. SDK, toolchain y lockfile sin cambios.
- Quince pruebas nuevas correctas dentro de la suite completa. La ejecución
  específica de contratos históricos, vistas, links y navegación termina con
  26 pruebas correctas, incluidas compatibilidad de concepto y prioridad del
  rango explícito EP-016.
- `scripts/check-quality.ps1` correcto: formato de 345 archivos sin cambios,
  análisis sin incidencias, 1.539 pruebas correctas y las cuatro ejecuciones
  de arranque development/test/production/invalid-synthetic. Se limita a dos
  procesos de prueba con una función local PowerShell, sin modificar el script.
- Windows release `--no-pub --dart-define=APP_ENV=test` correcto (55,4 s).
- Android debug con las mismas opciones correcto (17,1 s); Android SDK y
  JDK 17 ya instalados, con configuración de Flutter aislada por proceso.
- `git diff --cached --check` correcto. Logs en `.tools/`, ignorado:
  `ma-tsk-162-quality-final.log`, `ma-tsk-162-regressions.log`,
  `ma-tsk-162-build-windows.log` y `ma-tsk-162-build-android.log`.

Las comprobaciones se ejecutan sobre el checkout que conserva cambios ajenos;
solo los 21 archivos propios de MA-TSK-162 se confirman en la rama configurada
`ticket/ma-tsk-113` y se publican en `origin` sin forzar la subida.
Las pruebas de widgets no acreditan recorrido manual nativo, lector de pantalla
ni integración de las vistas de Estado PC/Android de los otros tickets.
