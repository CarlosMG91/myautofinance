# MA-TSK-161 · Estado mensual en Android

Ticket, épica y requisitos consultados en la API local de Epic Board el
2026-10-11, tablero **My autofinance**. MA-TSK-158/159/160/162 están
completados. MA-TSK-159 conserva la aprobación humana «Propuesta visual
aceptada: http://localhost:4310/» y no tiene adjuntos. Se utiliza la
[entrega aprobada EP-002](../ep-002/entrega-flutter.md) y prevalecen
EP-001 §5.1 y sus casos de referencia. No se modifica el tablero.

## Implementación

Android usa tarjetas también en ancho de tableta. Windows conserva la tabla
compacta y comparte las tarjetas en ancho estrecho o con texto ampliado.
`MonthlyStatusCards` compone las mismas celdas, importes y callbacks de
`MonthlyStatusScreen`: no calcula agregados ni introduce otro servicio.
La consulta SQLite MA-TSK-158 y los enlaces MA-TSK-162 siguen siendo las
fuentes reales. No hay dependencia de fotos patrimoniales.

Cada tarjeta muestra ruta actual, archivo cuando procede, mes, todas las
cuentas y cuatro acciones etiquetadas: previsto agregado, real directo,
real agregado y diferencia. Los niveles se expanden por UUID y las raíces
empiezan contraídas. Ausencia presupuestaria, cero registrado, neto cero y
Sin clasificar conservan la interpretación de la consulta. El total usa
raíces más Sin clasificar una vez; ninguna tarjeta vuelve a sumar filas.

Padding 16, separación 12 entre tarjetas y controles mínimos 48 × 48.
Los importes y rutas envuelven sin elipsis ni límite de líneas. El resumen
limita cada bloque al ancho disponible para soportar magnitudes largas a
320 px y texto 200 %. Cada tarjeta tiene contenedor semántico y las cifras
conservan etiquetas de categoría, periodo y alcance.

Estado activa una opción de cabecera adaptable en `PrimaryNavigation`:
título y Gestión pueden ocupar varias líneas en móvil o texto ampliado.
Las otras vistas conservan la configuración anterior. Se reutilizan los
controles de periodo y navegación EP-016.

Las acciones directas/agregadas, elección de diferencia, alta, edición y
categorización usan los formularios y rutas entregados. Android Back cancela
el diálogo o vuelve desde la secundaria; el editor existente protege los
borradores. Al volver se relee SQLite y se conserva mes, expansión, scroll
y foco. Se corrige el caso táctil en que un diálogo restauraba el foco de
otra cifra anterior: el retorno selecciona el control pulsado y los cambios
de foco durante la reconstrucción no sobrescriben esa selección.

Carga y error ocultan cifras anteriores; vacío real y ausencia presupuestaria
tienen mensajes distintos. Las respuestas tardías siguen descartándose por
el contador compartido de peticiones. No se añaden filtros de cuenta,
gráficos, porcentajes o reglas financieras.

## Verificación

`monthly_status_android_test.dart` ejecuta siete recorridos bajo la variante
Android de Flutter con SQLite real en memoria y datos exclusivamente sintéticos:

- Tarjetas en Android ancho, las cuatro cifras y objetivos táctiles.
- Tres niveles, etiquetas semánticas, retorno de foco/scroll y Back a 320 px
  con texto 200 %; cabecera y Gestión completas.
- Fuentes directas/rama, neto cero con registros, Sin clasificar, total y
  elección/cancelación de diferencia mediante Back.
- Carga, vacío, ausencia, error/reintento y respuesta tardía de otro mes.
- Edición persistida de real y partida; Back protege el borrador y las
  cifras se actualizan al volver.
- Alta mediante formulario y categorización mediante selector; se conserva
  el total y se mueve el importe desde Sin clasificar a la rama elegida.
- Histórico archivado y magnitudes largas sin recorte a 320 px/texto 200 %.

La regresión de Windows declara ahora explícitamente su variante de plataforma
en lugar de depender de la plataforma Android predeterminada del runner.
Los siete recorridos Android y doce Windows pasan juntos: **19 pruebas**.
Capturas sintéticas con fuentes/iconos cargados generadas y revisadas en
`.tools/161-android-200.png` y `.tools/161-android-large-200.png`, ignoradas
por Git. No acreditan TalkBack, gestos predictivos o una sesión manual en
dispositivo Android.

Las comprobaciones del checkout incluyen dependencias de sincronización
pendientes de otros tickets, ya documentadas en
[la entrega Windows](tabla-windows.md). No se incorporan a este commit.
Las verificaciones no acreditan una clonación limpia hasta que se confirmen
esas dependencias ajenas. Versiones y lockfile se conservan.

Comprobaciones finales:

- Flutter 3.47.0 / Dart 3.13.0, `check-toolchain.ps1` y
  `flutter pub get --enforce-lockfile`: correctos.
- `check-quality.ps1`: formato de 350 archivos sin cambios y análisis sin
  incidencias. La suite completa termina con 1.557 pruebas correctas y un
  timeout de 45 s en el recorrido Windows EP-011 de Presupuesto, previamente
  documentado como problema de concurrencia en la entrega Windows. No se
  afirma una pasada completa verde ni se modifica la ayuda ajena de EP-011.
- Repetición de `budget_lifecycle_test.dart` con `--concurrency=1`, después
  de terminar la suite: Windows y Android correctos (2 pruebas, 61 s).
  Un intento solapado anterior no pudo iniciar por la DLL SQLite cargada
  por la suite; la repetición espera su cierre y no modifica el SDK.
- Los cuatro arranques development/test/production/invalid-synthetic pasan
  por separado (4 pruebas); el script general no los alcanzó tras el timeout.
- Windows release `--no-pub --dart-define=APP_ENV=test`: correcto (109,5 s).
- Android debug `--no-pub --dart-define=APP_ENV=test`: correcto (110,2 s),
  Android SDK 36 y JDK efectivo Temurin 17.0.20.1+1. La configuración Flutter
  se aísla mediante APPDATA del proceso, sin cambiar preferencias globales.
- `git diff --check`: correcto; el commit incluye solo archivos del ticket.
