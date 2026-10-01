# EP-001 · Casos de referencia y resultados esperados

Estos datos son sintéticos y constituyen la comprobación funcional de EP-001. Las filas de movimientos y presupuesto están en [historico-ejemplo.csv](historico-ejemplo.csv); sus signos de presupuesto se invierten al importar.

## Reproducción y alcance de la comprobación

Desde la raíz del repositorio, ejecutar `node docs/ep-001/verificar-casos.mjs`. El comprobador lee el CSV original, invierte el signo de cada presupuesto y verifica filas, duplicados «Café», sumas mensuales y anuales por raíz, diferencias, foto sintética, colchón y propuesta de 2027. Debe terminar con `OK`; cualquier discrepancia termina con error. Sus cifras obligatorias son **48 presupuestos, 10 reales, enero real +1.229,75 EUR, real anual +2.329,65 EUR y presupuesto anual +13.200,00 EUR**.

Los casos A–H describen además operaciones de la futura aplicación que necesitan una base y vistas implementadas. El caso I es una prueba manual entre Windows y Android con Drive: comprobar versiones visibles, divergencia y conservación de ambas bases ante los fallos descritos. La verificación del CSV por sí sola no demuestra esos comportamientos.

## Preparación del caso

Crear la cuenta `Cuenta principal`; marcar `Ingresos` como raíz de ingreso y `Vivienda`, `Alimentación`, `Ahorro` y `Ocio` como raíces de salida. Mantener las subcategorías y la subsubcategoría `Alimentación / Supermercado / Compra semanal` del archivo. Confirmar la importación completa: **48 partidas presupuestarias y 10 movimientos reales**. Las dos filas idénticas «Café» son dos movimientos, no un duplicado de importación.

Crear además las siguientes fichas y foto manual del **2026-01-01**:

| Ficha | Tipo | Liquidez | Valor EUR |
|---|---|---|---:|
| Cuenta principal | Activo | Líquida | 6.000,00 |
| Cuenta de ahorro | Activo | Líquida | 3.000,00 |
| Cartera | Activo | Media | 10.000,00 |
| Deuda familiar | Pasivo | No aplica | 5.000,00 |

No crear foto para febrero. El movimiento «Transferencia a ahorro» es una salida de `Cuenta principal` categorizada como `Ahorro`; no crea automáticamente una entrada en la otra cuenta ni modifica las fotos.

En el detalle de la compra semanal de enero y de las dos filas «Café» se muestra `Discrecional`. Las demás filas reales de la plantilla dejan ese campo vacío. Cambiar una categoría o cuenta en una corrección conserva el texto de Discrecionalidad salvo edición expresa de ese campo.

## Caso A · Normalización e importación

Una fila CSV de presupuesto de salario `-3000.00` se guarda como ingreso previsto `+3.000,00`; alquiler `+1000.00` se guarda como salida prevista `−1.000,00`. Reimportar el mismo contenido produce **0 altas** y mantiene 48 presupuestos y 10 reales. Las dos filas «Café» aportan juntas `−20,00` al real de enero. Si se añade una partida `Vivienda` para enero, se rechaza por coexistir con `Vivienda / Alquiler` en ese mes.

## Caso B · Estado de enero de 2026

| Rama | Presupuesto EUR | Real EUR | Diferencia `real − presupuesto` EUR |
|---|---:|---:|---:|
| Ingresos / Salario | +3.000,00 | +3.100,00 | +100,00 |
| Vivienda / Alquiler | −1.000,00 | −1.000,00 | 0,00 |
| Alimentación / Supermercado / Compra semanal | −400,00 | −350,25 | +49,75 |
| Ahorro / Cuenta de ahorro | −500,00 | −500,00 | 0,00 |
| Ocio, sin presupuesto | — | −20,00 | −20,00 frente a presupuesto implícito cero; etiquetado «sin presupuesto» |
| **Total firmado** | **+1.100,00** | **+1.229,75** | **+129,75** |

`Alimentación` y `Alimentación / Supermercado` muestran como total agregado `−350,25` real y `−400,00` previsto; no suman otra vez el nodo hoja. Al abrir `Ocio` aparecen las dos filas «Café».

## Caso C · Estado de febrero de 2026

El presupuesto firmado del mes es `+1.100,00`. El real es `+3.020,00 − 1.000,00 − 420,10 − 500,00 = +1.099,90`; diferencia `−0,10`. El presupuesto de alimentación es `−400,00`, su real `−420,10` y su diferencia `−20,10`.

## Caso D · Cuentas, deudas e inversiones

Para enero: activos líquidos `6.000 + 3.000 = 9.000,00`; activos medios `10.000,00`; activos totales `19.000,00`; deudas `5.000,00`; patrimonio neto `14.000,00`. Estos valores proceden solo de la foto. Para febrero, la vista muestra **«sin dato»** y no repite la foto de enero.

En una copia del caso, registrar para febrero únicamente `Cuenta principal = 6.200,00` y `Deuda familiar = 4.800,00`: la vista y el colchón siguen mostrando **«sin dato»** e identifican `Cuenta de ahorro` y `Cartera` como pendientes. Registrar después `Cuenta de ahorro = 0,00` y `Cartera = 10.500,00`: la foto del 2026-02-01 queda completa, con activos líquidos `6.200,00`, activos totales `16.700,00`, deudas `4.800,00` y patrimonio neto `11.900,00`. El cero de la cuenta de ahorro es un dato válido. El colchón de febrero pasa a `6.200 / 3.000 = 2,0666…` meses (presentación a dos decimales: `2,07`). Corregir después `Cuenta principal` a `6.300,00` conserva la referencia 2026-02-01 y recalcula activos líquidos `6.300,00` y patrimonio neto `12.000,00`; la foto de enero permanece en `14.000,00`.

En otra copia, dar de alta una ficha `Cuenta nueva` con vigencia desde marzo de 2026. No se exige en enero ni febrero; una foto de marzo requiere su valor, incluso si es `0,00`. Darla de baja con último mes vigente abril conserva sus fotos de marzo y abril y deja de exigir valor en mayo. Ninguno de estos cambios rellena meses sin foto.

## Caso E · Presupuesto anual de 2026

Cada uno de los doce meses muestra ingresos `+3.000,00`, vivienda `−1.000,00`, alimentación `−400,00`, ahorro `−500,00` y total `+1.100,00`. El año suma ingresos `+36.000,00`, vivienda `−12.000,00`, alimentación `−4.800,00`, ahorro `−6.000,00` y **total `+13.200,00`**. La matriz se puede abrir hasta las 48 partidas originales.

## Caso F · Real anual de 2026

Enero totaliza `+1.229,75`, febrero `+1.099,90` y marzo–diciembre `0,00`. Por ramas, el año contiene ingresos `+6.120,00`, vivienda `−2.000,00`, alimentación `−770,35`, ahorro `−1.000,00` y ocio `−20,00`: **total `+2.329,65`**. Los importes de ocio no desaparecen por carecer de presupuesto.

## Comprobación conjunta de las cuatro vistas

Partir de la importación y la foto iniciales, sin las modificaciones de los casos D, H, J o K. En las tablas, «año» significa suma de flujos de los doce meses. Marzo–diciembre no tienen movimientos reales. Las cifras de una fila padre incluyen las hojas indicadas, pero el total general suma solo las raíces.

| Estado mensual: raíz | Enero previsto | Enero real | Enero diferencia | Febrero previsto | Febrero real | Febrero diferencia |
|---|---:|---:|---:|---:|---:|---:|
| Ingresos | +3.000,00 | +3.100,00 | +100,00 | +3.000,00 | +3.020,00 | +20,00 |
| Vivienda | −1.000,00 | −1.000,00 | 0,00 | −1.000,00 | −1.000,00 | 0,00 |
| Alimentación | −400,00 | −350,25 | +49,75 | −400,00 | −420,10 | −20,10 |
| Ahorro | −500,00 | −500,00 | 0,00 | −500,00 | −500,00 | 0,00 |
| Ocio | sin presupuesto | −20,00 | −20,00 | sin presupuesto | 0,00 | 0,00 |
| **Total firmado** | **+1.100,00** | **+1.229,75** | **+129,75** | **+1.100,00** | **+1.099,90** | **−0,10** |

El presupuesto anual y el real anual deben presentar las siguientes celdas de raíz. En presupuesto, marzo–diciembre repiten la cifra mensual de enero. En real, cada uno de esos meses vale `0,00`.

| Raíz | Presupuesto enero | Presupuesto febrero | Presupuesto 2026 | Real enero | Real febrero | Real 2026 |
|---|---:|---:|---:|---:|---:|---:|
| Ingresos | +3.000,00 | +3.000,00 | +36.000,00 | +3.100,00 | +3.020,00 | +6.120,00 |
| Vivienda | −1.000,00 | −1.000,00 | −12.000,00 | −1.000,00 | −1.000,00 | −2.000,00 |
| Alimentación | −400,00 | −400,00 | −4.800,00 | −350,25 | −420,10 | −770,35 |
| Ahorro | −500,00 | −500,00 | −6.000,00 | −500,00 | −500,00 | −1.000,00 |
| Ocio | sin presupuesto | sin presupuesto | sin presupuesto | −20,00 | 0,00 | −20,00 |
| **Total firmado** | **+1.100,00** | **+1.100,00** | **+13.200,00** | **+1.229,75** | **+1.099,90** | **+2.329,65** |

Al desplegar `Alimentación`, `Alimentación / Supermercado` y `Compra semanal` tienen el mismo agregado cuando solo existe la hoja. Su `−400,00` previsto y su `−350,25` real de enero se cuentan una vez en `Alimentación`, no tres. En febrero el real de esa hoja es `−420,10`; en 2026 suma `−770,35`. El desglose de ingresos, vivienda y ahorro también conserva una única partida o movimiento por registro. Abrir una cifra de Ocio en enero devuelve las dos filas «Café»; en febrero no devuelve ninguna.

La vista patrimonial muestra para enero activos líquidos `9.000,00`, activos totales `19.000,00`, deudas `5.000,00` y patrimonio neto `14.000,00`. Para febrero y marzo–diciembre muestra «sin dato: falta foto patrimonial»; al consultar el año 2026 se ven estos estados mensuales, sin total anual de patrimonio. La variante de foto completa de febrero del caso D da `11.900,00` de patrimonio neto solo para febrero y no cambia ningún flujo de las otras tres vistas.

## Caso G · Colchón de emergencia

Ingresos anuales presupuestados: `36.000,00`; promedio mensual: `3.000,00`. Con la foto de enero, `9.000,00 / 3.000,00 = 3,00 meses`. La deuda y la cartera de liquidez media no integran el numerador. En febrero el resultado es **«sin dato: falta foto patrimonial»**. Si se elimina el presupuesto de salario de un mes, el indicador queda **«sin dato: presupuesto anual de ingresos incompleto»**; si los doce importes de ingreso son cero, **«sin dato: ingresos presupuestados nulos»**.

Comprobaciones independientes sobre copias del caso inicial, conforme al [contrato del indicador](especificacion.md#61-contrato-extensible-de-indicadores):

| Variante | Resultado esperado |
|---|---|
| Enero original: líquidos `9.000,00`, ingresos anuales `36.000,00` | `3,00 meses`; `36.000,00 / 12 = 3.000,00`. |
| Febrero sin foto, con presupuesto completo | `foto_ausente`; «sin dato: falta foto patrimonial». |
| Febrero con solo `Cuenta principal` y `Deuda familiar` valoradas | `foto_incompleta`; pendientes `Cuenta de ahorro` y `Cartera`. |
| Enero con partida de salario eliminada solo en marzo | `ingresos_incompletos`; mes pendiente marzo, aunque los otros once meses tengan ingresos. |
| Enero con salario `0,00` explícito en los doce meses | `ingresos_nulos`; «sin dato: ingresos presupuestados nulos». |
| Enero con salario `−100,00` explícito en los doce meses | `ingresos_negativos`; «sin dato: ingresos presupuestados no positivos». |
| Enero con ambas cuentas líquidas valoradas en `0,00` y el presupuesto original | `0,00 meses`; el numerador cero es válido. |

## Caso H · Propuesta presupuestaria para 2027

La propuesta usa el real del mes equivalente de 2026 por **categoría raíz**, incluye ingresos y salidas, y redondea la magnitud a la decena superior o igual. Para enero propone: ingresos `+3.100,00`, vivienda `−1.000,00`, alimentación `−360,00` (desde `−350,25`), ahorro `−500,00` y ocio `−20,00`. Para febrero propone ingresos `+3.020,00`, vivienda `−1.000,00`, alimentación `−430,00` (desde `−420,10`) y ahorro `−500,00`. Los meses sin reales se proponen como cero editable. Ninguna propuesta modifica el presupuesto de 2026.

| Mes de 2027 | Raíz | Real del mes equivalente de 2026 | Propuesta editable | Comprobación |
|---|---|---:|---:|---|
| Enero | Ingresos | +3.100,00 | +3.100,00 | Ingreso, múltiplo exacto de diez. |
| Enero | Alimentación | −350,25 | −360,00 | Salida, magnitud redondeada hacia arriba. |
| Febrero | Ingresos | +3.020,00 | +3.020,00 | Ingreso del mismo mes del año anterior. |
| Febrero | Alimentación | −420,10 | −430,00 | Salida del mismo mes del año anterior. |
| Marzo | Ingresos | sin reales | 0,00 | Partida cero explícita, editable. |

En una copia de la propuesta, cambiar enero de `Alimentación` de `−360,00` a `−370,00` y guardar: la comparación con el real agregado `−350,25` da `+19,75`. Desglosar después esa partida en `Alimentación / Supermercado` por `−370,00`: se retira la partida de `Alimentación`, y el agregado del padre sigue siendo `−370,00`. Si se intenta guardar ambas partidas en enero, la operación se rechaza y el presupuesto anterior permanece. Lo mismo ocurre al intentar añadir `Vivienda` por `−1.000,00` al presupuesto de enero de 2026, que ya contiene `Vivienda / Alquiler`. Las partidas de raíces hermanas y las de otros meses no producen este conflicto.

## Caso I · Drive y fallos

Tras subir desde Windows, la pantalla confirma fecha y versión; Android ve esos datos antes de descargar y después puede consultar las mismas 48 partidas, 10 movimientos y foto de enero. Si Android modifica datos y sube una nueva versión, una subida posterior desde Windows basada en la versión anterior se **detiene**, avisa de la divergencia y conserva tanto la base local de Windows como la copia remota de Android. No se mezclan las dos versiones.

En Windows, descargar sobre cambios locales exige confirmación; cancelar no cambia la base. Confirmar crea una copia local previa recuperable y solo sustituye la base tras descargar y validar el archivo completo. Una pérdida de conexión durante la subida deja utilizable la copia remota anterior; durante la descarga, una transferencia incompleta, una base inválida o un fallo al crear el respaldo dejan abierta y utilizable la base local anterior. En cada fallo se muestra un mensaje y puede reintentarse manualmente, sin sincronización en segundo plano.

## Caso J · Agregación y clasificación de reales

Ejecutar estas comprobaciones en una copia del estado importado, sin alterar los resultados de los casos A–I. Añadir en enero los movimientos siguientes, todos en `Cuenta principal`. No añadir presupuestos.

| Concepto | Categoría | Real EUR | Discrecionalidad |
|---|---|---:|---|
| Compra general | Alimentación | −12,00 | Necesario |
| Ajuste de compra | Alimentación / Supermercado | +2,00 | vacío |
| Abono pendiente | Sin categoría | +7,00 | vacío |
| Cargo pendiente | Sin categoría | −3,00 | vacío |
| Devolución de ahorro | Ahorro / Cuenta de ahorro | +5,00 | vacío |
| Rectificación de nómina | Ingresos / Salario | −4,00 | vacío |

`Alimentación / Supermercado / Compra semanal` sigue en `−350,25`; `Alimentación / Supermercado` agrega `+2,00 − 350,25 = −348,25`; `Alimentación` agrega además su real directo `−12,00`, por lo que muestra `−360,25`. No se cuenta un movimiento otra vez al subir por el árbol. `Sin clasificar` muestra `+4,00` netos, permite abrir sus dos movimientos y no se incorpora a `Ingresos`. `Ahorro` pasa a `−495,00`, aunque contiene una entrada positiva. `Ingresos` pasa a `+3.096,00`, aunque contiene una salida negativa. El total firmado de enero pasa de `+1.229,75` a `+1.224,75` (`−12 + 2 + 7 − 3 + 5 − 4 = −5`). La diferencia frente al presupuesto total original de `+1.100,00` es `+124,75`. La marca de ingreso de `Ingresos` permanece y no se asigna a `Ahorro` ni a «Sin clasificar» por el signo de estas filas. El detalle de «Compra general» conserva `Necesario` sin ofrecer un filtro por Discrecionalidad.

## Caso K · Transferencia entre cuentas propias

En otra copia del estado importado, crear una entrada manual `+500,00` en `Cuenta de ahorro`, con categoría `Ahorro / Cuenta de ahorro`, para representar la segunda pierna de la transferencia de enero. La salida `−500,00` de `Cuenta principal` ya existe y no genera esa entrada por sí sola. El detalle presenta dos movimientos y sus cuentas respectivas; `Ahorro` suma `−500,00 + 500,00 = 0,00` en enero y el total firmado del mes sube de `+1.229,75` a `+1.729,75`. Si se elimina solo la entrada añadida, reaparecen `−500,00` en `Ahorro` y `+1.229,75` en el total. Ninguna de estas operaciones modifica las fotos patrimoniales.
