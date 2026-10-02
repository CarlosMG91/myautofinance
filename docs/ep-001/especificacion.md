# EP-001 · Especificación funcional

**Estado:** contrato aprobado por el usuario el 2026-10-01 y entregado en `origin/main`. **Idioma y divisa:** español y EUR. **Zona horaria para el mes actual:** Europe/Madrid.

## 1. Objetivo y límites

Autofinance permite registrar movimientos reales, presupuestos mensuales y fotos patrimoniales; consultar las cuatro vistas de datos y un primer indicador; e intercambiar manualmente una copia completa de la base local entre Windows y Android mediante Google Drive. Es una aplicación para una sola persona. La app funciona sin conexión salvo durante las operaciones explícitas de Drive.

No se migran las fotos patrimoniales antiguas. No se calculan saldos de cuentas a partir de movimientos. No hay posiciones individuales de fondos o acciones, conciliación bancaria automática, sincronización continua, fusión de bases divergentes, cifrado adicional de la copia en Drive ni publicación en tiendas. El XLS concreto de Openbank se especificará en EP-014 con una muestra real; aquí solo se fijan las reglas comunes de importación.

## 2. Glosario y modelo funcional

| Término | Significado |
|---|---|
| Movimiento real | Flujo de dinero fechado, vinculado obligatoriamente a una cuenta; puede quedar pendiente de categorizar. |
| Partida presupuestaria | Importe previsto para un mes y un nodo de categoría; no se vincula a una cuenta. |
| Categoría | Árbol de hasta tres niveles: categoría, subcategoría y subsubcategoría. |
| Categoría de ingreso | Rama raíz marcada explícitamente como ingreso; sus descendientes heredan esta marca. Se usa para calcular ingresos presupuestados del indicador. |
| Foto patrimonial | Valores introducidos manualmente por cuenta, deuda o cartera para el día 1 de un mes. |
| Activo líquido | Cuenta o cartera clasificada como líquida durante el mes consultado; su valor de la foto integra el numerador del colchón. |
| Discrecionalidad | Texto opcional heredado de los datos antiguos. Se conserva, pero la primera versión no filtra informes por él. |

Un importe real positivo representa entrada y uno negativo, salida. Ahorro y transferencias entre cuentas propias se registran como movimientos ordinarios de sus categorías y se suman por su signo; la aplicación no crea ni enlaza una contrapartida de forma automática. Los informes no infieren ingresos por el signo: la condición de ingreso procede de la marca de la categoría raíz. Un movimiento sin categoría figura bajo «Sin clasificar» y permanece en el total general firmado, pero no se atribuye a una categoría de ingreso.

Cada movimiento conserva fecha de valor, concepto, importe EUR con dos decimales, cuenta, categoría opcional y discrecionalidad opcional. La fecha de valor determina el mes de los informes. Dos movimientos legítimos pueden compartir fecha, concepto e importe. Las correcciones no alteran las fotos de saldos.

Cada movimiento categorizado apunta a un solo nodo del árbol, sea raíz, subcategoría o subsubcategoría; no se admite un cuarto nivel ni una subcategoría sin padre. El real directo de un nodo suma únicamente los movimientos asignados a ese nodo. Su real agregado suma ese importe directo y los de todos sus descendientes, una sola vez por movimiento. «Sin clasificar» es un grupo de informe, no una raíz del árbol. La marca de ingreso se define en la raíz y se hereda sin excepciones en la rama: una salida negativa en `Ingresos` sigue perteneciendo a esa rama, y una entrada positiva en `Ahorro` no se convierte en ingreso categorial.

La cuenta de un movimiento real identifica dónde se registró el flujo, incluso si el concepto menciona otra cuenta propia. Si se introducen manualmente las dos piernas de una transferencia, cada una conserva su cuenta, categoría y signo, y ambas participan en los totales firmados; no se compensan ni se excluyen automáticamente. Una transferencia registrada en una sola cuenta aporta solo esa pierna. Discrecionalidad se conserva asociada al movimiento, también al importarlo o editar otros campos, y se muestra en su detalle; no cambia signo, categoría, agregación ni selección de informes.

## 3. Presupuestos

El presupuesto es una entidad distinta del movimiento real. Cada partida tiene mes, categoría e importe EUR con dos decimales; no tiene cuenta. Internamente usa el mismo signo: ingreso previsto positivo y salida prevista negativa. En el CSV histórico, `PRESUPUESTO` usa el signo contrario y se invierte al importar. Para un mismo mes no se admiten partidas simultáneas en un nodo padre y en cualquiera de sus descendientes, tanto al crear como al editar, importar o guardar una propuesta; se rechaza la operación sin alterar las partidas existentes. La restricción se evalúa por mes: en meses distintos pueden usarse niveles diferentes. Sí se pueden presupuestar dos ramas hermanas. Una categoría padre agrega sus movimientos directos y los de sus descendientes; una partida definida en el padre **no se reparte** entre hijos para mostrar comparaciones ficticias.

Al preparar el año siguiente, la aplicación propone para cada mes **ingresos y salidas** reales del mes equivalente del año anterior, agregados por categoría raíz para evitar solapamientos. Redondea la magnitud de cada total a la decena de euros superior o igual y conserva su signo: `+3.021,00 → +3.030,00`; `−350,25 → −360,00`; un múltiplo exacto de diez no cambia. El total se calcula con la suma algebraica de todos los reales de la raíz antes de redondear. En meses sin reales de una raíz activa propone cero explícito. Una raíz de ingreso con total negativo, o una raíz de salida con total positivo, queda marcada para revisión antes de guardar. Cada importe propuesto puede editarse y desglosarse en subcategorías; para guardar el desglose se retira la partida del padre de ese mes. Guardar vuelve a validar la regla padre/descendiente. La propuesta no sustituye partidas ya guardadas sin confirmación.

Un mes sin partida presupuestaria se identifica como «sin presupuesto» en su desglose; no se confunde visualmente con una partida explícita de cero. Para totales aritméticos aporta cero. Los informes muestran también flujos reales sin presupuesto.

## 4. Cuentas y fotos patrimoniales

Cada ficha representa una cuenta corriente, una deuda o una cartera de inversiones. Las cuentas y carteras son activos y tienen una clasificación de liquidez: líquida, media o no líquida. Las deudas son pasivos y no forman parte de los activos líquidos. En la foto del día 1 se registra un valor no negativo por ficha; el patrimonio neto es `activos − deudas`. La app no deriva estos valores de los movimientos ni de cotizaciones externas.

La foto de un mes solo está completa cuando contiene un valor para cada ficha activa en ese mes. Si falta la foto o algún valor, la vista patrimonial y el indicador muestran «sin dato» para ese mes, identificando las fichas pendientes. No se arrastra automáticamente la foto anterior. Editar una foto conserva su fecha de referencia y permite recalcular los resultados del mes.

Cada ficha tiene nombre, tipo y, si es un activo, clasificación de liquidez. Su periodo de vigencia determina los meses en los que se exige su valoración: desde el mes de alta hasta el mes de baja, ambos incluidos. La baja conserva las fotos históricas; una ficha todavía no dada de alta no aparece como pendiente en meses anteriores. Para cada mes y ficha vigente hay como máximo un valor manual. El cero es un valor registrado válido, distinto de un valor ausente. La fecha de referencia de todos los valores de un mes es el día 1 de ese mes, aunque se introduzcan o corrijan más tarde.

Una foto completa muestra cada ficha vigente con su valor, suma las cuentas y carteras como activos, suma las deudas como magnitudes positivas y calcula `patrimonio neto = suma de activos − suma de deudas`. Los activos líquidos suman solo fichas activas clasificadas como líquidas; las de liquidez media o no líquida siguen formando parte de los activos totales. Si falta cualquier valor exigido, no se presenta un patrimonio parcial como total del mes: se muestra «sin dato» junto con la lista de fichas pendientes. Un mes sin fichas vigentes ni valores registrados tampoco se interpreta como patrimonio cero: muestra «sin dato: falta foto patrimonial». Cada mes se consulta de forma independiente, sin copiar valores ni clasificación desde una foto anterior para completar importes ausentes.

La clasificación de liquidez de cuentas y carteras se conserva históricamente por periodos mensuales sin solapes. Cada periodo comienza el día 1 de un mes y termina antes del día 1 del siguiente periodo; el último puede quedar abierto. Todo mes de vigencia del activo debe tener exactamente una clasificación. Cambiar la liquidez desde un mes elegido conserva los meses anteriores; corregir expresamente un periodo histórico recalcula solo los meses afectados, sin modificar sus valores manuales. Las deudas no tienen periodos de liquidez. No se usa la clasificación actual para reinterpretar fotos pasadas ni se rellena una valoración ausente. Decisión de MA-TSK-031, concretada en el [contrato de datos EP-004](../ep-004/modelo-datos.md).

## 5. Contratos de las cinco vistas

Todas las vistas permiten elegir año y, cuando corresponde, mes; al abrir la app se propone el mes actual en Europe/Madrid. Las agregaciones monetarias conservan céntimos y se calculan antes de formatear a dos decimales. La navegación desde una cifra abre los registros que la componen.

| Vista | Entradas | Resultado |
|---|---|---|
| Estado del mes | Movimientos y presupuesto del mes elegido | Real, previsto y diferencia `real − previsto` por categoría, con agregación de descendientes y total firmado. Diferencia positiva es favorable tanto para ingresos como para salidas. |
| Cuentas, deudas e inversiones | Foto completa del día 1 del mes elegido | Valores por ficha, activos, deudas y patrimonio neto. Sin foto completa: «sin dato». |
| Presupuesto anual | Partidas del año elegido | Matriz de doce meses y total anual por rama; sin doble conteo de padre e hijos. |
| Real anual | Movimientos del año elegido | Matriz de doce meses y total anual por rama, incluido «Sin clasificar». |
| Indicadores | Presupuesto anual y foto del mes elegido | Primer indicador: colchón de emergencia; arquitectura abierta a indicadores adicionales sin cambiar los datos básicos. |

Los totales de categorías combinan importes positivos y negativos por suma algebraica. Una cifra de presupuesto en un padre puede compararse con el real agregado de toda su rama; sus hijos solo muestran real y «sin presupuesto» propio. Una partida hija contribuye al total del padre. Las transferencias y el ahorro siguen estas mismas reglas.

### 5.1 Estado del mes

**Entrada y periodo.** Año y mes elegidos; movimientos cuya fecha de valor cae en ese mes y partidas de ese mes, tras normalizar el signo de importación. Se muestran las raíces, los nodos con importe directo y sus antecesores, más «Sin clasificar» si hay movimientos sin categoría. Cada cifra permite abrir los registros directos que la componen; al abrir un agregado se incluyen los registros de sus descendientes una sola vez.

**Columnas y cálculo.** Para cada nodo se muestran previsto agregado, real directo, real agregado y diferencia agregada `real agregado − previsto agregado`. El previsto agregado suma las partidas del nodo y su descendencia; la regla de exclusión padre/descendiente por mes impide que una partida se repita. En un nodo con partida propia, sus hijos muestran «sin presupuesto» propio aunque el padre tenga previsto; no se prorratea la partida. «Sin clasificar» tiene previsto aritmético cero y etiqueta «sin presupuesto». La diferencia conserva el signo y se calcula también cuando falta presupuesto. El total general suma solamente las raíces y «Sin clasificar», nunca una raíz junto a sus descendientes.

**Ausencias.** Un mes sin movimientos tiene real cero; un mes sin partidas tiene previsto cero para los cálculos y se etiqueta «sin presupuesto». La ausencia de datos patrimoniales no afecta a esta vista.

### 5.2 Cuentas, deudas e inversiones

**Entrada y periodo.** Año y mes elegidos; foto manual referida al día 1 y fichas vigentes durante ese mes. La vista presenta un valor por ficha, agrupado por tipo y liquidez. Solo una foto completa permite calcular subtotales. No utiliza movimientos ni presupuestos.

**Subtotales.** `activos = cuentas + carteras`; `deudas = suma de valores positivos de pasivos`; `patrimonio neto = activos − deudas`. Se expone además el subtotal de activos líquidos, sin descontar deuda. Cada ficha participa una vez en su grupo y en los agregados derivados. La vista anual permite navegar entre las doce fotos mensuales; no suma saldos de meses distintos ni presenta un «patrimonio anual» aditivo.

**Ausencias.** Si falta una ficha vigente, se listan las pendientes y los subtotales del mes muestran «sin dato». El valor registrado `0,00` sí completa la ficha. Los meses sin foto no heredan la anterior.

### 5.3 Presupuesto anual

**Entrada y periodo.** Año elegido y sus partidas mensuales. La matriz contiene enero–diciembre, una columna de suma anual y filas por raíz con desglose hasta el nodo presupuestado. Una celda sin partida muestra «sin presupuesto» en el desglose, aunque aporte cero a las sumas.

**Subtotales.** Cada celda agregada suma las partidas directas y descendientes de ese mes. El total anual de una fila suma sus doce celdas; el total mensual suma solo las raíces y el total del año suma los doce totales mensuales. Las filas padre son subtotales de sus hijos cuando el presupuesto está en hojas, o contienen su partida directa cuando se presupuestó el padre; nunca se suman de nuevo al total. No se traslada presupuesto entre meses ni se reparte una partida padre entre hijos.

### 5.4 Real anual

**Entrada y periodo.** Año elegido y movimientos según su fecha de valor. La matriz contiene enero–diciembre, total anual, raíces con su desglose y una fila «Sin clasificar» para movimientos sin categoría.

**Subtotales.** Cada celda agregada suma el real directo del nodo y el de sus descendientes. La columna anual suma las doce celdas de la fila; los totales mensuales y el anual general suman únicamente las raíces más «Sin clasificar». Un mes sin movimientos muestra `0,00`. Ahorro, transferencias y movimientos pendientes de categoría permanecen en el total por su importe firmado.

## 6. Primer indicador: colchón de emergencia

`colchón = activos líquidos de la foto del día 1 del mes / (ingresos presupuestados del año / 12)`.

Los ingresos presupuestados son la suma anual de partidas bajo raíces marcadas como ingreso, después de normalizar el signo del CSV. Se requiere una foto completa del mes y presupuesto de ingresos registrado para cada uno de los doce meses; un cero explícito es válido. Si falta un mes de ingresos, no hay foto completa o el denominador es cero o negativo, se muestra «sin dato» con el motivo. La unidad del resultado es «meses». El cálculo no resta deudas a los activos líquidos.

Cada futuro indicador declarará qué entradas necesita, periodo, unidad, fórmula y motivos de ausencia de dato; la primera versión solo ofrece el colchón.

### 6.1 Contrato extensible de indicadores

Cada indicador tiene un identificador estable, nombre visible, versión de su definición, entradas requeridas, periodo de consulta, unidad, regla de cálculo y estados de ausencia. La vista consulta el catálogo de indicadores y presenta para cada uno un resultado estructurado: `valor` y `unidad` cuando es calculable, o `sin dato` y `motivo` cuando no lo es. Añadir otro indicador incorpora una definición al catálogo y su cálculo; no exige cambiar movimientos, presupuestos ni fotos, ni interpretar el texto ya formateado de otro indicador. Los importes se calculan en céntimos; el resultado se redondea solo para mostrarlo.

| Campo del colchón | Contrato |
|---|---|
| Identificador y versión | `colchon_emergencia`, versión `1`. |
| Periodo | Mes elegido para la foto del día 1 y año de ese mismo mes para los ingresos presupuestados. |
| Entradas | Fichas vigentes, valores de la foto de cada una, clasificación de liquidez y partidas presupuestarias de los doce meses del año bajo raíces de ingreso. |
| Numerador | Suma de los valores de cuentas y carteras vigentes clasificadas como líquidas en la foto completa. No se restan deudas ni se incluyen activos de liquidez media o no líquida. |
| Denominador | Suma firmada de los ingresos presupuestados de los doce meses, dividida entre 12. Se usan importes internos tras invertir el signo del presupuesto CSV. |
| Valor y unidad | `numerador / denominador`, en meses. Se presenta con dos decimales y coma decimal; la precisión interna no se limita a esos dos decimales. |

La completitud del presupuesto de ingresos se comprueba por **mes**, no por tener doce filas ni por el signo de un movimiento: cada uno de los doce meses debe contener al menos una partida explícita bajo una raíz marcada como ingreso. Una partida de `0,00` cuenta como registrada. Pueden existir varias raíces o partidas hermanas de ingreso; se suman una vez según la regla de exclusión de padre y descendiente. Las partidas de otras raíces no completan un mes de ingresos. Si la suma anual firmada es negativa, el denominador también es inválido.

Los motivos son códigos estables acompañados de texto visible. Se evalúan en este orden para que una consulta con varias ausencias tenga un resultado determinista:

| Código | Texto visible | Condición |
|---|---|---|
| `foto_ausente` | «sin dato: falta foto patrimonial» | No hay valores registrados para el mes, o no existe una foto utilizable. No se usa la de otro mes. |
| `foto_incompleta` | «sin dato: foto patrimonial incompleta» | Falta el valor de alguna ficha vigente; se adjunta la lista de fichas pendientes. Un valor `0,00` no falta. |
| `ingresos_incompletos` | «sin dato: presupuesto anual de ingresos incompleto» | Algún mes del año carece de partida explícita en una raíz de ingreso; se adjuntan los meses pendientes. |
| `ingresos_nulos` | «sin dato: ingresos presupuestados nulos» | El total anual firmado de ingresos es exactamente cero y, por tanto, el denominador es cero. |
| `ingresos_negativos` | «sin dato: ingresos presupuestados no positivos» | El total anual firmado de ingresos es negativo. |

Una foto completa con activos líquidos `0,00` y denominador positivo produce **`0,00 meses`**, no «sin dato». Los cambios en una foto o en el presupuesto recalculan el resultado del mes consultado. Cada indicador futuro define sus propios motivos y su orden de evaluación.

## 7. Importación y sincronización

El [contrato CSV](contrato-csv.md) define la importación histórica. Cualquier importación muestra antes de confirmar número de filas, altas reales y presupuestarias, cuentas y categorías por resolver, errores y posibles duplicados. Una carga con errores no escribe parcialmente los datos: se corrige o se rechaza el lote. El mismo contenido de archivo cargado de nuevo no duplica registros; dos filas idénticas dentro de un mismo archivo siguen siendo dos registros. Un solapamiento entre archivos distintos se señala para revisión, sin descartarlo silenciosamente.

### 7.1 Copia manual en Google Drive

La base SQLite reside en el almacenamiento privado local de cada instalación. La carpeta normal y visible de Google Drive contiene un único archivo activo `autofinance.sqlite`, una copia completa creada por la app, sin cifrado adicional al de la cuenta de Google. Las actualizaciones del mismo archivo utilizan el historial nativo de versiones de Drive; sus revisiones anteriores pueden purgarse según la política de Google y no se promete retención indefinida. Solo los botones «Subir copia» y «Descargar última copia» acceden a Drive; abrir, editar o cerrar la app no inicia una transferencia. Cada instalación recuerda la versión remota de la que procede su base local y si hubo cambios locales desde esa versión. La pantalla muestra la cuenta, la fecha y la versión de la última copia remota conocida, el estado de los cambios locales y el resultado de la última operación. Una versión remota desconocida no se presume igual a la local: se consulta antes de subir.

**Subir copia.** Al pulsar el botón, la app obtiene una copia SQLite consistente de la base local, comprueba que se puede abrir y consulta la versión actual en Drive. Solo inicia la publicación de una nueva versión completa si la versión remota consultada coincide con la conocida por esta instalación; una subida inicial solo se permite si la consulta completa acredita que aún no existe copia remota. Una versión distinta observable antes de subir detiene la operación como divergencia. Comparar antes de subir no es una escritura condicional atómica. Si la prueba de MA-TSK-061 acredita una condición verificable por el servidor para la modalidad binaria utilizada, la subida debe utilizarla y tratar su rechazo por versión obsoleta como divergencia. Mientras no se acredite esa capacidad, no se promete bloquear cambios entre la consulta y el guardado. Si Drive no ofrece esa condición, el usuario acepta que dos instalaciones que consulten la misma versión y suban simultáneamente puedan completar ambas operaciones, quedando activa la última escritura y la anterior sujeta al historial nativo de Drive. Esta excepción no permite ignorar una divergencia ya observable, forzar una sobreescritura ni fusionar datos automáticamente. La copia remota anterior sigue utilizable hasta que la nueva esté completa. Tras confirmar la publicación, se registra la versión publicada como conocida y se muestra «Copia subida» con fecha y versión; ese acuse no garantiza que otro equipo no publique después. Un fallo antes de confirmarla no se anuncia como éxito; la app vuelve a consultar Drive antes de un nuevo intento para resolver si la subida llegó a completarse.

**Descargar última copia.** La app consulta y presenta fecha y versión remotas antes de sustituir nada. Si hay cambios locales desde la versión conocida, muestra que se perderán de la base activa y pide confirmación expresa; cancelar conserva la base abierta. Al confirmar, descarga el archivo completo a una ubicación temporal, valida que sea una base SQLite íntegra y compatible, y crea una copia local previa de la base que va a reemplazar. Solo con descarga, validación y respaldo terminados cierra la base activa, instala la descargada de forma segura y la abre; registra entonces la versión descargada como conocida y muestra «Copia descargada» con fecha y versión. Si no puede completar cualquiera de esos pasos, restaura o mantiene abierta la base anterior y muestra «No se descargó la copia; tus datos locales siguen disponibles». El respaldo previo permanece disponible para recuperar manualmente el estado local anterior.

**Divergencia y conexión.** Si Windows sube una copia, Android puede descargarla, modificar datos y subir otra versión. Una subida posterior desde Windows basada en la versión anterior se rechaza con «Hay una copia más reciente en Drive; no se ha subido tu copia local». Se ofrecen las opciones de conservar los datos locales y volver a consultar Drive, o descargar la última copia mediante el flujo anterior; no se fusionan versiones ni se sobreescribe la copia remota por defecto. Si falta conexión, falla la autenticación o se interrumpe una transferencia, se indica el motivo y se permite reintentar desde el botón correspondiente. Una subida incompleta no sustituye la última copia remota utilizable; una descarga incompleta o inválida no sustituye la base local utilizable. Ningún reintento automático en segundo plano modifica las bases.

La excepción de carrera fue aprobada por el usuario en MA-EPIC-060/MA-TSK-061; el [informe técnico y protocolo reproducible](../ep-007/control-versiones-drive.md) distingue la capacidad comprobada de la pendiente. No cambia la validación SQLite, el respaldo previo, la confirmación de descarga ni la recuperación local. La primera creación concurrente requiere también comprobar la identidad única del archivo: varias candidatas son un estado ambiguo, no una autorización para elegir o sobrescribir una de ellas.

## 8. Criterios de entrega de EP-001

Los [casos de referencia](casos-referencia.md) deben poder ejecutarse como pruebas de aceptación en las épicas posteriores. El [registro de decisiones](decisiones.md) conserva el origen de cada regla. El usuario aprobó el contrato completo el 2026-10-01 y sus artefactos están confirmados y subidos al remoto Git configurado. El contrato aprobado sirve de entrada a EP-002 y EP-003.
