# MA-TSK-073 · Liquidez por mes y corrección histórica

Desde el detalle de una cuenta o cartera, «Cambiar liquidez» permite elegir
un mes y una clasificación. La confirmación indica el inicio incluido y el
fin exclusivo: el siguiente periodo existente o el fin de vigencia. Conserva
los meses anteriores y los cambios posteriores programados.

«Corregir liquidez histórica» permite elegir un intervalo explícito. El mes
de fin es exclusivo; vacío alcanza el fin de vigencia y sustituye también
las clasificaciones posteriores que estén dentro del intervalo. La
confirmación explica ese alcance antes de escribir. Las deudas no muestran
estas acciones y los repositorios rechazan ambas operaciones sobre ellas.

El detalle muestra los periodos y su clasificación en tabla compacta para PC
y tarjetas para móvil. Tras guardar vuelve a la misma ficha con el historial
actualizado y anuncia el éxito solo después de confirmar la transacción.
Cancelar, Escape o Atrás conservan el borrador hasta confirmar su descarte;
un fallo de escritura conserva los campos y permite reintentar. Las acciones
incompatibles se deshabilitan durante la escritura y la confirmación.

`WealthManagement.changeLiquidity` y `.correctHistoricalLiquidity` coordinan
los puertos originales de EP-004 y la lectura del detalle en una misma unidad
de trabajo. El cargador se resuelve en cada guardado, sin retener una conexión
SQLite sustituida por recuperación. No se modifican esquema, repositorios,
valores manuales de fotos, dependencias, versiones ni lockfile.

Se revisaron EP-001 §4 y §5.2, la variante de liquidez histórica del caso D,
la aprobación de MA-TSK-019 y la entrega de EP-002, el mockup final y la
arquitectura de EP-003. Las nuevas acciones amplían la ficha entregada por
MA-TSK-072 usando las operaciones ya existentes; no crean otro mockup.
Indicadores, importación y Drive continúan en sus propias épicas.

## Evidencia de aceptación

Las pruebas usan SQLite real y datos sintéticos. El caso D verifica:

- Enero conserva activos líquidos de 9.000 EUR.
- Cambiar la cartera de febrero de 10.500 EUR a líquida eleva los activos
  líquidos de febrero a 16.700 EUR; el neto sigue en 11.900 EUR.
- Corregir solo febrero a media devuelve líquidos a 6.200 EUR, mantiene
  el neto y conserva la clasificación líquida de marzo.
- Todas las filas de valores de fotos conservan exactamente su contenido.

Las pruebas adicionales comprueban periodos contiguos sin huecos ni solapes,
cambio de año, alta/baja inclusivas, fin exclusivo, fin nulo, diciembre de
9999, cambios posteriores y rechazo de intervalos inválidos sin alterar
historial ni revisión. Los widgets recorren ambos formularios desde la ficha,
confirmación y cancelación con Escape, foco en campos inválidos, descarte,
escritura pendiente, ausencia de éxito anticipado, fallo y reintento, y deuda
sin acciones. La variante móvil usa 360 px y texto ampliado al 200 %.

## Verificación y publicación

Resultado local del 2026-10-04 con Flutter 3.47.0 y Dart 3.13.0:
`scripts/check-quality.ps1` correcto, resolución con `--enforce-lockfile`,
formato, análisis sin incidencias, 877 pruebas y las cuatro variantes de
`APP_ENV`. Tras ampliar las pruebas de accesibilidad y escritura pendiente,
las seis pruebas finales de `test/wealth/liquidity_management_test.dart`
también pasan; formato del módulo y análisis final vuelven a comprobarse.
`git diff --check` correcto y `pubspec.lock` intacto. Las pruebas de la suite
completa se ejecutan fuera del aislamiento para permitir los bloqueos SQLite
en archivo; las nuevas pruebas usan SQLite en memoria.

Se utiliza el ticket completo proporcionado por el usuario. No hay herramienta
Epic Board disponible en esta sesión y no se modifica el estado del tablero.
Los cambios concurrentes de sincronización y prototipos EP-008 quedan fuera
de la entrega. La rama de trabajo es `ticket/ma-tsk-071`, ya publicada con las
entregas previas de EP-009; esta entrega añade únicamente el commit del ticket.

La evidencia es automatizada con SQLite y widgets. No se ejecutaron builds ni
recorridos nativos en Windows/Android; no se modifican archivos de plataforma.
