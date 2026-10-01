# EP-001 · Contrato CSV histórico v1

Este contrato es para migrar movimientos y presupuestos históricos. No describe el XLS de Openbank. La [plantilla con datos sintéticos](historico-ejemplo.csv) es un ejemplo válido y el [documento de casos](casos-referencia.md) fija sus resultados.

## Formato físico

- Archivo de texto UTF-8, con o sin BOM; una fila de cabecera obligatoria, separador `;` y saltos de línea CRLF o LF.
- Cabeceras exactas en este orden: `fecha;concepto;importe_eur;tipo;categoria;subcategoria;subsubcategoria;cuenta_origen;discrecionalidad`.
- `fecha`: `AAAA-MM-DD`, fecha de valor para `REAL` y primer día del mes para `PRESUPUESTO`.
- `importe_eur`: número decimal con punto, dos cifras decimales, sin separador de miles ni símbolo de moneda; se aceptan `0.00` y `-0.00` solo en presupuestos.
- `tipo`: `REAL` o `PRESUPUESTO`, sin distinguir mayúsculas. Espacios alrededor de campos se eliminan; los nombres mostrados conservan su grafía.
- Los campos que contengan `;`, comillas o saltos de línea siguen el entrecomillado CSV estándar (comillas dobles, duplicadas dentro del campo).
- Cada registro tiene exactamente nueve campos. Se rechazan cabeceras distintas, columnas de más o de menos, comillas mal cerradas, bytes que no sean UTF-8 válido y filas vacías intermedias. Una línea final vacía tras el último salto de línea no cuenta como registro.

## Diccionario y reglas

| Columna | REAL | PRESUPUESTO |
|---|---|---|
| `fecha` | Obligatoria; determina mes y año del movimiento. | Obligatoria, día 1; determina el mes presupuestado. |
| `concepto` | Obligatorio, no vacío. | Obligatorio; puede ser «Presupuesto». |
| `importe_eur` | Positivo para entrada y negativo para salida; cero no admitido. | Signo **opuesto** al flujo previsto: gasto `+`, ingreso `-`. Se invierte al guardar; cero explícito admitido. |
| `categoria` | Opcional; vacío significa «Sin clasificar». | Obligatoria. |
| `subcategoria` | Opcional; requiere `categoria`. | Opcional; requiere `categoria`. |
| `subsubcategoria` | Opcional; requiere `subcategoria`. | Opcional; requiere `subcategoria`. |
| `cuenta_origen` | Obligatoria y asociada a una cuenta de la app. | Vacía; un presupuesto no pertenece a una cuenta. |
| `discrecionalidad` | Texto opcional, conservado literalmente tras quitar espacios externos. | Texto opcional, conservado para no perder el dato histórico. |

Las categorías del archivo se comparan con las existentes sin distinguir mayúsculas ni espacios externos. En la previsualización se muestran las rutas y cuentas desconocidas; el usuario las vincula o confirma su creación. Para cada categoría raíz nueva debe elegir si es de ingreso. La app no deduce esa marca del signo. No se escribe ninguna fila hasta resolver todas las referencias y errores del lote.

La comparación de cuentas también ignora mayúsculas y espacios externos. Una ruta se resuelve nivel por nivel y conserva el texto elegido al crear cada nodo; una coincidencia ambigua se resuelve expresamente, nunca se elige una cuenta o categoría al azar. La asignación elegida se aplica a todas las filas que usan la misma referencia del archivo. Vincular a una raíz existente respeta su marca de ingreso. `Sin clasificar` se obtiene dejando vacíos los tres campos de categoría de un `REAL`; no se crea una categoría con ese nombre.

El archivo se valida completo, incluidas fechas reales del calendario, importe, jerarquía y prohibición de presupuesto simultáneo en padre y descendiente del mismo mes. Para `PRESUPUESTO` se rechazan además dos partidas del mismo mes y nodo, y los conflictos con partidas ya guardadas, después de resolver las asignaciones. Para `REAL` se admiten filas idénticas. La previsualización muestra número de fila, tipo, fecha, ruta y cuenta resueltas, importe CSV e importe interno, número de altas por tipo, totales firmados por tipo antes y después de invertir `PRESUPUESTO`, errores con fila y motivo, referencias pendientes y posibles solapamientos. No se permite confirmar mientras haya errores o referencias sin resolver.

Confirmar vuelve a comprobar la huella del archivo, las asignaciones y los conflictos contra el estado vigente de la base. La creación de referencias aprobadas, lote, partidas y movimientos se hace en una sola transacción: si falla cualquier comprobación o escritura, se revierte todo. Una previsualización no modifica datos.

## Repetición y solapamiento

La identidad de una carga es SHA-256 de los bytes completos del archivo recibido, incluido BOM y saltos de línea, independientemente del nombre. La huella se registra con unicidad en la misma transacción que las altas. Volver a cargar exactamente esos bytes muestra «ya importado» y crea cero cuentas, categorías, partidas y movimientos, aunque cambie el nombre. Variar bytes genera otro lote y se valida de nuevo; no se promete equivalencia semántica entre archivos con distinta codificación física. El número ordinal de registro CSV, empezando por 2 tras la cabecera, distingue dos movimientos idénticos dentro de un lote: ambos se conservan. Si otro archivo contiene filas que parecen ya existentes, la previsualización las marca como posibles duplicados para revisión humana; nunca se eliminan por parecido de manera silenciosa. Las partidas presupuestarias, aun en otro lote, deben cumplir la unicidad y la regla de padre y descendiente. Cada registro importado conserva la referencia al lote y su ordinal de origen.

## Ejemplos de rechazo

| Fila | Motivo |
|---|---|
| `2026-01-03;Compra;−12,50 €;REAL;Alimentación;;;Cuenta principal;` | El importe no cumple el formato decimal con punto y sin símbolo. |
| `2026-01-15;Presupuesto;400.00;PRESUPUESTO;Alimentación;;; ;` | El presupuesto requiere el primer día del mes. |
| `2026-01-01;Presupuesto;1200.00;PRESUPUESTO;Vivienda;;;;` | Rechazada si ya hay una partida de enero en `Vivienda/Alquiler`. |
| `2026-01-03;Compra;-12.50;REAL;Alimentación;;;;` | Falta la cuenta de un movimiento real. |
| `2026-02-30;Compra;-12.50;REAL;Alimentación;;;Cuenta principal;` | La fecha no existe en el calendario. |
| `2026-01-03;Compra;0.00;REAL;Alimentación;;;Cuenta principal;` | Un movimiento real no admite importe cero. |
| `2026-01-01;Presupuesto;100.00;PRESUPUESTO;Ocio;;;Cuenta principal;` | Un presupuesto no admite cuenta. |
| `2026-01-03;Compra;-12.50;REAL;;Supermercado;;Cuenta principal;` | Una subcategoría requiere categoría. |
| `2026-01-01;Presupuesto;100.00;PRESUPUESTO;Vivienda;Alquiler;;;` dos veces | Dos partidas del mismo mes y nodo, incluso en lotes distintos. |

## Aceptación de MA-TSK-008

La plantilla se puede importar en una base vacía tras confirmar la creación de sus cuentas y categorías. El archivo repetido crea cero filas; dos filas iguales dentro del archivo crean dos movimientos. Los importes presupuestarios quedan con el signo interno indicado en [casos-referencia.md](casos-referencia.md). Un archivo inválido deja la base sin cambios.
