# MA-TSK-076 · Vista Patrimonio

Ticket consultado el 2026-10-04 mediante `GET http://localhost:4310/api/data`,
tablero **My autofinance**. Se implementa la vista aprobada de MA-TSK-019 según
`docs/ep-002/entrega-flutter.md`, `mockup-final.html`, EP-001 §4/§5.2 y caso D.
Se reutilizan `WealthController.readYear`, `WealthReading`, los repositorios
SQLite y los formularios de MA-TSK-072/073/074; no se modifica el esquema.

La ruta `/patrimonio?a&m` ofrece selección de año y mes, fecha explícita del
día 1, grupos de cuentas/carteras por liquidez efectiva y deudas, valores
manuales, pendientes y resumen de activos líquidos, activos, deudas y neto.
Las doce fotos se consultan independientemente y se abren desde un desplegable,
sin suma anual. Una foto ausente o parcial muestra motivos diferenciados y
«Sin dato» en todos los totales; mantiene visibles los valores individuales.
Cero registrado es válido. Un mes sin fichas vigentes tiene un mensaje propio.

Desde 840 puntos se presentan tablas compactas con lateral de 200/216 puntos;
en ancho menor, tarjetas y navegación inferior. Se mantienen cinco destinos,
Gestión y los accesos a captura y fichas. El año seleccionado recuerda su mes;
un año nuevo comienza en enero. Formularios apilados conservan mes, scroll y
foco del origen. El alta y cambio de liquidez reciben ese mes como valor
inicial. Los retornos de fichas indican Patrimonio/periodo o Fichas según la
pila. Al regresar se vuelve a consultar el año después de la persistencia,
incluso para cambios de liquidez realizados dentro del detalle de una ficha.
La navegación principal transmite el periodo a la siguiente ruta.

Carga, ausencia válida y error recuperable tienen estados diferentes.
Un error de lectura muestra causa y Reintentar, sin reutilizar cifras antiguas.
No hay indicador, lecturas de movimientos, importación ni acceso automático a
Drive. Las demás vistas principales conservan sus marcadores técnicos.

## Verificación

`test/wealth/wealth_screen_test.dart` verifica lecturas SQLite sintéticas,
fotos parciales, cero, estados de carga/error/vacío, doce meses, año recordado,
validación de año, persistencia al volver, altas, bajas y liquidez histórica.
Prueba nueve anchos (320/360/412/839/840/1024/1199/1200/1440) con texto normal
y al 200 %, y rutas reales de captura/guardar/cancelar/retorno. Se actualiza
la prueba de MA-TSK-074 que comprobaba el antiguo texto del marcador para
comprobar la nueva referencia visible y sus pendientes. Capturas optativas
con `CAPTURE_WEALTH=1`, datos sintéticos y fuente local; no se versionan.

`flutter build windows --release --no-pub --dart-define=APP_ENV=test` correcto;
la imagen Dart release (`data/app.so`) se recompiló con esta vista. El intento
`flutter build apk --debug --no-pub --dart-define=APP_ENV=test` está bloqueado
por Android SDK ausente. No se acredita ejecución manual nativa ni pruebas
en dispositivo Android, lector de pantalla o alto contraste del sistema.
Se revisaron visualmente capturas de widgets a 320 y 1440 puntos con datos
sintéticos; esta evidencia comprueba layout, no el comportamiento nativo.

La primera ejecución completa pasó formato/análisis y 920 pruebas; agotó
el límite predeterminado de 30 segundos en un recorrido de recuperación
SQLite y produjo un fallo posterior al cerrarse su conexión. Los ocho casos
de ese archivo (`local_recovery_journey_test.dart`) pasan aislados con
`--timeout=2m`. Se repite `scripts/check-quality.ps1` con un wrapper local de
Flutter que añade únicamente ese timeout a los comandos de pruebas, sin
modificar scripts, SDK o tests. Resultado final correcto: formato sin cambios, análisis sin incidencias, 922 pruebas y las cuatro variantes de APP_ENV. `toolchain.json` y `pubspec.lock` intactos; `git diff --check` correcto.

Solo se publican los archivos de este ticket en la rama configurada
`ticket/ma-tsk-071`; README, sincronización y propuestas de categorías ya
contenían cambios concurrentes y quedan fuera. No se cambia el estado de
Epic Board ni se cierra EP-009.
