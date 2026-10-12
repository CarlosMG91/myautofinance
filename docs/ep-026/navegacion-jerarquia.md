# MA-TSK-205 · Navegación y jerarquía de información

Contrato de diseño v1, 2026-10-12. Ticket y épica MA-EPIC-203 consultados en
Epic Board (`GET http://localhost:4310/api/data`, tablero **My autofinance**).
T02 es independiente de T01/T03. Esta entrega prepara T04, T05 y T06; la
activación visual espera la aprobación humana explícita de **MA-TSK-207**.
No concede esa aprobación ni cambia la aplicación actual. EP-001 conserva
todas sus reglas; solo la apariencia/navegación de EP-002 será sustituida.

El [catálogo JSON](catalogo-navegacion.json) es la fuente de IDs, etiquetas,
rutas, propietarios y conexiones. Lo pueden consumir el prototipo T04 y las
pruebas. El [contrato de shell/contexto](contrato-shell-contexto.md) fija los
slots y las obligaciones de composición para el trabajo independiente.

## Mapa adaptable

| Windows: barra lateral | Android: barra inferior | Contenido |
| --- | --- | --- |
| Inicio | Inicio | Flujos del mes, foto patrimonial del día 1 y tareas pendientes separadas. |
| Presupuesto | Presupuesto | Resumen del año y del mes enfocado; captura, propuesta y matriz completa. |
| Movimientos | Movimientos | Actividad, registro, filtros, importación y categorización pendiente. |
| Patrimonio | Patrimonio | Foto seleccionada, valores por ficha, registro/corrección y vigencias. |
| Análisis | Más | Windows abre Análisis; Android abre Más con accesos directos a Análisis, Real anual, Indicadores y Gestión. |

Windows mantiene **Gestión** como botón visible de herramientas, fuera de los
cinco destinos principales. Análisis muestra accesos **Real anual**,
**Indicadores** y **Diagnóstico de coherencia**. No es un sexto informe ni
suma de nuevo las cifras. Más tampoco es un módulo financiero.

El campo opcional `surfaces` restringe agrupaciones exclusivas de una
superficie: Más solo tiene entrada principal en Android. El resto de
destinos y flujos es accesible desde ambas proyecciones. `entrySelection`
fija la selección de informes/agrupaciones al abrirlos sin origen; los
detalles conservan la selección de su captura de origen.

Contar una acción por selección visible, desde cualquier destino principal:

| Informe | Windows | Android | Acciones |
| --- | --- | --- | ---: |
| Estado del mes | Inicio → Ver detalle | Inicio → Ver detalle | 2 |
| Presupuesto anual | Presupuesto → Ver detalle | Presupuesto → Ver detalle | 2 |
| Patrimonio | Patrimonio → Ver detalle | Patrimonio → Ver detalle | 2 |
| Real anual | Análisis → Real anual | Más → Real anual | 2 |
| Indicadores | Análisis → Indicadores | Más → Indicadores | 2 |

Los accesos a Real anual e Indicadores no deben quedar dentro de otro menú
de Análisis en Android. Al abrirlos, se selecciona Análisis en Windows y Más
en Android. Las rutas de edición/detalle mantienen seleccionado su padre;
el breadcrumb y **Volver** nombran el origen real, no siempre Inicio.

## Jerarquía de cada entrada

**Inicio** presenta, en este orden:

1. Título y selector **mes/año** visible; periodo de trabajo, no fecha de hoy.
2. **Resultado real del mes**, **Resultado presupuestado** y
   **Diferencia real − presupuesto**, con signo y EUR. Resumen de categorías
   con acceso al origen de cada cifra; **Ver detalle** abre la comparación
   completa de Estado, con real directo/agregado y presupuesto.
3. Sección independiente **Foto patrimonial · 1 de [mes]**. Solo si completa:
   patrimonio neto, activos/deudas y líquidos que ya publica Patrimonio.
   Si ausente/incompleta: **Sin dato** y fichas pendientes; **Registrar foto**
   o **Completar foto**. No completar con valores del mes anterior.
4. **Pendientes** obtenidos de datos existentes: movimientos sin categorizar
   y foto incompleta. Entradas **Importar CSV**, **Categorizar pendientes** y
   **Registrar foto**. Una ausencia de datos no genera un score o umbral.
   No afirmar «0 pendientes» mientras la consulta está cargando o falla.

No usar «dinero disponible» o «saldo disponible» para el resultado firmado.
La foto no se actualiza al importar movimientos ni al cambiar categorías.
No mostrar «actualizando banco» o fecha de sincronización bancaria.

**Presupuesto** conserva alcance anual y mes enfocado por separado. Muestra
resumen, partidas por rama y entradas **Captura mensual**, **Preparar año
siguiente** y **Ver detalle**. Este último contiene matriz de doce meses,
total anual, expansión hasta tres niveles y las mismas altas/ediciones por
UUID. Propuesta conserva revisión, desglose y confirmación de sustitución.
Mes sin partida muestra **Sin presupuesto**, distinto del cero explícito.

**Movimientos** muestra actividad legible (fecha de valor, concepto, cuenta,
categoría e importe firmado) y filtros activos visibles. **Ver detalle**
expone la lista completa paginada con los mismos filtros; no trunca
registros detrás de un resumen. Registro/edición, selección individual/lote,
Sin clasificar, borrado confirmado y procedencia siguen disponibles.

**Patrimonio** muestra la fecha de referencia, activos/deudas/neto y
liquidez. **Ver detalle** conserva todas las fichas vigentes, valores,
histórico y huecos reales; un año nunca presenta una suma anual de fotos.
**Registrar/corregir foto** y **Gestionar fichas** tienen entrada propia.

**Real anual** en Análisis muestra un resumen del año, seguido de
**Ver detalle** para su matriz de doce meses y todos los registros de origen.
No filtrar la consulta al mes enfocado. Usa EP-022, incluido Sin clasificar.
**Indicadores** conserva únicamente el colchón y sus causas de ausencia;
**Ver detalle** explica entradas/fórmula y facilita completar foto o
presupuesto. No añade otro indicador, umbral o recomendación financiera.

## Rutas y continuidad

| Ruta | Destino diseñado y continuidad |
| --- | --- |
| `/inicio` (nueva) | Resumen de Inicio; propietario monthly_status. |
| `/estado` | Comparación mensual completa: conservar significado de enlaces antiguos. |
| `/presupuesto` | Entrada anual; detalle completo en `/presupuesto/detalle` (nuevo). |
| `/presupuesto/mensual`, `/presupuesto/propuesta` | Captura y propuesta existentes, sin motor nuevo. |
| `/presupuesto/partidas[/nueva o /:id]` | Listado, alta y edición existentes; rangos y UUID conservados. |
| `/movimientos[/nuevo o /:id]` | Lista, alta y edición actuales; `/movimientos/detalle` (nuevo) reutiliza la misma lista. |
| `/pendientes-categorizacion` | Bandeja actual, también con filtro de lote. |
| `/patrimonio`, `/patrimonio/foto` | Resumen y captura; detalle en `/patrimonio/detalle` (nuevo). |
| `/patrimonio/fichas[/nueva o /:id]` | Catálogo/ficha/liquidez existentes. |
| `/analisis`, `/mas`, `/gestion` (nuevas) | Agrupaciones de presentación, sin repositorio ni modelo financiero. |
| `/real`, `/indicadores` | Mantener enlaces existentes; detalles `/real/detalle` y `/indicadores/detalle` nuevos. |
| `/categorias[/nueva o /:id]` | Árbol, formulario, traslado/archivo/reactivación y selectores actuales. |
| `/importaciones/csv`, `/importaciones/revision` | Selección/revisión/confirmación/resultado actuales. |
| `/importaciones`, `/importaciones/lotes/:id`, `/importaciones/origen/:id` | Historial, lote y procedencia; entrada a registro y pendientes del lote. |
| `/importaciones/openbank` (reservada) | Selección Openbank cuando se conecte su selector existente. |
| `/drive`, `/copias-locales[/:id]` | Drive manual y catálogo/detalle/restauración; sin acceso automático a red. |
| `/diagnostico` (reservada) | Diagnóstico manual EP-025; todavía pendiente, sin motor en EP-026. |
| `/`, `/error` | Inicio al arrancar tras T06; error conserva mensaje, retorno y recuperación. |

Los patrones con
`:id` representan UUID o identificadores ya admitidos por su parser; nunca
se insertan literalmente en una URL. Registrar rutas estáticas antes de
patrones dinámicos (`detalle`/ `nuevo`/ `nueva` no son UUID).

Adaptación de T06: mantener cada ruta antigua y sus argumentos, incluso
`/estado` con periodo/categoría. Solo `/` se transforma en Inicio al
arrancar; no convertir un origen serializado de Estado en resumen. No
reescribir prefijos arbitrarios. Resolver primero URI local sin scheme,
authority, fragmento ni parámetros duplicados; después el parser propio.
Conservar alias ya publicados `c`, `direct`/`branch` solo en parsers que los
admiten. Parámetros inválidos ofrecen **Volver al origen**, sin consulta,
escritura ni cambio de periodo. Respetar los contratos estrictos de
`BudgetOrigin`, `MonthlyStatusOrigin`, `BudgetLinks` y `MovementLinks`;
T06 adapta Inicio y los nuevos destinos de forma explícita y probada.

Gestión agrupa CSV/Openbank, historial, categorías, fichas, Drive, copias
locales y diagnóstico. Importar es también una acción contextual en Inicio
y Movimientos; categorizar aparece ahí y al terminar un lote; registrar foto
aparece en Inicio, Patrimonio y en el motivo de ausencia del indicador.
No hace falta recorrer Gestión para las tres tareas diarias.

## Disponibilidad y propiedad

El catálogo distingue `existing` (ruta/capacidad existente, sin afirmar que
ya tenga el nuevo diseño), `marker` (ruta técnica), `new` (ruta diseñada),
`integrationPending` y `backlog`. La interfaz futura debe mostrar un motivo
si no está conectado un servicio; nunca sustituir un marcador por cifras
sintéticas. Openbank existe como adaptadores/selectores, pero la entrada
actual «Importar XLS» está deshabilitada: T11 conectará ese recorrido.
No se presenta la ruta reservada como una importación ya operativa.

Consulta del tablero del 2026-10-12: MA-TSK-174 está terminado (consulta
anual); 175–180 bloqueados. EP-023/024/025 permanecen en backlog.
Sus motores, interfaces, enlaces y pruebas mantienen propietario. T04
coordina sus estados visuales; T05 publica el kit; T14 integra cuando hayan
entregado sus interfaces/cálculos. Esas épicas no dependen de T14.
Diagnóstico se reserva como composición de EP-025, sin inventar un noveno
ModuleId. T06 tampoco consulta SQLite desde el shell.

MA-TSK-204 aparece `done`, pero su actividad final dice que no pudo acceder
al checkout y no modificó archivos. No hay artefacto T01 en este checkout
al iniciar T02. Es una carencia de evidencia para T04/T14; esta entrega
verifica su propio catálogo, no declara completada la auditoría T01.

## Traspaso

T03 define identidad y accesibilidad visual; T04 carga este mapa y prueba
todos los recorridos con datos sintéticos antes de pedir aprobación explícita.
T05 materializa la API documentada. T06 conecta el router, sesión y shell.
T07–T13 y las interfaces EP-022/023/024/025 usan los mismos slots, sin editar
el shell ni mover motores de otras funcionalidades. Un cambio de este
contrato exige actualizar catálogo, documentos y casos de aceptación en el
mismo ticket, identificando consumidores afectados.

La [verificación de T02](verificacion-navegacion.md) distingue las pruebas
de contrato de los recorridos visuales/nativos todavía pertenecientes a
T04/T06/T14.
