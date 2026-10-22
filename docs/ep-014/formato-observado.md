# Openbank XHTML v1 · formato observado y recorrido conectado

El 2026-10-21 el usuario aportó un extracto original privado y el 2026-10-22
pidió expresamente habilitar el botón de importación. Esta evidencia resuelve
la falta de muestra descrita en los registros anteriores de MA-TSK-124–131.
No se incorpora el archivo personal a Git ni se reutiliza MyFinance.

## Evidencia y alcance del lector

La muestra E1 tiene 45.159 bytes y SHA-256
`db3728e64612d6261f1917c6a80176f2b77e82058f0fa97d15c0ff9d3ee8aad2`.
La inspección independiente de bytes y árbol con Python/lxml y la lectura
productiva con Dart se realizan en privado. La extensión es `.xls`, pero el
contenido es XHTML 1.0 Strict, codificado ISO-8859-1, con una sola tabla.
No es BIFF/OLE ni OOXML. Esas variantes y otros bancos se rechazan.

`OpenbankReader` usa `xml` 6.6.1 sin resolución externa ni ejecución de
contenido. El XML completo debe ser válido; solo se admite la estructura
observada. Se mantiene Flutter/Dart y las dependencias previas. Se añade
únicamente la dependencia XML fijada y su dependencia transitiva petitparser.
Versión de formato: `openbank-xhtml-iso8859-1-v1`; contrato común: `1`.
Se rechazan archivos vacíos o de más de 16 MiB antes del análisis XML.

## Estructura física

Una tabla; 60 filas físicas en E1. Las filas 1–11 son cabeceras; 12–59 son
48 movimientos; la fila final es vacía. Cada fila tiene diez celdas lógicas:
las columnas impares son separadores vacíos. Particularidad comprobada:
en las filas 6, 7 y 8 un elemento `font` envuelve tres `td`; se conserva y
aplana exclusivamente esa envoltura. No se reparan documentos HTML arbitrarios.
El `STYLE` del exportador está en mayúsculas. No hay celdas combinadas.

| Fila | Contenido observado |
| --- | --- |
| 1 y 5 | Vacías |
| 2 | `Cuentas - Movimientos`, con espacios/saltos de presentación |
| 3 | `Fecha de descarga:`; información, no fecha de valor |
| 4 | `Número de Cuenta:` y cuenta nacional con grupos 4/4/2/10 |
| 6–8 | `Descripción:`, `Titular:`, `Saldo:`; saldo expresado en EUR |
| 9 | `Lista de Movimientos` |
| 10 | Vacía |
| 11 | Columnas 2/4/6/8/10: `Fecha Operación`, `Fecha Valor`, `Concepto`, `Importe`, `Saldo` |
| 12–penúltima | Movimientos obligatorios; ninguna fila vacía intermedia se descarta |
| Última | Fila vacía de pie |

Fechas almacenadas como texto `DD/MM/AAAA`; se valida el calendario civil
sin conversión horaria. La columna 4, **Fecha Valor**, determina el periodo;
puede diferir de la operación y de la fecha incluida en el concepto.

Importe en columna 8: texto con coma y dos decimales; punto como agrupación
de miles, negativo para salida, positivo sin prefijo para entrada. Conversión
con `BigInt`, límites int64 y sin coma flotante. Cero no se admite como REAL.
No se han caracterizado importes con otras monedas o separadores.

Concepto en columna 6: texto de sus nodos, entidades XML decodificadas,
espacios exteriores eliminados para el movimiento. Los originales conservan
el texto decodificado sin recortar. Se guardan las cinco columnas, número y
descripción de cuenta, unidad `Tabla 1` y fila física. El ordinal común es la
fila física (desde 12), único y estable aunque haya dos reales idénticos.
Saldo y metadatos se conservan como información; nunca escriben fotos.

Todo error produce cero filas aceptadas. Los diagnósticos de datos incluyen
tabla, fila física y campo. Estructuras desconocidas, XML truncado, cabecera
distinta, columnas adicionales, fecha imposible, concepto vacío, cero,
desbordamiento o saldo no interpretable bloquean el lote completo.

## Fixture sintético verificable

[`fixtures/openbank-xhtml-sintetico.xls`](fixtures/openbank-xhtml-sintetico.xls)
se deriva mediante sustitución de nodos de texto del original privado;
conserva declaración, codificación, etiquetas, atributos, envolturas, cabeceras,
separadores y fila final. Se sustituyen todos los identificadores y datos
personales por valores sintéticos y se retienen cuatro filas de la misma
estructura. Se comparan los árboles de etiquetas/atributos de las once
cabeceras, las filas de datos y el pie. No es una reexportación desde Excel.

[`fixtures/openbank-xhtml-esperado.json`](fixtures/openbank-xhtml-esperado.json)
fija huella, cuatro filas, total −739,05 EUR y resultados por fila:

| Fila | Fecha valor | Céntimos | Caso |
| --- | --- | ---: | --- |
| 12 | 2026-02-20 | 120000 | Entrada y miles |
| 13 | 2026-02-18 | -250 | Operación de otro día, acento y `&amp;` |
| 14 | 2026-02-18 | -250 | Real legítimo idéntico; ordinal distinto |
| 15 | 2026-02-17 | -193405 | Salida con miles |

Los casos inválidos se obtienen mutando este mismo fixture, sin inventar
otros formatos bancarios. Añadir un salto final produce otro archivo con
solapamientos; renombrar sin cambiar bytes produce cero altas.

## Integración

`createOpenbankImportController` reutiliza el selector MA-TSK-127, calcula SHA-256
sobre todos los bytes originales y lee en un isolate. `OpenbankImportAdapter`
produce solo `InterpretedMovement`, categoría nula y referencia global pendiente.
La identidad detectada nunca asigna cuenta automáticamente: hay que elegirla
y aplicar la decisión explícitamente en cada archivo nuevo.

Gestión → **Importar Openbank** abre `/importaciones/openbank` con el origen y
periodo de retorno. Selección, cambio/cancelación, revisión, cuenta, avisos,
confirmación, resultado e historial usan el controlador y servicios EP-012.
No se eliminan coincidencias automáticamente. La misma huella ya confirmada
muestra «Ya importado» sin nuevas altas. No cambia el esquema de SQLite.

La habilitación no importa el extracto privado: los 48 movimientos de E1 ya
coinciden con la migración anterior. Tampoco configura OAuth ni sincroniza Drive.

## Verificación reproducible

- `test/importing/openbank_reader_test.dart`: formato observado, mapeo,
  originales, fechas/signos, duplicados, errores y rechazo completo.
- `test/importing/openbank_import_flow_test.dart`: selector/lector productivos,
  cuenta explícita, SQLite en disco, reapertura, repetición, cancelación,
  solapamientos revisados, rollback de escritura y fotos idénticas.
- `test/importing/openbank_import_screen_test.dart`: ruta de producción desde
  Gestión, selector con canal nativo controlado, elección de cuenta, revisión,
  confirmación SQLite y repetición, a 412 y 1440 píxeles. Capturas widget en
  `.tools/openbank-review-*.png`; no son capturas del runner nativo.
- Prueba privada del lector sobre E1 comparada fila a fila con una extracción
  independiente; el original y sus resultados detallados permanecen fuera de Git.

Resultados de calidad, builds y comprobación de la app se registran en
[`habilitacion-openbank.md`](habilitacion-openbank.md). Los tests widget a ancho
Android no equivalen a ejecutar el selector en un teléfono físico.
