# MA-TSK-206 · Identidad visual y sistema de diseño

Propuesta v1, **2026-10-12**, para Windows y Android. Ticket consultado en
Epic Board, tablero **My autofinance**, MA-EPIC-203. Entrega de T03 independiente;
alimenta el prototipo T04 (MA-TSK-207) y el kit T05 (MA-TSK-208). **Pendiente de
aprobación del prototipo global**. No activa tema, widgets, rutas ni pantallas.
La aprobación T04 sustituirá apariencia/navegación EP-002; EP-001 conserva
su contrato financiero. No presupone aprobados los ejemplos de esta guía.

## Artefactos para revisar y reutilizar

- [Galería local](identidad/galeria.html): resumen, categoría, movimiento,
  cuenta, formulario, avisos y tabla avanzada, además de tres gráficos.
  Abrir en navegador; todos los recursos están junto al HTML. Sus controles
  revisan estados sintéticos y validan un formulario sin persistencia.
- [Tokens JSON](identidad/tokens-visuales.json): fuente normativa de nombres/valores;
  [CSS generado](identidad/tokens.css) sirve al prototipo. Regenerar con
  `node docs/ep-026/identidad/generar-tokens.mjs`; `--check` detecta divergencias.
- [Verificación y capturas](verificacion-identidad.md): resultados observados
  y límites. Son capturas del HTML renderizado, no de la app nativa.
- [Navegación T02](navegacion-jerarquia.md) y
  [contrato shell/contexto](contrato-shell-contexto.md): conservan propiedad de
  rutas, periodos, slots y API del kit. Esta guía no los redefine.

## Dirección: calma, foco en cifras y contexto explícito

Fondo marfil suave, superficies blancas y acento petróleo. Texto oscuro;
una cifra principal por tarjeta, etiqueta antes del número y periodo junto
al título. El nombre `autofinance` es texto tipográfico, no un logo importado.
La voz es breve y concreta: «Foto del 1 de enero», «Sin presupuesto»,
«No se ha subido tu copia local». Ningún mensaje juzga la salud financiera.

La entrada sigue la jerarquía T02: resultados real/presupuesto/diferencia,
foto patrimonial separada y pendientes. No titula el resultado «saldo
disponible». Evitar matrices como composición principal: usar resumen,
comparación y acciones claras, con **Ver detalle** visible hacia todas las
filas/celdas. No esconder controles o datos completos tras el resumen.

Identidad propia: petróleo para acción/real, violeta para presupuesto,
marfil para fondo; tipografía y componentes comunes a ambas plataformas.
La inspiración se limita a lectura progresiva, agrupación y separación
entre resumen y actividad. No importar método YNAB, score Fintonic, objetivos,
umbrales, recomendaciones, conexión bancaria ni sincronización automática.

## Tokens de aplicación

Valores completos y pares de contraste en el JSON. Unidades: píxeles lógicos
Flutter/dp, rem escalables en la galería. Solo tema claro.

| Grupo | Tokens principales | Aplicación |
| --- | --- | --- |
| Superficie | canvas `#F6F5F1`, surface `#FFFFFF`, surfaceSubtle `#EFEEE8` | Fondo, tarjeta, cabecera de tabla. |
| Texto | text `#202E32`, muted `#526267` | Contenido y metadatos; secundario legible, nunca gris casi invisible. |
| Acción | accent `#14645F`, hover `#104E4A`, tint `#E5F2EE`, onAccent blanco | Primario, enlaces subrayados, selección con etiqueta. |
| Favorable | `#21613D` / `#EAF3EB` | Diferencia favorable, etiqueta y flecha ↑. |
| Desfavorable | `#923B32` / `#FBEFEA` | Diferencia desfavorable, etiqueta y flecha ↓. |
| Atención | `#775015` / `#FFF4DA` | Pendientes/revisión, motivo y acción. |
| Error | `#9A3038` / `#FCEDEF` | Validación fallida/operación fallida; × y mensaje. |
| Límites | border `#D5DDDC`, controlBorder `#738481`, focus `#284DB1` | Borde ornamental de tarjeta; borde funcional de campo/eje; foco. |
| Series | real petróleo, budget `#65569C`, asset `#355F91`, debt `#923B32` | Series siempre nombradas; color no equivale a bondad del importe. |
| Espaciado | 4 / 8 / 12 / 16 / 24 / 32 / 48 | Icono-etiqueta 8, controles 12, tarjeta 24, secciones 48. |
| Radio y borde | control 8, card 16, badge 6; borde 1 | Bordes moderados, sin sombras pesadas ni píldoras en todas las filas. |
| Movimiento | 120 ms; reducción 0 | Cambio de selección discreto, sin contadores animados ni carga de gráficos decorativa. |

Texto normal exige 4,5:1 y foco, controles y marcas gráficas 3:1 contra el
fondo. El borde ornamental no sustituye el borde de control. El comprobador
mide todos los pares declarados; los colores nuevos requieren volver a medir.
La selección añade fondo, indicador y `selected`/`aria-current`; los errores
añaden texto y semántica. En alto contraste se respeta el foco y la selección
del sistema; no forzar colores que eliminen sus señales.

## Tipografía y recursos sin red

**Roboto regular 400, medium 500 y bold 700**, empaquetadas en
`identidad/assets/`, sin modificación, desde `material_fonts` del SDK Flutter
3.47.0 local. La [licencia Apache 2.0](identidad/assets/LICENSE-Roboto.txt)
acompaña los archivos; referencia histórica upstream:
[Roboto 2, Apache 2.0](https://github.com/googlefonts/roboto-2).
El manifiesto con hashes en [assets](identidad/assets/README.md) permite verificar
los bytes de esta entrega. No se distribuye una fuente propietaria del SO ni
se usa Google Fonts como servicio. La galería carga las TTF locales incluso
sin conexión; T05 deberá declararlas como assets/font family en `pubspec.yaml`
con los mismos pesos y conservar licencia/créditos. No modificar ahora SDK
ni pubspec/lockfile para anticipar T05.

| Rol | Tamaño / peso / interlineado | Uso |
| --- | --- | --- |
| Cifra principal | 36 / 700 / 1,15 | Resultado principal, sin abreviar EUR; a ancho estrecho 32. |
| Título de página | 28 / 700 / 1,25 | Vista y contexto. |
| Sección | 20 / 700 / 1,35 | Agrupación independiente. |
| Cuerpo/control | 16 / 400 / 1,5 | Texto principal y formularios. |
| Etiqueta/metadato | 14 / 500 o 400 / 1,5 | Periodo, origen, estado. |
| Tabla PC | 14 / 400 / 1,5 | Celdas; total 700. |

Sin estilos inferiores a 14. Cifras tabulares (`tnum`), alineadas a derecha
en tablas y filas numéricas; comprobar soporte real de la fuente. El símbolo
€ puede bajar un grado en la cifra protagonista, nunca los céntimos. Con
texto al 200 %, pasar a una columna y reducir el rol de cifra hasta cuerpo
ampliado si es necesario; no disminuir el texto del sistema ni cortar signos.
El número permanece entero; moneda puede ocupar la línea siguiente.

**Iconos originales de contorno**, cuadrícula 24×24, trazo 1,75, extremos y
uniones redondeados, sin emojis como sistema de iconos. La galería incluye
categoría (cuatro celdas), movimiento (recibo) y cuenta (edificio) dibujados
desde geometría elemental, sin copiar assets externos. T05 extenderá el mismo
lenguaje: casa/Inicio, calendario/Presupuesto, recibo/Movimientos,
edificio/Patrimonio, barras/Análisis, puntos/Más, engranaje/Gestión,
flecha de entrada/Importar, flechas verticales/Subir o Descargar copia,
lápiz/Editar, marca/Confirmar, ×/Cerrar. Drive se nombra con texto; sin logo.
Entregar SVG locales o CustomPainter/Path originales; los contornos no se
obtienen de iconos de terceros. Rotular iconos accionables con tooltip y
semántica; iconos junto a texto son decorativos y no duplican anuncios.
No usar IconData nuevo hasta que el kit T05 defina su catálogo empaquetado.

## Reglas numéricas y estados financieros

El [contrato EP-001](../ep-001/especificacion.md#5-vistas-de-la-aplicación)
y sus [casos](../ep-001/casos-referencia.md) son las fuentes de cifras. Esta
guía presenta resultados de sus propietarios; no crea cálculos de dominio.

- EUR `es-ES`, separador de miles y coma; siempre dos decimales. Flujos y
  diferencias: `+1.229,75 €`, `−350,25 €`, `0,00 €`. Menos tipográfico U+2212;
  entrada admite `-`. No mostrar `−0,00`, abreviar miles ni ocultar céntimos.
- Foto de activo o deuda: magnitud `5.000,00 €` bajo su tipo. Deuda separada
  y explicación del neto `activos − deudas`. Patrimonio neto puede ser negativo;
  mostrar su signo, sin convertirlo por sí solo en error de datos.
- Signo de movimiento describe entrada/salida; no cambia la marca de ingreso
  heredada de la raíz. Salidas normales, ahorro y transferencias tienen texto
  neutro y conservan su signo. No añadir contrapartidas ni saldo calculado.
- Para una comparación presupuestada, diferencia `real − presupuesto`
  positiva: **↑ Favorable**; negativa: **↓ Desfavorable**; cero: **Igual**.
  Esta etiqueta describe la comparación algebraica de EP-001/EP-002, no una
  recomendación sobre ahorro. Sin partida: **Sin presupuesto**, mostrar la
  diferencia calculada por dominio contra cero aritmético sin evaluación
  favorable/desfavorable engañosa. No introducir tolerancias o umbrales.
- Cero registrado `0,00 €` es dato. Foto ausente/incompleta: **Sin dato** con
  motivo/fichas pendientes; no subtotales parciales, arrastre o interpolación.
  Partida ausente: **Sin presupuesto**; partida explícita cero: `0,00 €`.
  Mes sin movimientos: real `0,00 €`. Carga/fallo no se presentan como cero.
- Colchón existente: `3,00 meses`; cero válido `0,00 meses`. Denominador cero,
  negativo o entradas incompletas: motivo **Sin dato** del dominio, nunca
  infinito, porcentaje inventado, objetivo ni semáforo financiero nuevo.
- Lectura accesible: «Real agregado, menos trescientos cincuenta euros con
  veinticinco céntimos, Alimentación, enero de 2026». Anunciar literalmente
  ausencia/motivo; gráfico y tabla no anuncian dos veces el mismo contenido.

## Componentes, estados y ejemplos de la galería

| Componente | Anatomía y variante PC / Android |
| --- | --- |
| Resumen | Etiqueta, cifra, periodo/origen y enlace de detalle. 3 tarjetas en PC; una por fila en Android. Real y presupuesto separados de foto y pendientes. |
| Categoría | Icono, nombre, ruta hasta 3 niveles, tipo Directo/Rama completa, líneas real/presupuesto/diferencia. PC puede usar fila; Android tarjeta; UUID del dominio, no nombre como identidad. |
| Movimiento | Concepto, importe firmado, cuenta, fecha de valor, ruta o Sin clasificar; discrecionalidad en detalle. Salida neutra. Selección visible con checkbox/estado; lote conserva filtros. |
| Cuenta/ficha | Nombre, tipo/liquidez, valor manual y fecha día 1; Registrado/Pendiente. Deuda como magnitud en su grupo; no saldo actualizado por movimiento. |
| Formulario | Etiqueta persistente, ayuda/unidad, obligatoriedad, campo, error asociado y acciones. Una columna ≤560. Guardar/Cancelar claros; no placeholders como etiqueta. |
| Aviso | Icono/etiqueta, causa concreta, conservación de datos y recuperación disponible. Carga, vacío, sin dato, pendiente, éxito, divergencia y fallo son estados diferentes. |
| Tabla avanzada | Caption con periodo/EUR, cabeceras y primera columna fijas, cifras alineadas, total explícito, desplazamiento interno. Expansión hasta 3 niveles, filtros visibles, acceso a origen; matrices con 12 meses/total de flujos completos. |

Estado normal: superficie blanca. Hover: acento suave. Foco: anillo 3 px con
separación 3. Pulsado: mismo acento y feedback breve; seleccionado persiste
con texto/indicador. Deshabilitado: etiqueta/motivo legible, no solo opacidad.
Cargando: fase y región de estado, impedir duplicar envío. Vacío: alcance y
acción posible. Error de campo: mensaje asociado + borde, foco al campo
inválido después de intentar guardar, borrador conservado. Éxito: estado
anunciado, sin mover foco. Borrado/sustitución: confirmación con consecuencias,
Cancelar visible y retorno al origen. No usar error para dato ausente normal.
Sin conexión/Drive divergente no dispara acciones automáticas ni anuncia éxito.
La galería valida solo su importe sintético; validaciones reales pertenecen
a los módulos existentes, incluidos fechas/cuentas/categorías/solapamientos.

PC: margen 32, máximo 1200, tarjetas con padding 24 y filas ≥44. Android
320–599: margen/padding 16, separación 16, una columna; objetivos ≥48×48,
separación ≥8 y área segura. Entre 600–839 se usa una/dos columnas solo si
cabe todo; desde 840 el shell T02 puede usar lateral, sin comprimir tarjetas.
La galería no implementa ese shell. Teclado: Tab lógico, foco visible, Enter/
Espacio en controles, Escape/cancelación en diálogos que T04 ejemplificará;
la navegación existente conserva Back y protección de borradores. Texto 200 %
y ventana estrecha: altura fluida, etiquetas envueltas, sin overflow de página;
únicamente la tabla íntegra admite scroll horizontal. TalkBack/Narrador se
verificarán en implementación nativa; el HTML solo aporta semántica inicial.

## Gráficos como representación, sin fórmulas nuevas

Todo gráfico muestra título, serie/leyenda, periodo, ejes y unidad. Acompañar
con tabla o lista textual **visible**, orden y valores exactos, no solo tooltip.
Si no cabe una escala legible (Android/200 %), ofrecer la alternativa textual
sin perder cifras; T04 decidirá la composición global. Los ejemplos gráficos
son representaciones de fixtures, no servicios para T05 ni cálculos financieros.

**Barras comparativas firmadas.** Real petróleo y presupuesto violeta, filas
nombradas. Escala lineal compartida con cero explícito; negativos a izquierda/
abajo y positivos derecha/arriba; nunca valores absolutos para comparar flujos.
Dominio de ejes incluye cero y los extremos de ambas series; si ambas son cero,
usar un rango visual simétrico y marcas en cero (no un porcentaje). Etiquetas
EUR exactas en alternativa; presupuesto ausente no dibuja una barra cero.
La galería usa rango −500/+500 para sus cuatro fixtures. T05 elegirá rango
por los valores entregados y reescalará también para importes grandes,
sin truncar barras ni sumar las cifras de distintas ramas otra vez.

**Series temporales.** Meses en X; EUR firmado en Y para flujos/neto, y
«meses» para colchón. Real/presupuesto mantienen leyenda y un patrón de línea
distinto (real continuo, presupuesto discontinuo). Una serie no usa dos ejes
con escalas engañosas. Cero explícito es muestra a altura cero. Solo unir
puntos adyacentes calculables; no cruzar fotos incompletas/ausentes ni motivos
de ausencia del indicador. Galería: enero 14.000, febrero/marzo sin dato,
abril 14.500 sintético; dos puntos aislados. No sumar fotos como total anual.
Si solo hay un dato, mostrar punto y valor; si ninguno, motivo y tabla de
meses sin dato. Si el rango queda constante, ampliar escala visual, sin
inventar una variación; tooltips accesibles por foco solo como complemento.

**Distribución patrimonial.** Preferir barras horizontales rotuladas por activo
con valor y total. Solo con foto completa, todas las magnitudes finitas/no
negativas, suma coherente y total estrictamente positivo. Cada ficha vigente
aparece una vez; deuda queda en bloque separado, nunca dentro del denominador
ni en un pastel junto al neto. Ceros individuales válidos: etiqueta y longitud
cero. Total activos cero: mostrar todas las cifras cero y «Distribución no
representable», sin dividir. Foto incompleta: Sin dato y pendientes, ningún
subtotal/gráfico parcial. Dato inválido: aviso de origen, sin gráfico.
La longitud relativa es codificación visual, no indicador. Nunca pastel de
valores negativos, porcentajes con denominador cero, acumulados que cancelen
deuda/activos, ni gráfico que sugiera saldo disponible. No son necesarios
pasteles para esta identidad.

## Referencias públicas y evidencia consultada

Consulta **2026-10-12**, páginas públicas, sin login ni revisión autenticada
de las apps. Evidencia limitada a texto y descripciones de imágenes expuestas
por las páginas; no se afirma haber probado aplicaciones de terceros. No se
copian sus activos, logos, tipografía o paleta. El apartado separa observación
de decisión propia; no supone funcionalidades para Autofinance.

| Fuente pública | Evidencia observada | Interpretación aplicada |
| --- | --- | --- |
| [YNAB Features](https://www.ynab.com/features) | Secciones de informes de gasto/patrimonio; descripción pública de imagen Reflect con desglose y bloques. | Cifras y contexto antes del detalle; distintas superficies para flujo y patrimonio. No sus objetivos o método. |
| [The Great YNAB Remodel](https://www.ynab.com/whats-new/the-great-ynab-remodel), publicado 2025-09-15 | Texto describe Home como entrada de alertas/prioridades y Spending como lugar de actividad y registro. | Resumen como entrada y actividad específica, según el mapa propio T02. |
| [Fintonic en Google Play](https://play.google.com/store/apps/details?hl=es&id=com.fintonic) | Ficha pública con capturas listadas y oferta de financiación/FinScore en la descripción. No se ha evaluado esa UI autenticada ni se afirma detalle visual de las capturas. | Limitar inspiración; no trasladar score ni oferta comercial. |
| [Fintonic Control y Alertas](https://www.fintonic.com/es-ES/alertas/) | Texto agrupa cuentas, categorías y avisos concretos; sus automatismos se describen en público. | Agrupar cuenta/categoría y explicar pendientes propios con acciones manuales. |

La portada Fintonic `/es-ES/` devolvió 404 en la consulta; no se utiliza como
evidencia. No inferir paletas/tamaños exactos desde texto. La paleta, retícula,
tokens, ilustraciones geométricas y composición de esta entrega son decisiones
de diseño de Autofinance.

## Traspaso a T04 / T05

T04 usa estos tokens y ejemplos con el catálogo T02 en su prototipo navegable
Windows/Android y obtiene aprobación explícita. Debe cubrir estados reales
de propuestas, importaciones, catálogos, fotos, Drive/recuperación y las
interfaces pendientes EP-022/023/024/025, sin simularlas como entregadas.
T05 materializa tipografía empaquetada, iconos propios, tema, componentes y
gráficos detrás de `lib/ui/autofinance_ui.dart`, según el contrato de shell;
las pantallas reciben cifras/estados/callbacks del propietario, sin importar
app/features/data desde el kit. Estados Favorable/Desfavorable del kit son de
presentación, no nuevo motor. Las pruebas de T05 deben verificar semántica,
texto ampliado, contraste, valores negativos/cero/ausentes y assets sin red.
Ni esta guía ni sus capturas conceden la aprobación o la integración nativa.
