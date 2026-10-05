# MA-TSK-092 · Lista de movimientos reales

Implementación del 2026-10-05. Epic Board (`GET /api/data`, tablero **My
autofinance**) confirma MA-TSK-088 y MA-TSK-091 `done`. En MA-TSK-091 aparece
la discusión humana de **Tú**: «Propuesta visual aceptada:
http://localhost:4310/mockups/autofinance-ma-tsk-091-v1.html». Esa evidencia
supera el estado pendiente del documento local de la propuesta; no se modifica
el trabajo pendiente de publicar de aquel ticket.

## Composición y comportamiento

- `LocalBackupSession.movements` resuelve la conexión activa por lectura.
  `createMovementListSource` reutiliza los repositorios SQLite de EP-004/008/009.
  No crea tablas, conexiones adicionales, migraciones ni persistencia paralela.
- `/movimientos?a=2026&m=03` abre marzo desde Gestión o los accesos de
  Estado/Real. `desde`/`hasta` permiten periodo civil exclusivo; `c` admite
  UUID de categoría, `alcance=direct` o `branch`, y `sinClasificar=1` representa
  referencia nula. Categoría concreta y Sin clasificar simultáneos se rechazan.
  Estado/Real siguen siendo marcadores técnicos; sus futuras cifras pueden
  utilizar esta entrada con rama, alcance y mes explícitos.
- La consulta es `MovementRepository.readPage`: concepto literal sin mayúsculas
  ni acentos, periodo, cuenta, rama/directos/Sin clasificar, fecha descendente,
  desempate UUID, cursor y subtotal de todos los resultados. Producción usa
  páginas de 100; las pruebas usan dos para demostrar resultados ocultos.
- Tabla desde 840 px; tarjetas en ventana estrecha y con texto al 200 %.
  Campos visibles: fecha civil, concepto, cuenta, ruta actual o Sin clasificar,
  EUR firmado exacto y acceso al detalle de lectura, incluida procedencia y
  discrecionalidad. El formato conserva céntimos incluso en extremos int64.
- Selección explícita por UUID o captura exacta de página visible. Página/filtros
  limpian selección con anuncio. Error de lectura retira subtotal y filas,
  conserva UUID, filtros y cursor para reintentar. Validación del formulario no
  modifica la consulta aplicada; el encabezado explica los resultados activos.
- El detalle se apila; al volver se refrescan referencias y se restauran página,
  periodo, filtros, alcance, selección, scroll y foco del botón Abrir. Cambiar
  tamaño conserva el mismo controlador. Cambios de catálogo invalidan lectura y
  reinician cursores; la siguiente consulta resuelve rutas actuales.

## Traspaso a los siguientes tickets

`MovementListController.selection` entrega `MovementSelection` con UUID
concretos; `context` captura inmutablemente periodo, cuenta, categoría, alcance,
concepto y página. `MovementListScreen.onSelection` entrega ambos. Las acciones
de lote deben deshabilitarse durante carga/error y revalidar todos los UUID al
escribir. Ni selección ni cursor amplían el alcance a resultados ocultos.

MA-TSK-093 implementará el editor; MA-TSK-094 conectará categorizar/quitar
categoría/borrar con las confirmaciones y transacciones existentes. Este ticket
no añade escrituras, importadores, presupuestos, fotos ni sincronización.

## Verificación

- Toolchain local `.tools/flutter`: Flutter 3.47.0, Dart 3.13.0; comprobación
  de versiones y `flutter pub get --enforce-lockfile` correctos, sin cambios de
  SDK ni lockfile.
- `scripts/check-quality.ps1`: formato, análisis, 961 pruebas y cuatro
  configuraciones de arranque correctos. Los ajustes finales se verifican además
  con análisis y pruebas específicas de lista y arquitectura.
- Pruebas SQLite/widgets: subtotal global, búsqueda, rama/directos/no clasificado,
  UUID/página, errores y recuperación, contexto inmutable, invalidación, tablas,
  tarjetas, nombres semánticos, retorno con scroll/foco y adaptación a
  320/412/1024/1440 px y texto 200 %. Capturas sintéticas opcionales con
  `--dart-define=CAPTURE_MOVEMENT_LIST=true` quedan en `.tools`, fuera del commit.
- Windows release con `APP_ENV=test`: compilación correcta. El compilador local
  es Visual Studio 18 Insiders; no acredita por sí solo el entorno VS2022 de CI.
- Android debug se intentó: bloqueado por **Android SDK no configurado**.
  No se verificó dispositivo Android, lector de pantalla ni teclado nativo.

Solo se publican los archivos de MA-TSK-092 en la rama configurada
`ticket/ma-tsk-071`; se excluyen los cambios concurrentes de Drive y los
documentos/prototipos sin seguimiento de otros tickets.
