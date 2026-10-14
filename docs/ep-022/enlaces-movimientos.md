# MA-TSK-178 · Movimientos desde Real anual

Ticket y estados de EP-022 consultados en la API local de Epic Board, tablero
**My autofinance**, el 2026-10-14. La consulta MA-TSK-174 y la aprobación
MA-TSK-175 constan entregadas. Este contrato se puede usar sin consultar el
motor anual ni construir sus interfaces MA-TSK-176/177.

## Contrato para Windows y Android

`features/actual_spending/actual_spending.dart` publica `AnnualActualDetail`.
Recibe año civil 1–9999, mes opcional 1–12, UUID opcional, `unclassified` y
`MovementCategoryScope` (rama por defecto). Su propiedad `movements` entrega
el `MovementListQuery` existente, sin cuentas ni búsqueda.

| Cifra | Alcance |
|---|---|
| Celda mensual agregada | Año, mes y UUID; nodo más descendientes |
| Total anual de nodo | Año y UUID, sin mes; nodo más descendientes |
| Desglose directo | Mismo periodo y UUID con `scope: direct` |
| Sin clasificar | `unclassified: true`, UUID null; solo categoría SQL NULL |
| Total mensual o anual general | Sin UUID ni `unclassified`; todos los reales una vez |

El rango es civil `[desde, hasta)`, según fecha de valor. Año completo empieza
el 1 de enero y termina al inicio del año siguiente; mes termina al inicio
del siguiente mes. Año 9999 y diciembre de 9999 usan `until: null`, conforme
a ValueDate y al repositorio existente. No se construye una fecha de año
10000. Cero neto y ausencia no impiden abrir la lista.

App ofrece `AnnualActualNavigation(context:, origin:, session:)` con `open`,
`openMonth`, `openYear` y `addMovement`. El callback `origin` devuelve una
`AnnualActualOrigin` actual al pulsar, no el contexto inicial de la pantalla.
`addMovement` usa el formulario EP-010 y el primer día del mes enfocado,
sin asignar categoría ni cuenta implícitas. Los consumidores deben esperar
el Future y releer sus cifras después de volver, como en EP-019/021.

Se reutilizan `MovementLinks.list/create/detail`, la lista paginada y el
formulario existentes. No se incorpora otro motor de consulta, lista o editor,
ni se modifica la consulta de MA-TSK-174. La UI anual conectará estos métodos
a sus cifras y a la acción Añadir movimiento en sus tickets propietarios.

## Origen y retorno

`AnnualActualOrigin` distingue `/real` y `/real/detalle` mediante `detail`.
Conserva año, mes enfocado, UUID o Sin clasificar, alcance, ramas abiertas
(`abiertas`), tarjetas con meses abiertos (`meses`), posición y foco. Los
despliegues se codifican con UUID separados por comas; Sin clasificar usa el
token `sin-clasificar`. No persiste en SQLite ni Drive.

Valida destino y vista anual, calendario, UUID, filtros conocidos, posición
finita no negativa y foco sin controles ni longitud excesiva. Rechaza URLs
externas, fragmentos, parámetros repetidos o desconocidos y alcances inválidos.
MovementLinks valida el origen tanto al generar como al interpretar la ruta.
SessionLocation reutiliza el mismo contrato al reconstruir el contexto.
Un origen inválido presenta error seguro antes de cargar repositorios.
Las entradas históricas de EP-016 sin una instantánea de retorno mantienen
sus filtros opacos; ese mecanismo no relaja la validación de MovementLinks.

Con pila se conserva la pantalla y se restaura su contexto/foco al regresar.
Sin pila, la lista reconstruye la ruta validada y su contexto completo. El
formulario conserva la lista inmediata al guardar o cancelar. Una edición
fuera del rango de origen ofrece «Ver mes» sin cambiar automáticamente el
periodo. Una edición dentro de otro mes del mismo rango anual conserva ese
rango y no ofrece un aviso incorrecto de salida del periodo. Elegir «Ver mes»
es un cambio explícito y volver restaura el origen anterior.

## Verificación

Datos exclusivamente sintéticos y SQLite real:

- `annual_actual_links_test.dart`: contrato independiente de consulta/UI,
  rangos de años 1/2024/2026/9999 y meses 1/2/12, directo/rama/NULL/total,
  round-trip de resumen/detalle y orígenes inválidos.
- `annual_actual_detail_test.dart`: páginas de dos registros, subtotal y
  contador de todo el alcance en cada página; directos en tres niveles,
  dos cuentas, duplicados legítimos, cero neto, lista vacía y año 9999.
- `annual_actual_navigation_test.dart`: origen sintético con lista/formulario
  reales; edición fuera del año, «Ver mes» y regreso, retorno sin pila,
  alta en mes enfocado/cancelación, error anterior a cargar y editor anual
  sin pila que mueve la fecha dentro del mismo año.

Estas pruebas verifican la composición de enlaces. No acreditan aceptación
visual ni recorrido nativo de las interfaces anuales pendientes.

Comprobaciones locales del 2026-10-14:

- Flutter 3.47.0 / Dart 3.13.0 y `check-toolchain.ps1`, correctos.
- La resolución online con `--enforce-lockfile` falla al contactar con
  pub.dev desde el entorno restringido. La misma resolución con `--offline`
  termina correctamente usando caché, sin modificar SDK ni lockfile.
- Formato de 417 archivos y análisis final con fatal-infos/fatal-warnings,
  correctos; comprobador financiero EP-001, `OK`.
- `check-quality.ps1` se ejecutó con resolución offline y dos procesos de
  prueba mediante una función local, sin cambiar el script. La batería global
  termina con 1.193 pruebas correctas y 555 fallidas: predominan errores de
  apertura SQLite por restauración/recuperación pendiente, además de fallos
  de sincronización. Nueve fallos de gestión de presupuesto se reproducen en
  una copia limpia de HEAD sin cambios propios ni concurrentes. No se ha
  comprobado individualmente el origen de todos los fallos globales.
- Dos regresiones propias de rutas históricas EP-016 detectadas en esa
  ejecución se corrigieron preservando filtros opacos en entradas anteriores.
  La batería global no se repitió tras esa corrección; se repitieron las
  pruebas pertinentes de enlaces, origen anual, consulta anual, arquitectura,
  sesión/shell y navegación de Estado y Presupuesto: **100 pruebas correctas**.
- Las cuatro variantes de arranque development/test/production/invalid-synthetic
  se verifican por separado, porque el fallo global detiene el script antes
  de esa fase.
- No se requieren builds de plataformas para este contrato de navegación.
  No se han realizado builds ni aceptación visual nativa del informe anual.

Logs de verificación en `.tools/ma-tsk-178-*`, ignorados por Git. Solo se
confirman los archivos del contrato, navegación, pruebas y este documento;
README, sincronización y artefactos concurrentes permanecen fuera del commit.
