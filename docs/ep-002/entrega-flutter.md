# MA-TSK-020 · Entrega para Flutter · v1

Entrega del 2026-10-01 para Windows y Android; no implementa widgets. Epic Board, tablero **My autofinance**, confirma MA-TSK-019 `done` y la discusión humana «Propuesta visual aceptada: http://localhost:4310/mockups/autofinance-ma-tsk-019-v1.html». La copia retenida es [mockup-final.html](mockup-final.html), commit `711843d`. Las menciones de aprobación pendiente en documentos anteriores describen su estado histórico y quedan superadas por esta aceptación.

## Uso y autoridad

Leer esta entrega junto con [navegación](mapa-navegacion.md), [flujos](flujos-criticos.md), [sistema visual](sistema-visual.md) y [wireframes](wireframes.html). EP-001 prevalece en reglas financieras: [especificación](../ep-001/especificacion.md), [CSV](../ep-001/contrato-csv.md) y [casos](../ep-001/casos-referencia.md). El mockup aceptado fija identidad, cinco destinos y equivalencia tabla/tarjeta. Esta entrega concreta medidas, estados y recorridos omitidos en el prototipo, siguiendo esas fuentes; no convierte sus simulaciones en servicios reales.

No copiar literalmente las simplificaciones del CSS o de los manejadores del prototipo. Aplicar las medidas de este documento y del sistema visual: título 24, barra lateral 200/216 según ancho y cuerpo mínimo 14. El panel lateral opcional queda descartado en v1: todos los detalles usan rutas secundarias. Android anual usa selector de mes y tarjetas con total anual más sección desplegable «Los doce meses». No hay decisiones pendientes de navegación, color, densidad, formularios o confirmación para los implementadores. XLS permanece fuera de esta entrega hasta EP-014; mostrar «Openbank XLS: pendiente» sin acción de importación habilitada.

## Rutas y retorno

Los nombres siguientes son estables, independientes de la biblioteca de enrutamiento. `a` es año de cuatro cifras, `m` mes 01–12, `rama` ID estable o `sin-clasificar`; nunca usar nombre visible como ID. `alcance` es `directo` o `rama`; por defecto `rama` en agregados. `origen` es un contexto interno, no una URL arbitraria. La creación usa `nuevo`/`nueva` y la edición un ID existente.

| Ruta | Contenido y entrada | Periodo / retorno |
|---|---|---|
| `/estado?a&m` | Estado; apertura y destino Estado | Mes de trabajo |
| `/patrimonio?a&m` | Foto y fichas; destino Patrimonio | Mes de trabajo |
| `/presupuesto?a` | Matriz; destino Presupuesto | Año y mes enfocado |
| `/real?a` | Matriz; destino Real | Año y mes enfocado |
| `/indicadores?a&m` | Colchón; destino Indicadores | Mes y presupuesto del mismo año |
| `/movimientos?a&m&rama&alcance&origen` | Lista desde real directo/agregado | Volver a cifra y filtros |
| `/movimientos/nuevo?origen`, `/movimientos/:id?origen` | Captura / detalle con botón Editar | Guardar/cancelar al origen |
| `/presupuesto/partidas?a&m&rama&alcance&origen` | Lista desde previsto | Volver a celda |
| `/presupuesto/partidas/nueva?origen`, `/presupuesto/partidas/:id?origen` | Captura / detalle con Editar | Guardar/cancelar al origen |
| `/presupuesto/propuesta?a&origen` | Preparar año siguiente | Cancelar al año fuente; guardar al año destino |
| `/patrimonio/foto?a&m&origen` | Foto desde Patrimonio / ausencia de indicador | Mismo mes y destino de origen |
| `/patrimonio/fichas?origen`, `/patrimonio/fichas/nueva?origen`, `/patrimonio/fichas/:id?origen` | Lista / alta / detalle y edición | Retorno a Gestión o foto |
| `/categorias?origen`, `/categorias/nueva?origen`, `/categorias/:id?origen` | Árbol / alta / detalle y edición | Retorno a Gestión o selector |
| `/importar/csv?origen`, `/importar/csv/revision?origen` | Archivo / revisión y resultado del lote | Cambiar archivo o volver al origen |
| `/drive?origen` | Copia manual | Volver al origen sin consultas automáticas |

Gestión es un menú del encabezado, disponible en los cinco destinos, en este orden: Importar CSV, Categorías, Fichas, Copia en Drive. No sustituye una pestaña ni añade sexto destino. Cada secundaria tiene botón «Volver a [destino, periodo]». El contexto conserva destino, año, mes, rama, alcance, filtros, ramas abiertas, posición de desplazamiento y control con foco. Un detalle encadenado apila su contexto inmediato; las pestañas no forman pila de retorno.

Primer inicio: Estado con mes actual Europe/Madrid. Seleccionar año mantiene mes; al no haber mes recordado en ese año usar enero. Cambiar pestaña conserva periodo. Cambiar tamaño mantiene ruta, entradas y selección. Parámetro inválido o entidad inexistente muestra «No se pudo abrir este detalle», con «Volver al origen» (Estado del mes actual si falta origen); no escribe ni presenta ceros ficticios.

Guardar confirma persistencia antes de anunciar éxito y restaura origen y foco; si se cambia fecha fuera del mes, indicar «Movimiento guardado en [mes/año]» con acción «Ver mes». Cancelar descarta borrador. Salir con cambios mediante Volver, pestaña, cierre o Atrás de Android abre «Hay cambios sin guardar» con «Seguir editando» (predeterminado) y «Descartar cambios». Esc/cierre cancela. En importación se descartan asignaciones no confirmadas; durante sustitución de base no se admite salir hasta resultado seguro.

## Medidas y componentes obligatorios

Unidades lógicas Flutter; alturas mínimas crecen al ampliar texto. Sin descargas de fuentes: Segoe UI Windows y Roboto Android. Escala de espacio 4/8/12/16/24/32/48; radio control 8, tarjeta/diálogo 12; borde 1. Aplicar los valores de color y las etiquetas de diferencia de [sistema visual §3](sistema-visual.md#3-tipografía-importes-y-color), también en errores y alto contraste.

| Ancho disponible | Composición fijada |
|---|---|
| 320–599 | Una columna, margen 16, separación 12; barra inferior de cinco destinos, altura mínima 64 más área segura; etiquetas siempre visibles, crece para dos líneas |
| 600–839 | Margen 24, contenido centrado máximo 720; dos columnas de tarjetas solo con ancho mínimo 280 cada una; formularios a una columna |
| 840–1199 | Lateral 200, margen 24; tablas compactas |
| ≥1200 | Lateral 216, margen 32; contenido máximo 1440 centrado; tablas compactas |

En Windows estrecho se usa también la composición móvil. En Android ancho se conserva objetivo táctil 48×48 aunque haya tablas. Solo matrices anuales admiten scroll horizontal interior. No cortar signo, céntimos, errores ni rutas; envolver y crecer antes de truncar. No fijar alturas máximas a filas/tarjetas. Texto 200 % y ancho 320 deben seguir siendo operables.

| Componente lógico | Dimensiones y contenido | Estados / interacción |
|---|---|---|
| Shell | Encabezado título 24/600, periodo y Gestión; controles envuelven con separación 12 | Destino actual con etiqueta y marca; navegación accesible siempre |
| Tabla financiera | Texto 14; fila mínima 40; padding celda 10; columna categoría mínima 180, sangría 16 por nivel; columna monetaria mínima 120 | Cabecera y categoría fijas en matriz; cifras son acciones separadas, no fila con destinos ambiguos |
| Tarjeta de rama | Padding 16, separación 12; ruta 16/600, cifras 16; metadatos 14 | Ruta completa y alcance visible; pares etiquetados, sin cifras ocultas por sangría |
| Resumen | Padding 16; título 16, cifra 20/600, explicación 14 | Valor, cero, sin presupuesto, sin dato con motivo; jamás intercambiables |
| Campo | Etiqueta 16 persistente, ayuda/error 14, separación 8; PC altura mínima 40, Android 48 | Vacío, válido, inválido, bloqueado durante guardado; conservar entrada tras error |
| Botón | PC mínimo 40 de alto; Android/tacto 48×48; separación 8 | Normal, foco, pulsado, deshabilitado con causa visible; primario blanco sobre action |
| Diálogo de confirmación | PC ancho máximo 560, margen exterior 16, padding 24; móvil ancho disponible menos 32 y padding 16 | Scroll vertical, acciones visibles al desplazarse; Cancelar primero, confirmación verbal segunda |
| Editor secundario | PC contenido máximo 760, padding 24; móvil una columna con margen 16 | Ruta propia con título, ayuda, campos, Cancelar y Guardar; sin panel lateral |
| Aviso/progreso | Padding 16, icono 24, texto y acción; región semántica de estado | Error con causa y Reintentar, progreso con fase; éxito solo confirmado |

Tablas anuales: columna categoría 180 mínimo, doce columnas monetarias 120 mínimo, total anual 140 mínimo. Scroll enfocable con etiquetas y cabeceras persistentes. Pie de totales después de ramas; no sumar filas padre e hijas. En móvil cada tarjeta muestra año, total anual, mes enfocado y acción; desplegable muestra los doce meses en orden enero–diciembre. Patrimonio usa doce accesos mensuales con estado de foto, sin columna de total anual.

## Contenido por pantalla y correspondencia financiera

| Pantalla | Orden fijo / acciones | Fuente EP-001 y evidencia |
|---|---|---|
| Estado | Título/periodo, Añadir movimiento, resumen previsto/real/diferencia, árbol: rama → previsto agregado → real directo → real agregado → diferencia. Diferencia abre elección «Ver movimientos reales» / «Ver partidas presupuestadas» | §2, §3, §5.1; casos B,C,J,K. Total solo raíces + Sin clasificar; padre presupuestado no reparte a hijos |
| Patrimonio | Título/mes, referencia día 1, Registrar/editar foto, grupos cuentas/carteras por liquidez y deudas, líquidos/activos/deudas/neto, accesos a doce fotos | §4, §5.2; D. Incompleta: pendientes y sin subtotales numéricos; cero registrado sí completa |
| Presupuesto | Título/año, Crear partida, Preparar año siguiente, matriz y totales | §3, §5.3; E,H. Ausencia «sin presupuesto»; cero «0,00 € (registrado)»; sin cuenta |
| Real | Título/año, Añadir movimiento, matriz incluyendo Sin clasificar y totales | §2, §5.4; F,J,K. Fecha de valor determina mes; vacío cero; ahorro y transferencias por signo |
| Indicadores | Título/periodo, tarjeta «Colchón de emergencia», resultado en meses, fórmula, líquidos, ingresos anuales y /12, motivo y acción si falta dato | §6–6.1; G. Solo colchon_emergencia v1; motivos en orden foto_ausente, foto_incompleta, ingresos_incompletos, ingresos_nulos, ingresos_negativos |
| Movimientos | Periodo/rama/alcance, subtotal firmado, lista, Añadir movimiento, detalle completo | §2, §5.1/5.4; B,F,J,K. Dos Café son registros separados; Sin clasificar no es categoría |
| Partidas/propuesta | Lista por mes/rama; propuesta por raíz y doce meses, real fuente, importe editable, revisión y desglose | §3; H. Suma algebraica antes de redondear magnitud a decena; cero explícito; excluir padre al desglosar |
| Foto/fichas | Fecha día 1 fija, fichas vigentes con campos; gestión de tipo, liquidez y vigencia | §4; D. Magnitudes no negativas; alta/baja inclusivas; ninguna foto calculada desde reales |
| Categorías | Árbol hasta nivel 3; alta/edición; ingreso solo en raíz, heredado | §2–3; J. No cuarto nivel ni hijo sin padre |
| CSV/revisión | Archivo, conteos, filas, referencias, errores, solapamientos, confirmación y resultado | §7 y contrato CSV completo; A. Atomicidad, huella de bytes, presupuesto invierte signo |
| Drive | Versión/fecha remota conocida, cambios locales, última operación, Subir copia, Descargar última copia | §7.1; I. Divergencia detenida, respaldo y validación antes de sustituir; ninguna fusión |

Todos los importes son céntimos internos y formato es-ES EUR con dos decimales; positivos de flujo con +, negativos con −. Fotos son magnitudes sin +. Diferencia positiva «A favor», negativa «En contra», cero «Sin diferencia». No colorear una salida ordinaria como error. Listas reales PC: fecha, concepto, cuenta, categoría, importe y Abrir; móvil una tarjeta por registro con los mismos campos. Discrecionalidad se muestra en detalle, sin filtro v1. Partidas: mes, ruta, importe, Abrir; conservar metadatos históricos aunque no afecten cálculo.

## Formularios y decisiones de interacción

Orden de campos también es orden de foco. No añadir acciones destructivas ni vinculación automática de transferencias fuera del alcance funcional.

| Formulario | Campos en orden / validación / salida |
|---|---|
| Movimiento | Fecha de valor, concepto, importe firmado, cuenta, categoría opcional, Discrecionalidad opcional. Fecha calendario válida, concepto no vacío, importe no cero con hasta dos decimales, cuenta obligatoria. Selector permite «Dejar sin clasificar». Ayuda de signo visible; aceptar coma o punto sin separadores de miles y − o -. Guardar persiste sin cambiar foto |
| Partida | Año/mes, categoría obligatoria, importe firmado (cero válido). Sin cuenta. Conflicto muestra mes y ambas rutas, conserva borrador y partidas previas; resolver explícitamente el padre en su lista antes de reintentar |
| Propuesta | PC tabla raíz/mes/real fuente/propuesto/revisión/Desglosar; móvil tarjeta por raíz, total anual y doce meses editables desplegables. Valores atípicos llevan «Revisar signo» y casilla «He revisado los signos señalados» obligatoria si hay avisos. Desglose retira padre en borrador y exige mismo total o nueva edición explícita. Antes de sustituir: lista mes/ruta/importe anterior/nuevo y «Cancelar» / «Sustituir partidas». Sin partidas existentes basta «Guardar propuesta». Guardar vuelve al año propuesto |
| Foto | Referencia fija día 1; nombre/tipo/liquidez y valor por ficha vigente. Vacío = pendiente, 0 = registrado; negativo inválido. Guardar parcial permitido, aviso «Foto incompleta» y pendientes; sin arrastrar valores anteriores |
| Ficha | Nombre, tipo cuenta/deuda/cartera, liquidez líquida/media/no líquida solo para activo, mes de alta, mes de baja opcional. Nombre obligatorio; baja no anterior al alta. Baja conserva histórico; selector de cuenta de movimiento solo ofrece cuentas |
| Categoría | Nombre, padre opcional con ruta, marca Ingreso sí/no solo si raíz. Bloquear nivel 4; hijo muestra marca heredada de solo lectura. Guardar desde selector regresa con nodo nuevo seleccionado; cancelar conserva selección previa |

Foco al primer campo inválido al Guardar; error junto al campo y anunciado. Deshabilitar solo acciones incompatibles con escritura en curso. No mostrar éxito antes de respuesta de almacenamiento. Confirmaciones: foco inicial en título, opción conservadora predeterminada, Tab contenido dentro del diálogo, Esc/Atrás cancela, retorno al disparador. Expandir rama conserva foco y anuncia expansión. Botones/enlaces con nombre que incluya tipo de cifra, rama, alcance y periodo; icono nunca es el único nombre. Foco 2 con separación 2; alto contraste conserva etiquetas y bordes del sistema; reducir movimiento elimina transiciones prescindibles.

## Estados de carga, importación y Drive

En cada ruta: cargando (fase sin ceros ficticios), contenido, vacío válido, error de lectura con causa y Reintentar. Error de escritura conserva borrador; repetir no duplica operación. En Estado/Real vacío es cero, en Presupuesto ausencia es sin presupuesto, en Patrimonio/Indicadores ausencia es sin dato. Los textos concretos de [flujos críticos](flujos-criticos.md) son obligatorios.

CSV: seleccionar archivo → leyendo → revisión → confirmando → importado/ya importado/error. PC revisión usa tabla desplazable con ordinal, tipo, fecha, ruta/cuenta resueltas, importe CSV e interno; móvil tarjeta por fila con todos esos campos. Antes: conteo por tipo y totales antes/después de inversión, referencias pendientes, errores fila/campo/motivo. Referencia desconocida ofrece Vincular existente o Crear; raíz nueva exige marca ingreso. Asignar una referencia aplica a todas sus filas. No crear entidades durante previsualización. «Confirmar importación» bloqueado mientras haya errores o referencias pendientes. Solapamientos de reales entre archivos requieren «He revisado los posibles duplicados» antes de confirmar; no eliminan filas. Conflictos de presupuesto siguen siendo errores bloqueantes. Confirmación revalida contra base actual; fallo revierte lote y referencias. Repetición exacta: «Este archivo ya se importó. 0 altas.». Éxito muestra altas y enlaces a Estado/Presupuesto/Real del periodo; Volver conserva origen.

Drive en reposo no accede a red; muestra desconocida si no hay versión recordada. Subir: comprobando versión → subiendo → éxito o conflicto/error. Versión desconocida con remota existente o cambio remoto bloquea publicación y muestra versiones, «Conservar datos locales» / «Descargar última copia». Descargar: comprobando versión → confirmación si hay cambios locales → descargando → validando → creando respaldo → sustituyendo/abriendo → éxito. Confirmación muestra versión/fecha, pérdida de cambios de base activa y respaldo recuperable; botones «Cancelar» / «Descargar y sustituir». Bloquear ambos botones durante operación, mostrar fase, sin porcentaje inventado. Sin remota: aviso y acción Subir copia; no sustituir. Error de autenticación/conexión/validación/respaldo/apertura conserva o restaura base previa, muestra causa y reintento manual. Respuesta de subida perdida dice «No se pudo confirmar la subida»; nuevo intento comprueba versión. Éxito descarga identifica respaldo recuperable. No prometer restauración UI adicional ni sincronización en segundo plano.

## Criterios de implementación y verificación

La aprobación visual está satisfecha; EP-003 puede preparar SQLite/enrutamiento/servicios. Las épicas funcionales implementan estas pantallas con sus propias pruebas. No usar servicios simulados del prototipo como evidencia de persistencia o seguridad de Drive. [Verificación integral](verificacion-integral.md) conserva pendientes reales de teclado, layout, lector y dispositivo físico; la aprobación humana no acredita esas pruebas técnicas.

| Prueba de aceptación futura | Resultado verificable en PC y Android |
|---|---|
| Shell y retorno | Cinco destinos, Gestión desde todos, cambio de periodo y detalle/guardar/cancelar preservan origen; Atrás y borrador obedecen confirmación |
| Medidas | 320×800, 360×800, 412×915, 1024×768, 1440×900; límite 839/840 y 1199/1200; texto 200 %. Tabla/tarjeta según ancho, controles 48 en tacto, sin recorte ni scroll global horizontal |
| Estado/Real | Enero real +1.229,75 €, previsto +1.100,00 €, diferencia +129,75 €; febrero real +1.099,90 €, diferencia −0,10 €; anual real +2.329,65 €. Dos Café −10,00 € cada uno, no deduplicados |
| Presupuesto/propuesta | Anual +13.200,00 €; propuesta Alimentación enero −360,00 €, febrero −430,00 €, marzo cero; conflicto padre/hijo bloquea; cancelación y sustitución explícitas |
| Foto/indicador | Enero neto 14.000,00 €, colchón 3,00 meses; febrero ausente/parcial sin dato; completar con ahorro cero produce neto 11.900,00 € y 2,07 meses; corrección neto 12.000,00 €. Cinco motivos de indicador en orden |
| CSV | Ejemplo 48 partidas y 10 reales; repetido 0 altas; errores/referencias bloquean; solapamiento revisado; fallo no deja entidades parciales |
| Drive | Caso I entre instalaciones: divergencia conserva ambas bases, cancelación local intacta, validación/respaldo/apertura fallidos recuperan base anterior; cero accesos al entrar/salir |
| Accesibilidad | Tab/Mayús+Tab, Intro/Espacio, Esc y Atrás; foco contenido en modal y retorno; lector anuncia signos/periodo/alcance/errores; alto contraste y texto ampliado |

Verificación de esta entrega: ejecutar los tres comprobadores existentes y `git diff --check`; revisar enlaces y cobertura de todas las rutas, medidas, formularios y reglas de esta matriz. No existe proyecto Flutter en el checkout: no se ejecutan `flutter analyze`, pruebas de widgets ni Android físico. Los resultados de esta revisión se registran en [verificacion-entrega.md](verificacion-entrega.md).
