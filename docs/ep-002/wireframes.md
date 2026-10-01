# MA-TSK-016 · Wireframes de las cinco vistas

Entrega de baja fidelidad del 2026-10-01. Abrir [el atlas HTML](wireframes.html) en un navegador con JavaScript: no necesita servidor, red ni dependencias. Cada lámina contiene PC y Android, incluidos los formularios. El índice y los enlaces entre láminas permiten revisar la arquitectura; los selectores entre corchetes y campos son representaciones, no controles de una aplicación. No guarda datos ni sustituye el prototipo navegable posterior. La aprobación humana corresponde a MA-TSK-019 y sigue pendiente.

Fuentes leídas: [contrato funcional](../ep-001/especificacion.md), [casos sintéticos y CSV](../ep-001/casos-referencia.md), [navegación MA-TSK-013](mapa-navegacion.md), [flujos MA-TSK-014](flujos-criticos.md) y [sistema visual MA-TSK-015](sistema-visual.md). Se usa el ticket facilitado en la conversación: no hay herramienta de Epic Board disponible para consultar o actualizar el tablero. No se modifican estos contratos ni se implementa Flutter.

## Cómo interpretar las láminas

PC coloca destinos en una barra lateral de 200 y contenido en una tabla compacta. Android usa una columna de tarjetas de 360, cabecera con periodo y Gestión, y cinco destinos inferiores con etiquetas. El atlas presenta ambas versiones juntas; en ventanas estrechas las apila para poder examinarlas. No es una simulación de la ventana de una app: su índice exterior es una herramienta de revisión.

Se aplica la jerarquía de MA-TSK-015: título → periodo → acción → resumen → desglose → recuperación. Las cifras llevan EUR, signo y céntimos; la diferencia lleva A favor, En contra o Sin diferencia. La raíz es un subtotal, no un registro que se suma otra vez. Las acciones de real y previsto se separan. Las matrices PC contienen doce columnas mensuales y total, con desplazamiento interno y cabeceras persistentes. Android conserva los doce meses en cada tarjeta anual, desplegables, con total anual antes del desglose. El selector de mes enfocado del futuro prototipo facilitará saltar a un mes sin eliminar los restantes.

## Cobertura de aceptación

Cada enlace abre la pareja de wireframes, no una captura descrita solo con texto.

| Vista | Pareja PC / Android | Periodo y subtotales | Desglose y estados |
|---|---|---|---|
| Estado mensual | [Estado](wireframes.html#estado) | Año/mes; previsto, directo, agregado, diferencia; total firmado | Tres niveles de Alimentación; Ocio sin presupuesto; febrero desfavorable; mes sin reales; caso J con directos, pendientes y agregados distintos; padre presupuestado sin reparto |
| Patrimonio | [Patrimonio](wireframes.html#patrimonio) | Foto del día 1; cuentas, carteras, líquidos, medios, no líquidos, activos, deudas y neto | Ficha/tipo/liquidez/valor; doce fotos independientes; foto ausente e incompleta con pendientes; cero registrado; nunca suma anual de saldos |
| Presupuesto anual | [Presupuesto](wireframes.html#presupuesto) | Año; doce meses; suma anual por rama y total firmado mensual/anual | Raíces y rutas de partidas hasta nivel 3; sin presupuesto frente a cero explícito; padre como subtotal; no reparte ni duplica |
| Real anual | [Real](wireframes.html#real) | Año; doce meses según fecha de valor; total mensual/anual | Raíces, descendientes y variante Sin clasificar; mes vacío 0,00; cifras abren listas directas o de rama completa |
| Indicadores | [Indicadores](wireframes.html#indicadores) | Año/mes; líquidos de foto y presupuesto del mismo año / 12 | Fórmula, entradas, único indicador en v1; cinco causas de sin dato en orden; acciones específicas; numerador cero válido |

### Equivalencia entre tabla y tarjeta

| Información en PC | Información conservada en Android |
|---|---|
| Fila y cabeceras de Estado | Ruta completa y pares rotulados previsto agregado, real directo, real agregado y diferencia |
| Sangría de categoría y subtotal | Ruta completa hasta tres niveles; no depende de sangría ni color |
| Celda mensual y columna anual | Cada tarjeta identifica año, doce meses y total anual; importe enlazado a la entidad correspondiente |
| Ficha y sus columnas | Tarjeta con nombre, tipo, liquidez y valor manual; fecha común en cabecera |
| Subtotales/total y avisos | Mismos textos e importes; no oculta pendientes ni presenta subtotales parciales como válidos |
| Lista de movimientos | Una tarjeta por registro, incluso para dos Café idénticos; fecha, cuenta, categoría, signo y Discrecionalidad |

Estado no usa «sin dato» por falta de foto: muestra real cero cuando no hay movimientos y «sin presupuesto» cuando falta partida. Presupuesto y Real tampoco requieren foto. Los errores de lectura sí muestran un aviso con recuperación, sin fingir ceros. Patrimonio e Indicadores muestran «sin dato» y motivo cuando faltan sus entradas.

## Edición y pantallas secundarias

| Lámina doble | Entrada y campos | Confirmación, errores y retorno del futuro prototipo |
|---|---|---|
| [Lista y detalle](wireframes.html#movimientos) | Cifra real → lista; rama completa / solo nodo; subtotal, dos Café separados y todos los campos del detalle | Volver conserva vista, año, mes, rama y filtros; mes vacío conserva lista y total cero |
| [Movimiento](wireframes.html#movimiento) | Añadir o editar; fecha de valor, concepto, importe firmado no cero, cuenta obligatoria, categoría opcional y Discrecionalidad | Error junto al campo, conserva entradas y foco al primer error; guardar vuelve al origen; fecha fuera del mes informa nuevo destino del registro; transferencia manual por pierna |
| [Partida](wireframes.html#partida) | Cifra prevista → lista y edición; año/mes, categoría e importe, sin cuenta | Cero válido; conflicto Vivienda / Alquiler y Vivienda en enero bloquea guardado; presupuesto previo intacto; retorno a celda |
| [Propuesta anual](wireframes.html#propuesta) | Preparar 2027 desde 2026; referencia real, propuesta por raíz y mes; editar o desglosar | Revisa doce meses, ceros y signos atípicos; desglose retira padre; valida antes de guardar; sustitución exige confirmación con partidas afectadas; cancelar vuelve a 2026, guardar a 2027 |
| [Foto](wireframes.html#foto) | Patrimonio o motivo de Indicadores; referencia fija al día 1 y valores de fichas vigentes no negativos | Vacío pendiente distinto de cero; admite guardar incompleta manteniendo sin dato; completar recalcula; cancelar vuelve al destino y mes originales |
| [Ficha](wireframes.html#ficha) | Gestión o foto; nombre, tipo, liquidez de activo y meses de alta/baja inclusivos | Deuda sin liquidez; conserva histórico; vigencia determina pendientes; guardar/cancelar retorna al origen |
| [Categoría](wireframes.html#categoria) | Gestión o selector; nombre, padre y ruta completa | Máximo tres niveles; hijo requiere padre; ingreso editable solo en raíz y heredado; guardar vuelve al selector con nuevo nodo, cancelar conserva selección anterior |
| [Gestión y estados comunes](wireframes.html#gestion) | Acceso desde todos los destinos; enlaces secundarios | Cargando, lectura fallida/reintentar, vacío y salida con cambios sin guardar. CSV y Drive se desarrollarán en el prototipo usando los guiones de MA-TSK-014 |

Los enlaces de guardar/cancelar del atlas ilustran un destino concreto, no ejecutan el cambio ni preservan un historial. El futuro prototipo debe recibir y restaurar el origen real, conservar selección y scroll, y devolver el foco. Lo mismo aplica a selección de periodo, expansión de ramas, validaciones, confirmaciones y gestión de datos: el atlas fija su contenido y ubicación; no afirma haber validado interacciones que aún no existen.

## Guion de revisión y resultados

Se verificaron las cifras con `node docs/ep-001/verificar-casos.mjs`: **OK**, 48 presupuestos y 10 reales; enero real +1.229,75 €, real anual +2.329,65 €, presupuesto anual +13.200,00 €. Se compararon además las cifras dibujadas con los casos B–H y J: enero neto 14.000,00 €, colchón 3,00 meses; febrero completo de la variante D neto 11.900,00 € y colchón 2,07; propuesta Alimentación enero −360,00 €.

Comprobación estructural mediante ejecución del script del atlas en Node: todas las láminas generan dos marcos, todas las anclas internas resuelven, las matrices tienen doce meses y columna anual, y las tarjetas conservan esos doce meses. Los importes se generan desde los mismos datos para PC y Android. Los dos Café conservan fecha 09/01/2026 del CSV y registros separados.

La revisión visual en navegador se intentó, pero no hay navegador conectado disponible. Queda sin verificar el renderizado real y la interacción con teclado/lector de pantalla. Antes de aprobar el mockup, revisar las cinco vistas y ediciones en Windows 1024×768 y 1440×900 y Android 360×800 y 412×915, también 320 dp y texto al 200 %. Comprobar especialmente desplazamiento de matrices, importes sin truncar, foco, tamaño táctil y retorno a origen. Estos resultados deberán registrarse en los tickets de prototipo y validación. No existe proyecto Flutter en este checkout para ejecutar análisis o pruebas Flutter.
