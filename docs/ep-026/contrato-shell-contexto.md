# MA-TSK-205 · Contrato del shell y contexto v1

Especificación de API para MA-TSK-208 (kit T05), MA-TSK-209 (shell T06)
y sus consumidores. La API aún no se activa en Flutter. No depender de
código simulado del futuro prototipo. La aprobación de MA-TSK-207 habilita
la implementación visual; estas interfaces de diseño pueden prepararse antes.

## Propiedad y entradas públicas

- `lib/ui/autofinance_ui.dart` será la entrada pública del kit T05. Solo
  presentación Flutter; no importa `app`, `features`, SQLite ni servicios.
  `core` conserva su regla de Dart puro y no recibe widgets.
- `lib/app/navigation/` compone el shell T06 y adapta sesión/rutas/servicios.
  Cada funcionalidad sigue consumiendo dominio y callbacks por constructor.
  Ninguna funcionalidad importa `app` para navegar.
- Cada módulo publica sus loaders/consultas y callbacks mínimos desde su
  propia presentación. La app aporta los concretos. Presupuesto reutiliza
  `AnnualBudgetNavigation`; Estado su navegación de detalle; Real anual
  sus consultas/enlaces de EP-022. El kit no se convierte en motor de informes.

T05 deberá ampliar la comprobación de arquitectura para permitir
`features/*/presentation → ui` por su entrada pública y `app → ui`.
`domain`, `data` y `core` no importan el kit; `ui` solo depende de
Flutter/Dart y de sí mismo. La prueba actual solo admite `core/features`
desde funcionalidades: no añadir widgets a `core` para sortearla.
El grafo permanece acíclico y esa ampliación se verificará en T05.

API de presentación acordada para materializar en T05 (firmas normativas):

```dart
typedef AfSelectDestination = Future<bool> Function(String destinationId);

class AfNavItem {
  const AfNavItem({
    required this.id,
    required this.label,
    required this.icon,
    this.unavailableReason,
  });
  final String id; // IDs del catálogo, no nombres de módulos.
  final String label;
  final IconData icon; // T03/T05 eligen iconos propios del kit.
  final String? unavailableReason;
}

class AfPageSlots {
  const AfPageSlots({
    required this.title,
    required this.body,
    this.contextTrail,
    this.actions = const [],
    this.status,
    this.detailAction,
  });
  final String title;
  final Widget body;
  final Widget? contextTrail;
  final List<Widget> actions;
  final Widget? status; // Cargando/vacío/error/sin dato de su propietario.
  final Widget? detailAction;
}

class AfShell extends StatelessWidget {
  const AfShell({
    super.key,
    required this.primaryItems,
    required this.utilityItems,
    required this.selectedId,
    required this.onSelect,
    required this.periodControl,
    required this.page,
    this.onBack,
  });
  final List<AfNavItem> primaryItems;
  final List<AfNavItem> utilityItems;
  final String selectedId;
  final AfSelectDestination onSelect;
  final Widget periodControl; // Obligatorio en todas las entradas.
  final AfPageSlots page;
  final Future<bool> Function()? onBack;
  // build lo implementa T05/T06 tras la aprobación, no T02.
}
```

Las firmas describen componentes; el bloque no es una biblioteca compilable
ni afirma que los widgets existan. Iconos/tokens/breakpoints definitivos son
propiedad T03/T05; T06 elige la proyección del catálogo para la superficie.
Partir del límite adaptable existente de 840 px en el prototipo y probar
PC 1024×768/1440×900, Android 360×800/412×915, ancho 320 px, el cambio a
840 px y texto 200 %, sin obligar a densidad de PC en Android.

El shell contiene navegación, encabezado, periodo, retorno y slots. No
envuelve un Scaffold de una pantalla dentro de otro. T06 extrae las
composiciones duplicadas de `PrimaryNavigation` y Patrimonio; cada consumidor
entrega contenido. `status` no crea por su cuenta estados financieros.
`detailAction` es **Ver detalle** con el callback del propietario, no un
botón que invente una tabla a partir de tarjetas parciales.

La app calcula `selectedId`: Real/Indicadores/Diagnóstico → Análisis en
Windows; Real/Indicadores/Análisis/Gestión → Más en Android. En secundarios,
mantiene el principal de la captura de origen. En Gestión de Windows no
marca un informe financiero distinto. La selección solo se publica después
de un `onSelect` que devuelve true. false conserva pantalla, foco y periodo.

`entrySelection` del catálogo fija la selección al entrar directamente en
un informe o agrupación, también desde un enlace sin pila. `/estado` conserva
su comparación completa con Inicio seleccionado. `/mas` se conserva como
agrupación al abrirlo en Windows y selecciona la utilidad Gestión; no se
redirige ni cambia el contenido. En secundarios manda la captura del origen:
una ficha abierta desde Patrimonio conserva Patrimonio, y desde Gestión
conserva Gestión/Más. Sin captura, usar el padre de la ruta: presupuesto,
movimientos, patrimonio o Gestión para categorías/importación/copias/Drive.
Una entrada directa a diagnóstico selecciona Análisis/Más; desde Gestión
conserva esa agrupación. Estos valores son IDs de presentación; no alteran
`ModuleId` ni el destino financiero del contexto.

Un cambio de tamaño conserva destino exacto, captura y periodo y solo
proyecta de nuevo `selectedId`. Por ejemplo, Indicadores pasa de Más a
Análisis al ensancharse sin navegar, perder foco ni disparar otra consulta.
Un `onSelect` en curso deshabilita temporalmente nuevas selecciones; el
adaptador resuelve el guard antes de publicar ruta y contexto como una sola
transición. Una cancelación o error conserva ambos y permite reintentar.

Cada pantalla aporta acciones disponibles, loader/controlador propio y
callbacks ya validados (`onImport`, `onPending`, `onPhoto`, `onDetail`,
`onEdit`). Un callback no disponible se representa con motivo explícito;
no se conecta a una implementación falsa. Entrar a Drive o al catálogo no
autoriza una subida, descarga, restauración o escritura.

## Una sola sesión y captura de origen

Reutilizar `NavigationSession`, `NavigationContext`, `NavigationPeriod`,
`AnnualNavigationPeriod` y `SecondaryNavigationContext`. T06 extenderá el
catálogo de destinos de presentación sin duplicar el estado en cada pantalla
ni cambiar los IDs de módulos financieros. Extender `SessionDestination`
para los destinos nuevos requiere actualizar parsers/observer y sus switches
y pruebas en ese mismo ticket; los cinco valores actuales conservan su
semántica, en especial `status` para la comparación `/estado`.

El contexto transporta destino exacto, año/mes, vista mensual/anual,
UUID/alcance de categoría, filtros inmutables, posición y token de foco.
No guardar este estado en SQLite/Drive. Para listas se conserva además el
rango/consulta propio existente: `desde`/`hasta` son fechas en Movimientos,
pero meses en partidas. No reinterpretarlos con un parser universal.

El selector mensual nombra **Enero de 2026**; el anual **Año 2026 · Mes
enfocado: enero**. Elegir un mes enfocado no reduce una consulta anual.
Gestión conserva el periodo de trabajo aunque no tenga cifras propias.
En Movimientos se distingue rango derivado del periodo y rango personalizado:
sin captura se abre el mes de trabajo completo; una captura conserva su
rango. Cambiar explícitamente mes/año ajusta el rango derivado; un rango
personalizado sigue visible como **Rango propio: [fechas]**, con acción
**Usar mes seleccionado** para sustituirlo. No ocultar esa diferencia ni
reinterpretar un rango anual del desglose como el mes enfocado. El adaptador
guarda esa procedencia de filtro en la captura en memoria, sin cambiar los
serializers financieros existentes.

| Operación | Contrato de contexto |
| --- | --- |
| Arranque nuevo | Leer reloj Europe/Madrid una vez; usar mes actual o contexto explícito recibido. |
| Cambiar principal | Mantener periodo elegido; guardar captura del saliente; restaurar filtros del destino si existe captura compatible. |
| Entrar a destino por primera vez | Mismo año/mes; filtros propios iniciales, sin copiar filtros de otro informe. |
| Cambiar mes explícitamente | Mantener rama/alcance y filtros aplicables; invalidar scroll/foco de resultados antiguos como hace `withPeriod`. |
| Cambiar año en mensual | Mantener número de mes. |
| Cambiar año en anual | Mes recordado para ese año o enero, como `periodForYear`; año de consulta completo. |
| Abrir detalle/editor/selector | Push con captura completa y foco originario; jamás leer reloj para elegir periodo. |
| Volver con pila | Pop, restaurar origen completo; releer cifras si cambió la base, conservar categoría/filtros/scroll/foco. |
| Volver sin pila | Reconstruir origen validado mediante el parser existente y argumentos; ruta inválida no consulta datos. |
| Cambiar mes dentro de captura secundaria | `secondarySession` local; no cambia el informe padre. |
| Guardar fuera del periodo | Aviso con **Ver mes** explícito; guardar por sí solo no salta a otra fecha. |
| Mes actual | Única acción, además del arranque, que consulta reloj y cambia explícitamente al mes actual. |

T06 será propietario de un almacén de capturas en memoria por ID de destino,
basado en `NavigationContext`, para volver entre principales sin perder
categoría/filtros/expansiones/scroll/foco. Al entrar con un periodo diferente,
aplicar `withPeriod(periodoDeTrabajo)` a la captura: no restaurar su mes viejo.
Un detalle posee su captura completa independiente, aunque se cambie el
periodo local secundario. No restaurar un callback tardío sobre un principal
que ya no es el origen activo. Guardar revisión de navegación y comprobar
`mounted`/ruta actual; reutilizar el control de respuestas tardías de
`NavigationSession.setContext`.

Cambiar destino puede releer datos para el periodo seleccionado. La regla
«cero recarga silenciosa de periodo» prohíbe elegir de nuevo el mes actual,
borrar el año del usuario o alterar filtros sin indicarlo. No prohíbe una
lectura coherente tras una mutación. Restaurar una base invalida los lectores
y la sesión de datos mediante los mecanismos existentes, no copia valores
antiguos a una conexión nueva.

## Back, teclado y protección de trabajo

Android Back y **Volver** comparten el mismo guard: primero diálogo abierto,
después selector/detalle/editor, después origen y finalmente salida de la
app desde un principal. Back desde Más vuelve al principal anterior; volver
de Análisis/Real/Indicadores conserva la captura que abrió la agrupación.
No apilar cada selección principal como una nueva copia del informe.

Edición sucia, revisión de importación y propuesta pasan por
`NavigationLeaveGuard` antes de cambiar destino, periodo, detalle o cerrar.
Presentar **Seguir editando / Descartar cambios**; **Guardar y continuar**
solo si el formulario propietario puede validar/guardar. Cancelar conserva
borrador/selección, periodo, foco y ruta. Descartar no escribe. Restaurar,
borrar y sustituir presupuestos conservan su confirmación específica.
Guard de navegación no sustituye una confirmación de escritura.

Orden de teclado: navegación, periodo, acciones de página, contenido.
Tab/Shift+Tab recorren controles; Enter/Espacio los activan; Escape cierra
el nivel superior o pide resolver borrador. En Windows Alt+Izquierda usa el
mismo retorno protegido. No robar Ctrl+F ni atajos de editores. FocusTraversal
y nombres accesibles en kit; seleccionado se anuncia por Semantics. Al volver
se restaura el token o, si el registro dejó de existir, el encabezado de la
lista con aviso; scroll se limita al nuevo tamaño. En Android cada acceso
principal incluye icono y etiqueta, área táctil accesible y seleccionado
anunciado. El selector de periodo sigue visible al aumentar texto, mediante
reflujo, no ocultándolo en Más.

## Recuperación sin base activa

Arranque: resolver restauración interrumpida antes de abrir SQLite. Si no
hay base utilizable, raíz única de recuperación `/copias-locales`, sin informe
de datos debajo en la pila ni constructor que obligue a abrir la base rota.
Ofrecer listado/detalle/restauración, progreso real y error reintentable con
los servicios independientes existentes. Solo tras reapertura validada se
compone Inicio y se recomponen consultas. Android Back no descubre un informe
que nunca pudo abrirse. El selector muestra el contexto conservado pero no
sugiere cifras de una base ausente. Entrada Drive exige su servicio disponible
y una acción remota explícita; nunca se descarga una copia por arrancar.

## Entrega independiente

| Propietario | Entrega que consume el contrato |
| --- | --- |
| T03/T04 | Identidad, mapa navegable y estados reales/ausencias; aprobación de T04 registrada. |
| T05 | Entrada UI pública, slots, selector, accesibilidad y ejemplos sintéticos. |
| T06 | Router, snapshots de principal, guards, aliases y arranque/recuperación. |
| T07–T13 | Contenido/actions/status/detailAction; cálculo y servicios existentes por constructor. |
| EP-022/023/024/025 | Consultas/estados/callbacks propios e interfaces usando kit T05. |
| T14 | Integración y evidencia visual/nativa de todo lo anterior. |

T05 puede fijar los widgets y T06 sus adaptadores sin que cada pantalla
modifique la API. Los detalles actuales siguen usando sus serializers y
puertos. Cambios de firma después de v1 se revisan contra todos los
consumidores y la batería de navegación histórica, no se hacen incidentalmente.
