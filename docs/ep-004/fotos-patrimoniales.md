# MA-TSK-037 · Fotos patrimoniales mensuales

El esquema físico v6 añade `wealth_snapshots` y `wealth_values`. Hay una
cabecera por mes civil (día 01) y como máximo una valoración manual por ficha
y cabecera, en INTEGER no negativo de céntimos. Cero completa una ficha;
las deudas conservan magnitudes positivas. No hay procedencia de importación
ni relación con movimientos para producir saldos.

`WealthRepository`, publicado por `wealth`, ofrece preparación de cabecera,
alta/corrección de valoración, borrado de valor o foto y consulta mensual.
`SqliteWealthRepository` recibe la base compartida por constructor. La
corrección conserva UUID, cabecera y mes; repetir el mismo importe no escribe.
Cada operación y la lectura conjunta se ejecutan en una transacción.

La consulta devuelve `absent`, `incomplete` o `complete`, valoraciones
registradas y fichas pendientes. Una cabecera vacía, incluso sin fichas
vigentes, es ausencia. Las fichas se exigen desde alta hasta baja inclusivas.
La liquidez es la efectiva en el mes, con validación de cobertura histórica;
las deudas no tienen liquidez. No se arrastran importes entre meses. El
resultado no expone totales parciales ni calcula informes: el consumidor debe
exigir estado completo antes de calcularlos.

CHECK, UNIQUE, FK y triggers protegen enteros, no negatividad, vigencia y
fecha de referencia. Una cabecera con valores no puede cambiar de mes;
modificar vigencia no puede dejar valoraciones fuera. El borrado de foto
retira expresamente valores y cabecera en la misma transacción.

La migración v5→v6 añade siete objetos, sin inventar fotos ni modificar datos
anteriores. La apertura conserva respaldo consistente y valida esquema,
integridad y referencias, incluyendo vigencia de las fotos. Los snapshots
anteriores permanecen intactos; se incorpora `drift_schema_v6.json`. Las
pruebas de migraciones desde versiones anteriores comparan contra v6.

## Verificación

Pruebas con SQLite real y datos sintéticos: variante del caso D, ausencias,
cabecera vacía, pendientes, cero, deuda, corrección estable, altas/bajas,
liquidez histórica y corrección de periodos, huecos rechazados, int64 máximo,
borrados, reapertura, independencia de movimientos, restricciones SQL
directas y migración v5 con preservación de revisión y respaldo. Se verifica
el uso del índice de ficha/mes mediante EXPLAIN QUERY PLAN.

Se amplía la prueba de integración nativa para persistencia, cero, corrección,
liquidez y ausencia de arrastre. No se ejecuta en Windows/Android en esta
sesión; las pruebas de host no acreditan ejecución en dispositivos. No se
modifican plataformas ni se ejecutan sus builds.

Se usa el ticket completo facilitado por el usuario: no hay herramienta Epic
Board disponible y no se cambia el estado administrativo del tablero.

Calidad local del 2026-10-01: Flutter 3.47.0 / Dart 3.13.0, lockfile sin
cambios, formato correcto, análisis sin incidencias, 64 pruebas y cuatro
variantes APP_ENV correctas. Comprobador de casos EP-001: OK. Generación
Drift, snapshot v6 y `git diff --check` correctos.
