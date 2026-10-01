# MA-TSK-015 · Sistema visual adaptable y accesible

**Estado:** guía de diseño para el prototipo de EP-002. Pendiente de validación en el prototipo y de aprobación humana del mockup MA-TSK-019; no define widgets Flutter. Se apoya en el [mapa de navegación](mapa-navegacion.md), los [flujos críticos](flujos-criticos.md), la [especificación aprobada](../ep-001/especificacion.md) y los [casos sintéticos](../ep-001/casos-referencia.md). Todos los ejemplos son sintéticos.

## 1. Principios y formato

- La información financiera se lee primero por **concepto y periodo**, después por **tipo de cifra** (previsto, real, diferencia o valor de foto) y finalmente por **importe y estado**. El signo describe entrada o salida; una diferencia positiva es favorable según el contrato, incluso en una raíz de salida. La marca de ingreso de una raíz no se deduce del signo.
- Cada cifra navegable identifica qué registros abre. Un agregado se rotula «Rama completa» y un importe asignado al propio nodo se rotula «Directo». Presupuesto y real abren listas distintas. No se suma una fila padre otra vez en el total general.
- La vista usa español y formato `es-ES`, EUR y dos decimales: `+1.229,75 €`, `−350,25 €`, `0,00 €`. Se usa el signo menos tipográfico `−` en pantalla; al copiar o introducir se acepta el guion `-`. El signo y los céntimos permanecen visibles en tablas, tarjetas, formularios, resúmenes y lectores de pantalla. Los importes se alinean por la coma decimal, con cifras tabulares cuando la fuente lo permita. Se redondea solo al presentar, nunca antes de sumar.
- Los saldos patrimoniales son valores de la **foto del día 1**. La deuda se muestra como magnitud `5.000,00 €` bajo la etiqueta «Deudas»; la fórmula del patrimonio explica que se resta. Una foto ausente o incompleta no genera un subtotal numérico.

## 2. Tamaños y composición adaptable

Las medidas son píxeles lógicos (dp en Android; unidades independientes de escala en el diseño de Windows). Los cortes responden al **ancho disponible para la app**, no al tipo de dispositivo. La interfaz admite zoom del sistema y texto al 200 %; el contenido crece antes de truncar importes o mensajes. No hay desplazamiento horizontal de la página completa; solo la matriz anual de Windows puede desplazarse dentro de su contenedor con cabeceras y primera columna fijas.

| Ancho disponible | Destinos y estructura | Datos y acciones |
|---|---|---|
| 320–599 | Barra inferior con `Estado`, `Patrimonio`, `Presupuesto`, `Real`, `Indicadores`; encabezado con título y periodo. Contenido a una columna, margen 16, separación 12. | Tarjetas por rama, ficha, movimiento o mes; importes en líneas etiquetadas. Acción primaria visible en el encabezado o al final del bloque. Menú `Gestión` accesible desde el encabezado. En 320 dp y texto ampliado, la barra puede usar solo etiquetas visibles en dos líneas; no se sustituye por iconos solos. |
| 600–839 | Misma navegación inferior; margen 24 y ancho máximo de lectura 720. | Tarjetas de hasta dos columnas solo si cada una conserva al menos 280; formularios a una columna. |
| 840–1199 | Barra lateral persistente de 200; contenido con margen 24 y ancho flexible. | Estado, listas y Patrimonio usan tablas compactas; filtros y acciones junto al título. Matrices anuales en contenedor desplazable, con primera columna y cabecera fijas. |
| ≥1200 | Barra lateral de 216; margen 32; contenido máximo 1440 centrado. | Tablas compactas con más columnas visibles; panel de detalle lateral opcional de 320–400 si quedan al menos 720 para la tabla. La ruta de detalle sigue funcionando sin panel. |

Objetivos de revisión: Android estrecho **360×800** y ancho **412×915**; Windows **1024×768** y **1440×900**, todos con escala normal y texto ampliado. A 320 dp no se oculta ninguna de las cinco rutas. En matrices anuales, Android muestra selector de mes, tarjeta por rama y total anual identificable; cambiar de mes conserva año, rama y significado de cada cifra. Windows muestra enero–diciembre y total anual en la tabla compacta, con desplazamiento interno cuando falte ancho. Patrimonio recorre doce fotos, sin total patrimonial anual.

### Rejilla y densidad

Escala de espaciado: `4 / 8 / 12 / 16 / 24 / 32 / 48`. Radio: 8 para controles y 12 para tarjetas; borde 1. Altura visual mínima de fila de tabla: 40, ampliable según texto; controles de Windows: mínimo 36 de alto. En Android, toda zona pulsable mide al menos **48×48** y separa objetivos vecinos al menos 8. El espacio bajo la barra inferior respeta el área segura del sistema. La densidad compacta no reduce texto por debajo de 14 ni achica zonas táctiles en pantallas con tacto.

## 3. Tipografía, importes y color

Fuente del sistema de cada plataforma, con alternativas que soporten `€`, acentos y `−` (por ejemplo Segoe UI en Windows y Roboto en Android). No se descarga una fuente para usar la app. Escala base con interlineado aproximado de 1,4 y crecimiento del sistema:

| Uso | Tamaño / peso | Aplicación |
|---|---|---|
| Título de vista | 24 / seminegrita | «Estado del mes», «Presupuesto anual». |
| Título de sección o cifra destacada | 20 / seminegrita | Total firmado, patrimonio neto, `3,00 meses`. |
| Título de tarjeta / fila principal | 16 / seminegrita | Rama, ficha o concepto. |
| Cuerpo, controles y celdas | 16 / regular; en tabla Windows 14 / regular | Etiquetas, importes y acciones. El importe de total usa seminegrita. |
| Ayuda, origen y metadatos | 14 / regular | Fecha de valor, cuenta, «Rama completa», estado de copia. |

| Token | Valor | Uso y contraste calculado frente al fondo indicado |
|---|---|---|
| `surface` / `canvas` | `#FFFFFF` / `#F5F7FA` | Tarjetas y tabla / fondo de la vista. |
| `text` / `muted` | `#17212B` / `#455468` | Texto principal: 16,29:1 sobre blanco; secundario: 7,72:1 sobre blanco. |
| `action` / `actionTint` | `#124B7A` / `#EAF3FB` | Enlaces, selección y botón primario blanco sobre `action`: 9,08:1; texto `action` sobre tinte: 8,09:1. |
| `positive` / `positiveTint` | `#166534` / `#EAF6EE` | Diferencia favorable con texto «A favor»: 6,42:1 sobre tinte. |
| `negative` / `negativeTint` | `#9F2733` / `#FCEDEF` | Diferencia desfavorable con texto «En contra»: 6,58:1 sobre tinte. |
| `caution` / `cautionTint` | `#8A4B08` / `#FFF4E5` | Revisiones y conflictos: 6,25:1 sobre tinte. |
| `focus` | `#005FCC` | Anillo de foco de 2 px con separación de 2 px; contraste 5,98:1 sobre blanco. |

Los colores se usan solo junto con **signo, etiqueta y texto**. Un importe real `−20,00 €` no se pinta rojo por ser negativo: rojo queda reservado para una **diferencia desfavorable o error**. Una diferencia `+49,75 €` lleva «A favor»; `−20,10 €`, «En contra»; `0,00 €`, «Sin diferencia». El estado «sin dato» lleva motivo y acción, nunca una cifra gris que parezca cero. La selección de pestaña añade texto y un indicador de forma; el foco añade anillo, no solo cambio de relleno. Bordes, iconos y gráficos informativos se verifican al menos a 3:1; texto normal al menos a 4,5:1. En alto contraste del sistema se priorizan colores y bordes del sistema, conservando las mismas etiquetas.

## 4. Componentes reutilizables

| Componente | Estructura y variantes | Estados obligatorios |
|---|---|---|
| Navegación principal | Cinco destinos con icono y nombre visible; destino actual marcado con barra o fondo y `actual` para tecnología asistiva. `Gestión` abre Importar CSV, Categorías, Fichas y Copia en Drive. | Normal, seleccionado, foco, deshabilitado solo cuando una ruta realmente no exista. |
| Encabezado de vista | Título, año/mes accesible por etiqueta, estado de periodo y acción principal. En rutas secundarias: `Volver a [vista, periodo]`. | Cargando, error recuperable, periodo vacío. Cambiar año no cambia a escondidas el mes elegido. |
| Resumen de cifra | Etiqueta de magnitud, importe, unidad, periodo y explicación breve de origen. Total firmado y patrimonio neto tienen mayor peso. | Calculable, cero explícito, sin presupuesto, sin dato con motivo. |
| Tabla compacta Windows | Encabezados persistentes, primera columna con árbol sangrado hasta tres niveles y botón `Expandir/Contraer`; importes alineados por decimal. Fila de raíz y total con seminegrita y separador. En Estado: previsto agregado, real directo, real agregado y diferencia; en matrices: meses y total. | Hover, foco de celda/acción, selección, fila expandida, vacío y error. La fila completa solo es pulsable si conduce a un único destino; de otro modo cada cifra tiene botón/enlace rotulado. |
| Tarjeta Android | Cabecera con ruta de rama, periodo y tipo; pares `Previsto`, `Real`, `Diferencia` o valor de ficha; acción textual «Ver movimientos» / «Ver partidas». La jerarquía se expresa con ruta completa y profundidad, sin depender solo de sangría. | Normal, expandida, foco externo, pulsación, sin presupuesto y sin dato. Una tarjeta nunca oculta el signo ni mezcla real y presupuesto en una sola acción. |
| Campo de importe | Etiqueta persistente, `€`, ayuda «Usa + para entrada y − para salida» en movimientos/partidas; teclado numérico con acceso a signo y coma en Android. La foto pide magnitud no negativa. | Vacío, cero escrito, válido, inválido con texto de causa junto al campo; error anunciado y foco dirigido al primer error al intentar guardar. |
| Selector de categoría | Árbol de máximo tres niveles con ruta completa y búsqueda opcional. Raíz de ingreso marcada «Ingreso: sí» en la gestión de raíces. | Ninguna selección, seleccionada, categoría inválida, conflicto padre/descendiente con ambas rutas y mes. `Sin clasificar` aparece como ausencia de categoría, no como nodo seleccionable. |
| Aviso y confirmación | Título específico, hecho ocurrido, consecuencia y acciones verbales. Ejemplo: «Copia más reciente en Drive» + ambas versiones + «Conservar datos locales» / «Descargar última copia». | Información, revisión, error, éxito confirmado. Un mensaje transitorio también queda disponible en una región de estado y en el historial de la vista si afecta datos. |
| Progreso | Texto de fase, por ejemplo «Leyendo CSV…», «Validando copia…», sin prometer éxito antes de confirmarlo. | Inactivo, en curso, éxito, fallo recuperable; bloquear solo la acción que podría duplicar una operación. |
| Iconos | Trazo simple de 20–24 con forma reconocible: estado (resumen), patrimonio (cartera), presupuesto (calendario), real (lista), indicadores (gráfico), gestión (ajustes), abrir (flecha), aviso (triángulo). | Siempre con etiqueta visible o nombre accesible; las acciones destructivas o de sustitución usan texto explícito, nunca icono solo. |

El orden visual y semántico de una fila o tarjeta de Estado es **rama → previsto → real directo → real agregado → diferencia → acciones**. En una fila padre, la cifra agregada lleva «Rama completa» y la directa «Solo esta categoría». La diferencia abre un selector claro «Ver movimientos reales» o «Ver partidas presupuestadas». Una fila de presupuesto sin partida muestra «sin presupuesto» y ofrece «Crear presupuesto»; `0,00 € (registrado)` representa una partida existente. En Real, un mes sin movimientos muestra `0,00 €`, con lista vacía explicativa al abrirlo.

## 5. Estados de contenido y ejemplos sintéticos

| Contexto | Presentación visible | Acción siguiente |
|---|---|---|
| Estado enero 2026, Alimentación | `Previsto −400,00 € · Real −350,25 € · Diferencia +49,75 € · A favor`. Si se abre el padre, las cifras indican «Rama completa». | «Ver movimientos reales» o «Ver partidas presupuestadas». |
| Estado enero 2026, Ocio | `Sin presupuesto · Real −20,00 € · Diferencia −20,00 € · En contra`; dos movimientos «Café» de `−10,00 €` cada uno permanecen como filas separadas. | «Ver 2 movimientos» o «Crear presupuesto». |
| Estado febrero 2026, total | `Previsto +1.100,00 € · Real +1.099,90 € · Diferencia −0,10 € · En contra`. | Abrir cada tipo de registro por separado. |
| Presupuesto 2027 propuesto, marzo sin reales | `Propuesta 0,00 € (registrado al guardar)` y `Sin movimientos en el mes de referencia`. | Editar antes de guardar; no llamarlo «sin presupuesto». |
| Patrimonio febrero 2026 sin foto | `sin dato: falta foto patrimonial`; fecha «Valores del 1 de febrero de 2026». | «Registrar foto del día 1». |
| Foto parcial de febrero | `sin dato: foto patrimonial incompleta · Faltan: Cuenta de ahorro y Cartera`. `Cuenta de ahorro 0,00 €` registrado sí completa esa ficha. | «Completar foto»; no mostrar patrimonio parcial. |
| Colchón enero / febrero | Enero: `3,00 meses`, con «Activos líquidos 9.000,00 € / ingresos mensuales presupuestados 3.000,00 €». Febrero sin foto: motivo `sin dato`. | Desde motivo, abrir la foto o el presupuesto del mismo periodo. |
| Drive en reposo / divergencia | `Versión remota conocida: A` o `desconocida`; divergencia: «Hay una copia más reciente en Drive; no se ha subido tu copia local», con versión local conocida y remota actual. | Solo `Subir copia` o `Descargar última copia` consultan Drive; la descarga con cambios locales pide confirmación expresa. |

## 6. Teclado, tacto y tecnología asistiva

- Orden de tabulación: navegación principal → Gestión → periodo → acción principal → filtros → contenido en orden de lectura → acciones de la fila/tarjeta. `Tab` y `Mayús+Tab` recorren controles; `Intro` o `Espacio` activan botones y selecciones; `Esc` cierra menú o diálogo y equivale a cancelar, sin guardar. Nunca se requiere arrastrar, mantener pulsado o usar gesto oculto. Las tarjetas tienen acciones textuales pulsables con 48×48 en Android.
- El foco visible acompaña cada control, también dentro de tablas desplazables. Al expandir una rama, el foco permanece en su botón y se anuncia «expandida»; al cerrarla, «contraída». Los encabezados de tabla identifican cada cifra y el nombre completo de la rama. La navegación anual anuncia mes y año al cambiar de tarjeta; el total anual conserva su propia etiqueta.
- Un diálogo de sustitución de presupuesto o descarga lleva el foco al título, contiene las consecuencias y devuelve el foco al botón que lo abrió al cancelar. Al confirmar, el foco pasa al resultado de la operación. El botón predeterminado es la opción conservadora; no hay confirmación por cierre accidental. Los formularios conservan entradas válidas tras error y conectan cada mensaje con su campo.
- Los avisos de guardado, fallo y cambio de periodo se anuncian mediante región de estado sin mover el foco salvo cuando se deba corregir un error. Una operación larga comunica fase y resultado. El texto alternativo de una cifra incluye signo, moneda, tipo y periodo: «Diferencia en contra, menos veinte euros con diez céntimos, Alimentación, febrero de 2026». `0,00 €` se anuncia como cero; «sin dato» y «sin presupuesto» se anuncian literalmente con su motivo.
- El tamaño de texto del sistema hasta 200 % permite crecer filas y tarjetas y envolver etiquetas; el zoom del 400 % en ancho de 1280 deja un recorrido de una columna. No se corta el signo ni el botón de cancelación. Se respeta la reducción de movimiento del sistema: transiciones prescindibles se eliminan. Las tablas y tarjetas no dependen de animación para revelar cifras o errores.

## 7. Comprobación del prototipo

La guía se considera aplicada cuando el prototipo permita revisar, con teclado y tacto, estos recorridos en los cuatro tamaños objetivo y con texto ampliado:

1. Pasar entre los cinco destinos conservando periodo; volver de una cifra de enero a su rama, celda y filtros. En PC comprobar tabla compacta y desplazamiento de la matriz sin perder encabezados; en Android comprobar tarjeta y total anual.
2. Comparar en Estado enero `+1.229,75 €` real y `+129,75 €` diferencia; abrir dos «Café» separados. Verificar que `−20,00 €` de Ocio y `−20,10 €` de diferencia desfavorable se distinguen por **etiqueta**, no por color.
3. Abrir febrero sin foto, completar con una ficha a `0,00 €` y comprobar el paso de «sin dato» a `11.900,00 €` de patrimonio y `2,07 meses` de colchón; cancelar un formulario sin perder el origen.
4. Revisar la propuesta 2027, el conflicto padre/hijo y los estados de CSV inválido y repetido, con error concreto, acción de recuperación y foco correcto.
5. Revisar Drive en reposo, subida divergente y confirmación de descarga con cambios locales. Confirmar que entrar o salir de la vista no inicia una transferencia.

Esta es una especificación visual verificable para los tickets de prototipo y mockup de EP-002. La aprobación humana del mockup de MA-TSK-019 sigue siendo requisito antes de implementar pantallas Flutter.
