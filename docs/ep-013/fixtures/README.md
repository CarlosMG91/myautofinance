# Fixtures sintéticos para importación CSV

`node docs/ep-013/fixtures/generar-fixtures.mjs` crea los CSV de `archivos/`
y `manifiesto.json`. La salida usa exclusivamente datos inventados. Repetir
el comando regenera los mismos bytes; `node
docs/ep-013/fixtures/generar-fixtures.mjs --check` verifica que los archivos
generados sigan coincidiendo con sus definiciones. Los CSV incluyen casos
válidos e inválidos para que el lector, el adaptador y la integración puedan
probarse cuando sus tickets estén disponibles.

## Formato que debe tener el archivo de origen

Cada carga recibe **un CSV** UTF-8, con o sin BOM, separado por punto y coma.
La cabecera debe ser exactamente esta y conservar el orden:

```text
fecha;concepto;importe_eur;tipo;categoria;subcategoria;subsubcategoria;cuenta_origen;discrecionalidad
```

`fecha` usa `AAAA-MM-DD`; para un presupuesto siempre es el día 1. `importe_eur`
usa punto decimal y exactamente dos cifras, sin miles ni símbolo de moneda.
`tipo` acepta `REAL` o `PRESUPUESTO`, sin distinguir mayúsculas. Los espacios
exteriores se recortan al interpretar campos. Para incluir `;`, comillas o un
salto de línea dentro de un valor, se usa el entrecomillado CSV estándar y se
duplican las comillas interiores. Cada fila tiene nueve columnas.

Un REAL exige concepto, fecha válida y cuenta; su importe firmado ya expresa
el flujo real, y cero no está permitido. Categoría y niveles inferiores son
opcionales, pero no se puede saltar un nivel; los tres vacíos representan
«Sin clasificar». PRESUPUESTO exige concepto, fecha del primer día y categoría,
no admite cuenta y también exige continuidad de niveles. Su importe de origen
tiene el signo contrario al flujo previsto: por ejemplo, gasto `+100.00` se
guarda como `−100.00`, e ingreso `−3000.00` como `+3000.00`. La inversión se
aplica exactamente una vez. El cero presupuestario explícito se conserva.

## Vista previa y resolución

Antes de confirmar, revisar por registro y campo los errores, las cuentas y
rutas de categoría desconocidas o ambiguas, los posibles movimientos repetidos
y los conflictos de presupuesto. La misma ruta de categoría se resuelve nivel
por nivel; una coincidencia ambigua requiere una elección expresa. Para una
raíz nueva se elige explícitamente si es de ingreso. Asignar una raíz existente
respeta su marca. Un CSV no cambia la marca de ingreso por el signo del importe.

La vista previa presenta altas y totales firmados en céntimos enteros por tipo:
importe CSV e importe interno. Los totales PRESUPUESTO deben tener signo
opuesto entre ambas columnas; los de REAL deben coincidir. No se confirma si
queda algún error, referencia sin resolver, doble presupuesto para un mismo
nodo/mes o presupuesto simultáneo en padre y descendiente durante el mismo mes.

## Corrección y repetición

No se editan filas en la aplicación. Ante errores, corregir el archivo original
con una herramienta externa y volver a cargar el archivo completo. No se guarda
ninguna parte de una carga fallida. Volver a elegir exactamente los mismos
bytes, aunque el nombre haya cambiado, debe informar que ya se importaron y
crear cero filas. Cambiar bytes crea una carga distinta que debe validarse
completa. Dos REAL iguales dentro del mismo archivo se conservan ambos; un
parecido con filas previas se marca para revisión humana, nunca se borra solo.

`referencias-renombradas.csv` es idéntico en bytes a `valido-lf.csv`, aunque
representa una nueva selección con otro nombre. `bytes-distintos-contenido-
similar.csv` prueba el aviso de solapamiento, y `dos-reales-iguales.csv` prueba
ordinales distintos para reales duplicados. Para `referencia-ambigua.csv`, la
ambigüedad depende del catálogo sintético que monte la prueba, no del archivo
por sí solo.

## Resultados de referencia

No se cambian los casos financieros aprobados en
[`casos-referencia.md`](../../ep-001/casos-referencia.md). Al importar la
plantilla anual original, el resultado obligatorio es:

| Comprobación | Resultado |
|---|---:|
| Partidas PRESUPUESTO | 48 |
| Movimientos REAL | 10 |
| Real firmado de enero | `+122975` céntimos (`+1.229,75 EUR`) |
| Real anual | `+232965` céntimos (`+2.329,65 EUR`) |
| Presupuesto firmado anual interno | `+1320000` céntimos (`+13.200,00 EUR`) |

El archivo anual continúa siendo `docs/ep-001/historico-ejemplo.csv`; los
fixtures pequeños de esta carpeta ejercitan formato y diagnósticos, y no lo
sustituyen. Los totales de la muestra válida aquí son: REAL CSV `−5525`
céntimos e interno `−5525`; PRESUPUESTO CSV `+40000` e interno `−40000`.
Esta muestra valida que las dos inversiones previstas se entienden aparte del
resultado anual canónico de EP-001.

## Cobertura del manifiesto

`manifiesto.json` enumera propósito por archivo. Entre otros, cubre BOM/no BOM,
LF/CRLF, comillas y separadores embebidos, campos multilínea, espacios, tipo en
minúsculas, UTF-8 inválido, cabecera incorrecta, columnas extra/faltantes,
comillas sin cerrar, registros vacíos, calendario imposible, REAL cero,
presupuesto cero, presupuesto con cuenta o categoría ausente, jerarquía
incompleta, referencias ambiguas, repetición renombrada, dos REAL iguales,
bytes distintos con contenido similar y conflictos padre/descendiente o
nodo/mes. La resolución real de referencias y los solapamientos requieren un
catálogo y movimientos sintéticos del arnés de integración.
