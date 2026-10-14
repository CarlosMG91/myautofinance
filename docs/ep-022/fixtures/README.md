# MA-TSK-179 · Fixtures de Real anual

Fixtures y resultados esperados para consulta anual. Todo el contenido es
sintético; no se importa ningún extracto ni se depende del motor/UI.

- `referencias.json`: caso F y variantes independientes J, K y L.
- `verificar.mjs`: verifica integridad estructural y todos los importes
  publicados desde los movimientos mediante céntimos enteros.

Desde la raíz: `node docs/ep-022/fixtures/verificar.mjs`.

Cada movimiento tiene UUID estable para permitir comprobar detalle por origen.
Las categorías se identifican por UUID, no por nombre; categoría nula es el
grupo de informe «Sin clasificar». `active` y `archived` solo afectan la
visibilidad del nodo raíz, nunca borran su historia. `categoryPath` representa
la ubicación actual, de modo que los UUID de registros sobreviven a traslados.

J parte del caso F y añade los seis movimientos descritos por EP-001. K parte
de F y añade la segunda pierna de 500 EUR entre cuentas. L es una base
independiente con el árbol de tres niveles y los dos movimientos de enero más
24 presupuestos anuales descritos en EP-001. El año esperado de L contiene
12 × (3.000 − 600) = 28.800 EUR en la rama de ingreso, incluido el movimiento
directo de enero en `SALARIO`; los presupuestos no forman parte de estos
resultados reales.

Las expectativas del manifiesto especifican cifras directas por nodo. El
agregado de una rama es la suma de los movimientos cuyos UUID apuntan al nodo
o a sus descendientes actuales. El total anual cuenta cada movimiento una vez
(raíces y Sin clasificar), nunca vuelve a sumar sus filas descendientes.
