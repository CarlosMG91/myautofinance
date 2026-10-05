# MA-TSK-087 · Casos sintéticos de referencia

Fixture común; fechas ISO civiles y cantidades en céntimos. Las identidades son simbólicas y representan UUID distintos. `a1` y `a2` son cuentas corrientes activas. Categorías: `c` raíz, `c1` hija nivel 2 y `c11` nieta nivel 3; `d` es otra raíz. `NULL` es «Sin clasificar».

| UUID | Cuenta | Fecha valor | Concepto | Céntimos | Categoría directa | Discrecionalidad | Procedencia |
|---|---|---|---|---:|---|---|---|
| m1 | a1 | 2026-03-31 | Café | +1250 | c | NULL | manual |
| m2 | a1 | 2026-03-31 | café | +1250 | c1 | regalo | import_row r1 |
| m3 | a2 | 2026-03-30 | Café | -450 | c11 | NULL | import_row r2 |
| m4 | a1 | 2026-03-01 | Árbol | -300 | d | NULL | manual |
| m5 | a2 | 2026-04-01 | CAFE | -200 | NULL | capricho | manual |

m1 y m2 son duplicados legítimos: UUID y procedencia distintos; no deduplicar por igualdad visible. Los signos representan una entrada (+1250) y salidas (-450, -300, -200). El 2026-03-31 pertenece a marzo por fecha de valor, aunque la fecha técnica de edición sea posterior. Subtotal marzo global: +1750 céntimos.

## Consultas esperadas

| Consulta | UUID en orden | Subtotal |
|---|---|---:|
| Marzo, sin más filtros | m1, m2, m3, m4 | +1750 |
| Marzo, cuenta a1 | m1, m2, m4 | +2200 |
| Marzo, categoría c directa | m1 | +1250 |
| Marzo, rama c | m1, m2, m3 | +2050 |
| Marzo, Sin clasificar | vacío | 0 |
| Marzo, cuenta a1 y rama c | m1, m2 | +2500 |
| Marzo, concepto `CAFE` | m1, m2, m3 | +2050 |
| Abril, Sin clasificar | m5 | -200 |
| Marzo, concepto `arbol` | m4 | -300 |

En empate de fecha, UUID ascendente resuelve estabilidad (m1 antes que m2). Búsqueda no distingue mayúsculas ni acentos, pero solo mira concepto: buscar `regalo` o `capricho` no devuelve filas aunque aparezcan en discrecionalidad. Combinar filtros aplica intersección. Una página de tamaño 2 para marzo global muestra m1,m2 pero subtotal sigue siendo +1750, pues agrega también m3,m4. El cursor tras m2 continúa m3,m4 sin repetir filas.

## Escritura individual

1. Editar m2 cambiando concepto y categoría conserva UUID m2, a1, fecha, +1250, discrecionalidad `regalo` y procedencia r1. Ninguna duplicidad visible con m1 provoca rechazo.
2. Editar discrecionalidad de m2 a NULL conserva todos sus otros campos; volver a texto no cambia signo ni consultas/subtotales.
3. Categoría NULL representa «Sin clasificar». Categorías c, c1 y c11 pueden asignarse como referencias directas; no se sustituyen descendientes por raíz.
4. Cambiar fecha de valor a un mes en que la cuenta no está vigente, usar cuenta deuda/cartera, importe cero, fecha imposible o concepto vacío rechaza escritura sin cambiar registro ni revisión. Edición de un movimiento importado conserva procedencia.

## Selección y atomicidad de lotes

1. Selección explícita `{m1,m3}` categoriza ambos; cuenta, fecha, concepto, importe, discrecionalidad, UUID y procedencia permanecen. Revisión aumenta una vez.
2. Selección de página visible `{m1,m2}` modifica solo esos UUID aunque la consulta tenga m3,m4. Nunca se expande a todos los resultados.
3. Quitar categoría de `{m2,m3}` pone NULL y conserva los demás campos.
4. Borrar `{m2,m4}` con confirmación elimina exactamente esos registros; r1 y su lote siguen como procedencia retenida para m2.
5. Un lote `{m1,desconocido}` o categoría destino inválida falla atómicamente: nadie cambia, no hay borrado parcial ni incremento de revisión. Lote vacío se rechaza.
6. Selección repetida `{m1,m1}` actúa sobre m1 una vez. Un lote con registros elegibles e inelegibles no omite silenciosamente los inelegibles: se rechaza entero.

Estos casos definen resultados de aceptación, no afirman ejecución sobre una implementación de EP-010.
