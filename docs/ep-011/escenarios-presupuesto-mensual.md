# MA-TSK-104 · Escenarios sintéticos de presupuesto mensual

Estos escenarios son un conjunto reproducible de aceptación para EP-011. Se
apoyan en los casos E, H, L y N–O de
[`docs/ep-001/casos-referencia.md`](../ep-001/casos-referencia.md) y en las
reglas de presupuesto de
[`docs/ep-001/especificacion.md`](../ep-001/especificacion.md). No introducen
reglas financieras nuevas. Ejecutar cada escenario desde una copia limpia de
la fixture indicada; los importes internos se expresan en EUR firmados.

## Fixtures

### F1 · Árbol mínimo reproducible

Crear raíces activas `INGRESOS` (marcada ingreso) y `GASTOS` (salida). Bajo
`INGRESOS`, crear `Salario` y `Otros`; bajo `Salario`, crear `NÓMINA` e
`IMPUESTOS`. Bajo `GASTOS`, crear `Vivienda` con hijos `Alquiler` y `Luz`, y
`Alimentación` con hijo `Supermercado` y nieto `Compra semanal`. Así se
ejercitan tres niveles, hermanos y categorías de nombre repetido sin usar
nombres como identidad. En una variante, crear una segunda hija llamada
`IMPUESTOS` bajo `Salario`; ambas conservan UUID distintos.

Las rutas identifican estas categorías: `INGRESOS/Salario/NÓMINA`,
`INGRESOS/Salario/IMPUESTOS`, `GASTOS/Vivienda/Alquiler`,
`GASTOS/Vivienda/Luz` y `GASTOS/Alimentación/Supermercado/Compra semanal`.
Los alias I/S/N/T/G de los escenarios de signo remiten a los UUID estables
del caso L; al combinar con F1, usar sus UUID en vez de comparar nombres.

### F2 · Presupuesto base de enero y febrero de 2026

Para **cada** uno de enero y febrero registrar partidas internas: Salario
`+3.000,00`, Vivienda `−1.000,00`, Alimentación `−400,00` y Ahorro
`−500,00` si se añade esa raíz opcional a F1. El total mensual firmado es
`+1.100,00`. No crear partida de Ocio ni de `GASTOS` padre. Una categoría
opcional `Ocio/Café` queda sin presupuesto.

La raíz y nodos de F1 pueden poblarse con importes distintos si el escenario
solo prueba estructura; conservar F2 para comparar exactamente con los casos
de referencia E y H. Presupuesto CSV, cuando se use, lleva signo contrario:
Salario `-3000.00`, Vivienda `1000.00`, Alimentación `400.00` y Ahorro
`500.00`; tras importación los signos internos deben coincidir con F2.

### F3 · Partida importada con metadatos

Importar sintéticamente, o preparar por repositorio, una partida CSV de enero:
categoría `GASTOS/Alimentación`, concepto `Presupuesto histórico`, importe
CSV `400.00` (interno `−400,00`), discrecionalidad `Necesario`,
`importRowId` correspondiente a la fila 7, `batchId` de lote sintético y
`sourceOrdinal` 7. Guardar
el ID, timestamps y los metadatos completos antes de editar. La categoría
archivada posterior conserva la referencia. No incluir archivos ni datos
personales.

### F4 · Categoría archivada

Archivar `GASTOS/Alimentación` y su rama, conservando F3. No eliminar la
partida ni la categoría. Su detalle sigue identificable por ID y muestra la
ruta archivada para corregirla; el árbol activo no debe presentarla como
activa.

## Escenarios de lectura y escritura

| ID | Preparación y acción | Resultado esperado |
|---|---|---|
| L1 · Signos y excepción | En doce meses de 2026 poner N (`Salario/NÓMINA`) `+3.000,00` y T (`Salario/IMPUESTOS`) `−600,00`. | Ambos signos se conservan aunque T herede marca de ingreso. Total mensual `+2.400,00`, anual de ingresos `+28.800,00`; no se infiere tipo desde el signo. Coincide con caso L. |
| L2 · Árbol completo y nombres | Consultar enero con F1, dos hermanas `IMPUESTOS` y partidas solo en algunas filas. | La tabla PC incluye todo el árbol activo en orden jerárquico; cada partida se asocia por UUID. Nombre repetido no duplica ni reasigna datos. Partida padre conserva importe propio, no rellena descendientes. |
| L3 · Cero frente a ausencia | En `GASTOS/Vivienda/Luz` guardar `0,00`; dejar `GASTOS/Vivienda/Alquiler` sin partida. Consultar enero y febrero. | Enero muestra Luz `0,00` como partida registrada y Alquiler «sin presupuesto»/ausente; febrero mantiene el mismo árbol y ausencia. La lectura no materializa ceros. |
| L4 · Hermanos y meses | Enero: Alquiler `−900,00`, Luz `−100,00`; febrero: Alquiler `−950,00`, Luz sin partida. | Las hermanas coexisten. Febrero es independiente: no hereda valor ni registro de enero. |
| W1 · Alta confirmada/cancelada | Abrir alta para enero en `GASTOS/Alimentación/Supermercado/Compra semanal`, importe `−25,00`; confirmar. Repetir en febrero y cancelar. | Primera confirmación crea una partida con ese UUID/mes/importe. Cancelación deja febrero sin partida y no cambia revisión/datos. |
| W2 · Conflicto padre → descendiente | F2 con partida `GASTOS/Vivienda` en enero; intentar crear `GASTOS/Vivienda/Alquiler` para enero. | Rechazo con explicación, mes y las dos rutas; se conserva partida padre y borrador. No hay sustitución, reparto ni borrado. |
| W3 · Conflicto descendiente → padre | F2 con `GASTOS/Vivienda/Alquiler` en enero; intentar crear `GASTOS/Vivienda`. | Mismo rechazo y conservación del descendiente. Probarlo también con importe descendiente `0,00`: cero también cuenta como partida. |
| W4 · Hermanas no conflictivas | Con Alquiler enero `−900,00`, añadir Luz enero `−100,00`. | Aceptado; las categorías son hermanas. Repetir con una raíz distinta y el mismo mes: aceptado. |
| W5 · Cambio de mes/categoría | Crear detalle de Alquiler enero `−900,00`; editar a Luz febrero `−950,00` y confirmar. | La partida deja de ocupar Alquiler enero y aparece en Luz febrero. La unicidad/conflictos se validan en el destino. Ninguna otra partida cambia. |
| W6 · Edición rechazada | Con partida de Vivienda enero y otro presupuesto en Alquiler febrero, editar el último a Alquiler enero. | Conflicto padre-descendiente explicado; edición no aplicada, registro previo intacto y entradas editadas preservadas para corrección o cancelar. |
| W7 · Detalle cancelado | Abrir partida guardada, cambiar mes/categoría/importe y elegir Cancelar o Atrás; en diálogo elegir Seguir editando y luego Descartar cambios. | Seguir editando mantiene formulario y borrador. Descartar vuelve a los valores guardados; no cambia base ni revisión. |
| W8 · Borrado confirmado/cancelado | Abrir detalle, pedir eliminar. Cancelar confirmación; repetir y confirmar. | Cancelar conserva partida y sus metadatos. Confirmar elimina solo la partida solicitada; no equivale a importe cero. Segundo borrado informa que ya no existe. |
| H1 · Archivo histórico | Con F4, abrir partida de F3. Corregir importe y mes manteniendo categoría archivada; confirmar. | Edición permitida y la categoría sigue archivada. ID, concepto, discrecionalidad, fila, lote, ordinal y fecha de alta se preservan; solo cambian mes e importe. |
| H2 · Cambio explícito de destino archivado | Desde H1 intentar mover a otra categoría archivada; después probar crear en esa categoría. | Rechazo para nuevo destino/alta; referencia actual no se pierde. No se reactiva ni sustituye categoría automáticamente. |
| H3 · CSV normalizado | Importar F3 desde el CSV definido arriba. | El valor interno invierte signo una vez a `−400,00`; al abrir y guardar sin cambios permanece idéntico y no se aplica una segunda inversión. |

## Fallos, reintentos y operaciones destructivas

Ejecutar estas secuencias en copias desechables de F1–F4. Para provocar un
fallo de persistencia controlado puede usarse un trigger de prueba que aborte
la escritura; retirarlo antes del reintento. No añadir un reintento automático.

| Secuencia | Pasos | Estado esperado |
|---|---|---|
| R1 · Guardado falla y reintenta | Capturar revisión y fila inicial. Preparar una edición válida; activar fallo SQLite, confirmar; retirar fallo y pulsar Reintentar una vez. | Primer intento informa error, revierte transacción y conserva partida anterior y revisión; formulario retiene el borrador. Reintento manual guarda exactamente una vez, con una revisión efectiva. |
| R2 · Alta falla y reintenta | Preparar alta válida de `GASTOS/Vivienda/Luz` febrero `0,00`; provocar fallo, luego retirar y reintentar. | Tras fallo no hay fila ni cero fantasma; al reintentar hay una partida explícita cero, sin duplicado. |
| R3 · Borrado falla y reintenta | Pedir eliminar una partida con metadatos de F3, confirmar con fallo activo; retirar fallo, volver a pedir eliminar y confirmar. | Primer fallo conserva fila y metadatos completos. El reintento vuelve a pedir confirmación y elimina una vez; no presenta «guardado» como resultado de borrado. |
| R4 · Conflicto, corrección y reintento | Intentar W2, conservar borrador; cambiar el destino a Luz hermana, guardar. | El primer guardado no cambia base. El segundo se valida de nuevo y guarda solo la elección corregida. |
| R5 · Cancelación de borrado | Abrir detalle, solicitar borrado, cancelar; salir con Atrás. | No se elimina nada. Si hay cambios sin guardar, se muestra el diálogo de descarte según W7. |
| R6 · Repetición idempotente | Tras éxito W5 o R1, repetir la misma edición con los mismos valores. | Sigue habiendo una sola partida; no cambia timestamps ni revisión si los valores ya coinciden. |

## Registro de ejecución

Al ejecutar una implementación, anotar por escenario: fecha, plataforma,
fixture limpia usada, ID/UUID relevantes, resultado observado y evidencia
(prueba automatizada o recorrido manual). Reabrir la base SQLite después de
los escenarios R1–R3 para comprobar persistencia y rollback. Estos escenarios
no exigen pantallas implementadas para preparar o usar fixtures y sirven
tanto para pruebas de dominio/SQLite como para aceptación posterior de PC y
Android.
