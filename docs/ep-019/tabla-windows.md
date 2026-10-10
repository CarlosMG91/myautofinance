# MA-TSK-160 · Estado mensual en Windows

Ticket y requisitos consultados en la API local de Epic Board el 2026-10-10,
tablero **My autofinance**. MA-TSK-158 y MA-TSK-162 constan terminados.
MA-TSK-159 consta aprobado el 2026-10-10 a las 08:45 UTC, con discusión humana
«Propuesta visual aceptada: http://localhost:4310/». No hay adjuntos ni un
mockup nuevo retenido de ese ticket: la referencia visual comprobable utilizada
es [la entrega aprobada EP-002](../ep-002/entrega-flutter.md), su
[mockup](../ep-002/mockup-final.html) y su sistema visual. Prevalecen EP-001 §5.1
y los casos B/C/J/K/L. Se completa el avance parcial del mismo MA-TSK-160
presente al iniciar; los cambios de otros tickets se conservan fuera del commit.

## Composición y comportamiento

`MonthlyStatusScreen` recibe consulta, mes, callbacks de fuentes y controles
por constructor. No importa app, SQLite ni widgets internos de otros módulos.
`MonthlyStatusRoute` conecta la sesión EP-016, `PeriodControls`,
`PrimaryNavigation`, el menú Gestión existente y los enlaces MA-TSK-162.
`LocalBackupSession.monthlyStatus` resuelve la conexión activa en cada lectura.
La aplicación real sustituye `/estado`; las composiciones técnicas sin fuente
inyectada conservan su marcador para las pruebas de infraestructura.

La tabla contiene categoría, previsto agregado, real directo, real agregado
y diferencia. El resumen y el total usan las cifras de la consulta, sin sumar
filas visibles ni recalcular reglas financieras. Categorías por UUID y ruta
actual, hasta tres niveles; raíces inicialmente contraídas, antecesores e
histórico archivado conservados. Los movimientos compensados mantienen sus
fuentes aunque el real sea cero. Ausencia presupuestaria lleva «Sin presupuesto»;
el cero registrado se identifica expresamente. No se prorratean partidas padre.

Cada cifra usa el callback y alcance contratados: directo para real directo,
rama para previsto/real agregados y diferencia. La diferencia ofrece ambas
fuentes; total y Sin clasificar conservan sus selecciones específicas. Añadir
movimiento abre el formulario EP-010 con mes y origen. No añade gráficos,
porcentajes, filtro de cuenta ni dependencia de fotos patrimoniales.

El ancho estrecho o texto ampliado usa tarjetas con ruta completa y pares
etiquetados. Se mantiene el mismo widget, periodo, expansión y posición al
cambiar de tamaño. Tabla: cuerpo 14, sangría 16 por nivel y acciones de altura
mínima 40. Tarjetas: cuerpo 16, padding 16 y acciones de altura mínima 48.
Los importes heredan la fuente de la aplicación; signo y etiqueta acompañan
a las diferencias y el alto contraste utiliza colores del tema.

Lectura en curso y error ocultan las cifras anteriores: no muestran ceros
ficticios. Un contador de peticiones descarta respuestas tardías. El error
ofrece Reintentar. Volver de fuentes, alta o Gestión relee el mes; las
invalidaciones de catálogo/importación/restauración recomponen la consulta.
Si hay una secundaria abierta, la invalidación espera a su retorno: no inicia
lecturas ocultas mientras el editor mantiene operaciones sobre la misma base.
También se aplazan las respuestas del cargador que llegan con Estado oculto.
El periodo de otra vista no activa consultas en Estado bajo la pila; al volver
se aplica el contexto vigente y se solicita la lectura pendiente. La primera
consulta empieza después de disponer de las dependencias de la ruta.
Se conservan ramas, scroll y foco al releer el mismo mes. La reducción temporal
del contenido durante la carga no se publica como nueva posición de scroll.
El cambio de mes limpia la posición anterior. El origen serializado restaura
ramas y foco incluso al reconstruir Estado sin pila de navegación.

## Verificación

`test/monthly_status/monthly_status_screen_test.dart` añade doce escenarios
con SQLite real y datos sintéticos:

- Árbol de tres niveles, padre presupuestado, ausencia y cero registrado,
  detalle directo/rama y movimientos con neto cero.
- Diferencia con elección y cancelación; fuentes de total y Sin clasificar.
- Cambio de mes, respuesta tardía, error de lectura y reintento.
- Alta EP-010, Gestión, edición persistida de partida y movimiento, retorno
  y actualización de las cifras.
- Scroll no nulo con muchas ramas, expansión y foco después de detalle y
  recarga del catálogo; homónimos, traslado y archivo bajo el árbol actual.
- Reemplazo por otra conexión SQLite e invalidación, sin datos antiguos.
- Origen sin pila, tarjetas a 320 px/texto 200 % y cambio de ancho.
- Totales EP-001: enero previsto +1.100,00 €, real +1.229,75 €, diferencia
  +129,75 €; febrero real +1.099,90 €, diferencia −0,10 €, sin fotos.

Las capturas opcionales se generan con `STATUS_CAPTURE=true` en `.tools/`,
ignoradas por Git y usando solo datos sintéticos. No son evidencia de pruebas
manuales nativas, lector de pantalla o dispositivo Android. La sustitución
de conexión verifica el consumidor de restauración, sin volver a acreditar
el protocolo de recuperación EP-006/007. MA-TSK-161 conserva su propio alcance
Android y MA-TSK-164 la verificación integrada de la épica.

La comprobación de HEAD más solo MA-TSK-160 descubre un bloqueo previo de la
rama: código ya confirmado de sincronización referencia
`drive_upload_factory.dart`, `drive_upload.dart` y ampliaciones de estado
de instalación que siguen pendientes de commit de MA-TSK-064. El análisis
de esa base aislada informa 84 incidencias de Drive. No se incorporan esos
archivos ajenos al commit de Estado. Las verificaciones con la composición
completa incluyen dichas dependencias tal como están en el checkout; la
carpeta ignorada `.tools/ma-tsk-160-review` permite compilar sin disputar sus
artefactos con las pruebas principales. Esta limitación también afecta a una
clonación limpia de la rama hasta que se entregue el trabajo previo de Drive.

Comprobaciones de la versión final:

- Flutter 3.47.0 / Dart 3.13.0; `check-toolchain.ps1` y dependencias fijadas
  comprobados, sin cambios en toolchain ni lockfile.
- Doce pruebas de Estado correctas; regresión específica junto con el recorrido
  histórico de Categorías Windows/Android: 14 pruebas correctas. La suite
  completa incorpora además la aserción de ausencia de lecturas ocultas.
  La prueba histórica de Categorías con sesión real ahora espera el título
  «Estado del mes» en lugar del marcador técnico sustituido por este ticket.
  Las pruebas de navegación patrimonial esperan también la carga textual de
  Estado y desmontan la interfaz antes de cerrar SQLite. Regresión final de
  Estado, navegación patrimonial y foto: 29 pruebas correctas, sin excepciones
  por cierre prematuro de la base.
  La misma espera textual se incorpora a la ayuda de Categorías. El recorrido
  conjunto final de Estado, Categorías, navegación patrimonial y foto termina
  con 57 pruebas correctas, sin excepciones pendientes de SQLite.
- `check-quality.ps1` supera versiones, resolución fijada, formato y análisis.
  La suite completa con concurrencia 4 termina con 1.550 pruebas correctas
  y un timeout de SQLite en el recorrido histórico EP-011 de presupuesto
  Android (lectura de revisión tras borrar la partida). Su ayuda compartida
  permanece intacta: la revisión automática rechazó ampliarle las esperas
  por considerarlo fuera del alcance de estos archivos. Registro de la
  ejecución en `.tools/160-quality-approved.log` (ignorado).
  Reejecutado sin concurrencia, el recorrido EP-011 pasa en Windows y Android
  (2 pruebas, 42 s), sin modificar su ayuda compartida. No se afirma que la
  pasada completa con concurrencia 4 sea verde. Los cuatro arranques
  development/test/production/invalid-synthetic pasan por separado (4 pruebas).
- Capturas de widgets Windows 1440 px y ancho estrecho 320 px/texto 200 %:
  generadas y revisadas, con fuentes e iconos cargados para la inspección.
- Análisis de la composición completa sin incidencias. Windows release
  `--no-pub --dart-define=APP_ENV=test` correcto en 84,5 s, sobre la copia de
  verificación con las dependencias previas de Drive descritas arriba.
- La compilación Android comprueba el JDK efectivo con `flutter doctor -v`:
  Temurin 17.0.20.1+1, Android SDK 36. La configuración Flutter está aislada
  mediante APPDATA del proceso; no se modifican preferencias globales.
  Android debug `--no-pub --dart-define=APP_ENV=test` correcto en 23,9 s,
  sobre la misma composición de verificación que Windows.
