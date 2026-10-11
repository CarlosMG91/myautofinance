# MA-TSK-170 · Navegación anual y partidas de origen

Ticket consultado el 2026-10-11 en Epic Board, tablero **My autofinance**.
Se reutilizan EP-011, el periodo/contexto de EP-016, la lista de partidas de
MA-TSK-162 y la propuesta ya entregada de MA-TSK-154. Fuentes financieras:
EP-001 §3/§5.3/caso E; entrega visual general aprobada de EP-002.

## Rutas y periodo

| Entrada | Alcance |
| --- | --- |
| `/presupuesto` | Principal anual; año y mes enfocado desde sesión. |
| `/presupuesto?a=2025` | Mes recordado de 2025, o enero si no se recuerda. |
| `/presupuesto?a=2026&m=10` | Año 2026 con octubre enfocado. |
| `/presupuesto/mensual?a=2026&m=10` | Captura secundaria EP-011, con periodo mensual local. |
| `/presupuesto/partidas?a=2026&m=10` | Partidas de octubre. |
| `/presupuesto/partidas?a=2026&m=10&desde=01&hasta=12` | Partidas de todo 2026; octubre solo es foco para una alta explícita. |
| `/presupuesto/partidas?a=2026&m=10&desde=02&hasta=04` | Rango inclusivo febrero–abril, dentro del mismo año. |
| `/presupuesto/partidas/nueva` y `/presupuesto/partidas/<UUID>` | Formularios existentes, con los mismos parámetros de consulta/origen. |
| `/presupuesto/propuesta?a=2026&m=10` | EP-018 existente, sin implementar otro motor o editor. |

`BudgetListQuery(month: ...)` conserva el contrato mensual de EP-019.
`BudgetListQuery.annual(year, focusedMonth: ...)` y `.range(...)` separan el
mes enfocado de `firstMonth`/`lastMonth`. `desde`/`hasta` son meses `01`–`12`,
ambos obligatorios cuando hay rango. Sin rango, `m` determina el mes consultado.
La consulta mensual usa `list`; la de varios meses usa **una** `readYear` dentro
de la misma unidad de lectura que el árbol. No añade repositorios o servicios.

`rama` selecciona una categoría por UUID, `alcance=directo` solo el nodo y
`alcance=rama` nodo y descendientes. Sin categoría se incluyen todas las
partidas del periodo una vez. El detalle no reparte una partida padre, conserva
archivadas con datos y rechaza IDs duplicados o registros fuera del año pedido.
El cero explícito conserva su partida; un neto cero conserva todos sus orígenes.
Una lista vacía permite **Crear partida** sin escribir hasta confirmar el formulario.

Los callers de pestañas siguen usando `/presupuesto`, ahora anual. Captura,
recorridos EP-011 y su prueba nativa migran a `/presupuesto/mensual`.
Los enlaces desde Estado, Gestión e importaciones mantienen los formularios y
las partidas por UUID. La acción **Ver mes** abre la captura del periodo guardado
con una elección explícita del contexto común; guardar solo no lo cambia.

## Origen y retorno

`BudgetOrigin` admite únicamente Estado, Presupuesto anual y captura mensual.
La serialización lleva año, mes, UUID/alcance, `abiertas`, `posicion` y `foco`.
Estado conserva además su contrato previo de `concepto`, mediante
`MonthlyStatusOrigin`. URLs externas, fragmentos, parámetros duplicados,
orígenes anidados, UUID inválidos, foco con controles y posiciones negativas o
no finitas se rechazan antes de cargar datos. Las rutas principales conservan
los aliases `c` y `direct`/`branch` EP-016 al normalizarlos; las nuevas rutas de
partidas usan el contrato estricto ya publicado por EP-019.

Con pila se conserva la instancia del consumidor, su scroll y los focos.
Sin pila, lista y editor reconstruyen el origen validado y pasan el contexto
completo como argumento. La lista conserva el rango al abrir un formulario y
relee al volver tras crear, editar o borrar, restaurando posición y foco. El
observador registra también el origen de rutas secundarias para que hacer pop
desde **Ver mes** recupere la captura/lista anterior y su periodo original.

La captura secundaria usa `NavigationSession.secondarySession`: controles
EP-016 y el mismo reloj de la sesión principal, con contexto/memoria locales.
Cambiar su mes o pulsar **Mes actual** no cambia la matriz de origen. Volver
pasa por la protección de borrador EP-011. Cambiar destino transmite el periodo
de trabajo elegido, sin heredar filtros de otro informe.

## Entrega a las interfaces anuales

`AutofinanceApp.annualBudgetBuilder` y `AppRouter.generateRoute` inyectan
`AnnualBudgetBuilder`. Recibe `AnnualBudgetNavigation`, con `current`, `year`,
`focusedMonth` y estos callbacks:

- `openMonth(month, categoryId: ...)`: agregado mensual o total general.
- `openYear(categoryId: ...)`: rama anual o total general del año.
- `openCell(month: ..., categoryId: ..., budgetId: ...)`: edición de la partida
  propia por UUID, incluido cero; sin UUID, alta explícita de una ausencia.
- `openMonthlyCapture()`: captura secundaria con origen completo.
- `canPrepareNextYear()` / `prepareNextYear()`: entrada a EP-018 cuando están
  disponibles calculador y guardado, y el año admite un destino siguiente.

Las interfaces publican sus expansiones/posición/foco en `NavigationContext`
antes de invocar el callback y releen sus cifras al terminar su `Future`.
Los callbacks capturan el contexto, restauran el origen y devuelven foco. La
restauración exige que la ruta de origen siga activa: cambiar de destino desde
la captura no permite que un callback pendiente recupere Presupuesto encima.
La entrada a propuesta evita doble apertura y descarta una disponibilidad tardía
si se cambió de periodo; un guardado EP-018 en el año destino respeta la
navegación explícita ya entregada, sin restaurar encima el año fuente.

**MA-TSK-168/169 implementan las interfaces de matriz y tarjetas.** Este ticket
no sustituye su implementación ni concede la aprobación de MA-TSK-167: el
suplemento local aún registra aprobación pendiente. Mientras no se inyecte la
vista anual, `/presupuesto` conserva una entrada técnica anual con los controles
comunes, Gestión, Captura mensual y Preparar año siguiente. No presenta datos
sintéticos ni llama a una captura mensual como si fuese una matriz anual.
La entrada puede probarse con un consumidor de callbacks sin depender de esas
interfaces. No se modifica la propuesta EP-018 ni se duplica el detalle EP-019.

## Verificación y entrega

Los cuatro archivos `annual_budget_*` nuevos de pruebas comprueban contratos
con doubles y navegación con SQLite sintético. Cubren alcance directo/rama,
padre en enero e hija archivada en febrero, neto cero con dos UUID, cero propio,
ausencia, alta/cancelación, edición fuera del año, borrado confirmado, retorno
con/sin pila, foco, rutas inválidas sin consultas y disponibilidad de propuesta.
El caso E reutiliza `seedRecoveryReference`: los 48 UUID del detalle coinciden
con la proyección anual; cada mes suma +1.100,00 EUR y el año +13.200,00 EUR.
Las lecturas no incrementan la revisión de la base.

Regresiones de EP-011, propuesta, Estado, Gestión, navegación histórica,
periodo y arquitectura se adaptan a la secundaria explícita. Logs de calidad,
builds y pruebas permanecen en `.tools/ma-tsk-170-*`, ignorados.
`check-toolchain.ps1`, `flutter pub get --enforce-lockfile`, formato (364
archivos) y análisis sin incidencias pasan con el SDK fijado. Las compilaciones
Windows release y APK debug, ambas con `APP_ENV=test` y `--no-pub`, pasan.
`./scripts/check-quality.ps1` termina correctamente: **1.589 pruebas** de la
batería, más un arranque en cada entorno development/test/production/
invalid-synthetic. Se limita la concurrencia a cuatro procesos en este PC.
Los recorridos con variantes Windows/Android son pruebas widget con SQLite
de archivo; no se ha ejecutado E2E nativo en dispositivos.

La rama configurada es `ticket/ma-tsk-113`, remoto `origin`. La entrega incluye
solo archivos propios de MA-TSK-170. README, APIs de Drive y prototipos de otras
épicas estaban modificados antes de iniciar el ticket y quedan fuera del commit.
El checkout actual consume dependencias de subida Drive todavía sin confirmar
por su ticket; estas pruebas no acreditan que una clonación limpia del remoto
compile hasta que ese trabajo se publique. No se cierra EP-021 ni se incorporan
archivos de las interfaces o de otros tickets.
