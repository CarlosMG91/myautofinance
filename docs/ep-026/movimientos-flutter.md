# MA-TSK-213 · Movimientos y bandeja de categorización

La presentación usa el kit MA-TSK-208: tema claro, lista de actividad con
concepto destacado, fecha de valor/cuenta, categoría e importe firmado.
Windows alinea importes a la derecha; Android, contenedores estrechos y texto
ampliado refluyen a una columna. No hay tabla ni tarjeta vacía por registro.
El detalle/editor y la bandeja utilizan el shell compartido cuando la app
inyecta su sesión; mantienen su presentación independiente para consumidores
sin shell. El retorno del editor usa el guard de borrador existente.

Se ha consultado el ticket completo aportado por el usuario y la dependencia
MA-TSK-208 completada. No hay conector Epic Board en esta sesión y no se ha
cambiado su estado. La autorización vigente del ticket se aplica igual que
en T05–T09; no se inventa ni modifica la evidencia humana de aprobación T04.
Fuentes: EP-001 §2/casos de referencia, kit Flutter, contrato de shell y
prototipo v1 de EP-026. Las reglas financieras permanecen vigentes.

## Comportamiento y comprobación

| Criterio | Entrega y evidencia |
| --- | --- |
| Contador/subtotal del ámbito completo | `MovementPage.totalCount` y `PendingMovementPage.subtotalCents` amplían las páginas existentes. SQLite obtiene contador y suma exacta junto a la página en la misma transacción, sin cursor/límite en los agregados. Desbordamiento int64 produce error; no se inventa un subtotal. |
| Duplicados legítimos y neto cero | Cada fila tiene la clave UUID. El caso nuevo verifica dos cargos idénticos y un abono compensatorio: tres UUID, subtotal cero y todas las páginas. Cero se presenta sin signo. Vacío conserva contador/subtotal cero. |
| Filtros/selección/paginación | Se mantienen rango civil y semántica de cada extremo, concepto, cuenta, categoría, Rama completa/Solo directos, Sin clasificar y lote de importación. Se conservan los controladores, cursores y reglas de invalidación; seleccionar página solo captura UUID visibles. |
| Origen y retorno | Lista→registro→lista conserva filtros, selección, scroll y foco; lista→bandeja→lista conserva el mismo controlador. El enlace entrega origen serializable y etiqueta de retorno. Si el registro deja de estar visible, el foco vuelve al encabezado con aviso. |
| Detalle/editor | Cuenta obligatoria/vigente, categoría opcional, concepto y fecha civil, importe real distinto de cero, céntimos exactos. Discrecionalidad y procedencia (fila/lote/importRowId) se mantienen en detalle; edición, cancelación, error, guardado y rechazo siguen en los servicios existentes. |
| Categorización | Acciones individual/lote conservan selección explícita, selector, confirmación, transacción atómica y revalidación. Sin reglas automáticas ni límites nuevos. Los pendientes siguen participando en los totales firmados. |
| Accesibilidad/estados | Texto 100/200 %, 320–1440 px y umbral 840; objetivos de selección 48 dp, botones con texto, Tab/Enter y tacto. Estados carga, vacío y error usan AfStatus; fallo de lectura no muestra contador/subtotal antiguo. Las regresiones verifican recuperación y borrador. |

## Interfaz para EP-024

Entrada de presentación: `features/movements/movement_widgets.dart` exporta
`MovementRecordList` y `MovementActivityRow`. Solo puede consumirse desde
presentación; dominio/datos mantienen `movements.dart` sin Flutter. La prueba
de arquitectura contempla explícitamente esta segunda entrada y conserva
dependencias declaradas y grafo acíclico. Los argumentos transportan registro,
etiquetas resueltas, selección y acciones del propietario; no deducen identidad
desde nombres ni calculan agregados. El ancho efectivo determina el reflujo.
No se implementan filtros de partidas ni otra lista para EP-024.

## Reproducción y evidencia visual

`examples/movements_review.dart` abre únicamente SQLite en memoria con cuatro
movimientos sintéticos (neto 0,00 EUR, dos «Café» y tres pendientes). Inyecta
los adaptadores reales y el router de la app; no abre datos personales ni
servicios de Drive. Ejecutar con `flutter run -d windows -t
examples/movements_review.dart --dart-define=APP_ENV=test` para revisión manual.

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub test/movements test/architecture_test.dart
./scripts/check-quality.ps1
node docs/ep-001/verificar-casos.mjs
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
$env:MOVEMENT_REDESIGN_CAPTURE='1'
flutter test --no-pub test/movements/movement_redesign_widgets_test.dart
```

Las seis imágenes de `movimientos-capturas/` proceden del motor Flutter,
con Roboto local, router y SQLite sintéticos: actividad/bandeja a 1440, 360 y
320 px/200 %. Se han inspeccionado visualmente jerarquía, importes, categorías,
filas idénticas y reflujo. Son capturas de widgets, **no de apps instaladas**.
No acreditan Narrador/TalkBack ni la integración nativa final de T14.

## Verificación · 2026-10-13

- Toolchain Flutter 3.47.0/Dart 3.13.0 correcto, resolución fijada online y
  offline comprobada. Sin cambios de SDK, dependencias o lockfile.
- Batería específica final: **104 pruebas correctas**, incluyendo lista,
  editor, bandeja, lote, consultas, enlaces, arquitectura y recorridos nuevos.
  Los recorridos nuevos usan teclado Enter en PC y pulsación en Android;
  verifican Discrecionalidad/procedencia y retorno tras abrir registro/bandeja.
- Caso adicional de relectura fallida: conserva origen/foco lógico y no afirma
  que el registro se haya borrado cuando no pudo leerse. Las regresiones de
  Estado Android conservan las cuentas exactas de 1/2/1/4 registros con la
  etiqueta principal de concepto del rediseño.
- Revisión final: **20 comprobaciones** de lista/Estado Android y **13** de
  importación correctas. La fixture de importación usa `configureConnection`,
  igual que producción, para registrar el sumatorio exacto existente; conserva
  las comprobaciones de 51 pendientes, paginación, retorno y procedencia.
- Análisis del checkout compartido sin incidencias; formato sin cambios.
  EP-001 conserva los casos de referencia, signos, duplicados y céntimos.
- Builds finales Windows release y Android debug con `APP_ENV=test`: correctos.
  Android utiliza JDK 17 mediante APPDATA local aislado, sin preferencias globales.
- La apertura nativa para capturas fue rechazada dos veces por la revisión
  automática de permisos: consideró posible acceso a datos privados por el
  nombre del ejecutable, incluso tras comprobar la muestra y SQLite en memoria.
  Se solicitó autorización específica; no se ejecutó ni se eludió el rechazo.

La sesión de periodo de detalle/bandeja es secundaria e independiente del
principal; se comprueba cambiar abril/mayo localmente y volver a marzo en la
lista sin modificar su consulta ni la selección.

Se excluyen del commit todos los cambios concurrentes de categorías, fichas,
copias y backend Drive, README y exportaciones del kit. La rama configurada
es `ticket/ma-tsk-113`. La calidad global y los bloqueos de la base compartida
se registran a continuación.

### Límites de calidad global

`check-quality.ps1` alcanza formato/análisis correctos en el checkout completo.
La ejecución de todas las pruebas llegó a **605 correctas y 27 fallos** y quedó
bloqueada en recorridos de categorías; se detuvo únicamente esa ejecución
propia. Los fallos incluyen el ListTile bajo un DecoratedBox del rediseño
concurrente de categorías y una comprobación de importación. Esta última se
resolvió configurando el sumatorio exacto en su fixture y sus 13 pruebas pasan.
Dos comprobaciones
del texto vacío de enlaces de Estado detectaron un cambio propio: se restauró
la frase anterior sin cambiar la consulta. No se declara la calidad global
correcta ni se modifican los archivos concurrentes para ocultar sus fallos.

Una copia aislada de HEAD + archivos de este ticket tampoco puede validar
toda la app: HEAD ya importa contratos Drive que siguen sin seguimiento en
el checkout (`drive_upload_factory.dart`, `drive_upload.dart`) y usa miembros
pendientes de InstallationSyncState. Da 84 incidencias de análisis ajenas a
Movimientos; no se añaden esos cambios al commit de MA-TSK-213.

Los intentos iniciales de pruebas tuvieron bloqueos de archivos SQLite DLL.
La batería específica final se ejecutó correctamente con configuración y
directorio de build propios (`.tools/213-final-test-config`), fuera del sandbox.
Los cachés y logs no se incluyen en el repositorio. Los cuatro arranques
development/test/production/invalid-synthetic pasan por separado con builds
locales independientes. Windows release y APK debug del último código pasan;
la apertura de una app nativa y los lectores de pantalla permanecen pendientes.
