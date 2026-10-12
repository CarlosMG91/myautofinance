# MA-TSK-209 · Shell adaptable y navegación

Implementación de T06 sobre el catálogo y contrato de T02 y la entrada pública
del kit T05. Se consultaron MA-TSK-209, la épica y los requisitos en Epic Board
(`GET http://localhost:4310/api/data`, My autofinance). T04 y T05 figuran `done`;
se aplica la autorización de implementación del ticket facilitado por el usuario.
No se modifica la evidencia ni se atribuye una aprobación humana nueva a T04.

## Composición y continuidad

`PrimaryNavigation` adapta sesión, guards, rutas y controles a `AfShell` y
`AfPageSlots`. Windows muestra Inicio, Presupuesto, Movimientos, Patrimonio y
Análisis, con Gestión como utilidad. Android muestra los cuatro primeros y Más,
que ofrece Real anual e Indicadores directamente, además de Análisis y Gestión.
Real/Indicadores seleccionan Análisis en ancho Windows y Más en Android.
La agrupación `/mas` permanece accesible en Windows, seleccionando Gestión.

Inicio es un slot de entrada con acceso a la comparación existente mediante
Ver detalle. Su resumen financiero pertenece a T07. Los informes todavía sin
interfaz y Diagnóstico explican su disponibilidad; no presentan cifras de prueba.
Openbank permanece deshabilitado con motivo mientras su recorrido está pendiente.
Gestión reúne los accesos existentes a importación, historial, categorías,
fichas, pendientes, Drive y copias. Movimientos conserva el filtro Sin clasificar.

Patrimonio, presupuesto anual y captura mensual, Estado, Movimientos, Drive
y copias entregan contenido al shell. El formulario mensual conserva su sesión
secundaria independiente. Las pantallas secundarias conservan sus parsers,
controladores y guards de edición existentes. El rediseño de sus contenidos
pertenece a T07–T13. No se trasladan consultas ni lógica financiera.

`AfShell` añade dos parámetros opcionales compatibles: `scrollController` y
`backLabel`. El controlador pertenece al contenido. Su árbol mantiene el mismo
tipo e índice del contenido al cruzar 840 px; el reflujo de texto cambia solo
la disposición de navegación. Los controles conservan borrador, foco y posición.
La navegación precede al periodo y contenido en el recorrido de teclado,
también al 200 %. Los elementos tienen icono, etiqueta y selección semántica.

## Rutas y estado

- `/` abre Inicio; `/estado` sigue siendo la comparación mensual completa.
- Se incorporan `/inicio`, `/analisis`, `/mas`, `/gestion` y `/diagnostico`.
- Los aliases estáticos `/presupuesto/detalle`, `/movimientos/detalle`,
  `/patrimonio/detalle`, `/real/detalle` y `/indicadores/detalle` abren el contenido
  completo existente. Los propietarios sustituirán esa composición al entregar
  sus resúmenes. No se reescriben prefijos ni identificadores de registros.
- Se conserva el nombre original y los argumentos de `RouteSettings`, incluidos
  enlaces anteriores. Una URI inválida no publica contexto ni consulta datos.
- `NavigationSession` mantiene capturas por destino en memoria. Al volver aplica
  el periodo de trabajo, conserva filtros compatibles y descarta posición/foco
  de un periodo anterior. Nada de esto se guarda en SQLite o Drive.
- Movimientos distingue rango derivado del periodo y rango propio. El rango
  propio sigue visible y Usar mes seleccionado exige resolver filtros sin aplicar.
  No se transforma un rango anual de movimientos en el mes enfocado.
- La observación de rutas publica contexto junto con la navegación; Back restaura
  la captura. Volver, Escape y Alt+Izquierda usan el retorno y guards existentes.
  Los guards rechazados o fallidos permiten reintentar; una respuesta tardía no
  sustituye una elección posterior. Seleccionar el padre desde la captura permite
  regresar al principal aunque ya comparta su selección visual.
- Guardar fuera del periodo conserva el origen. Solo pulsar Ver mes abre el mes
  guardado; hacer Back recupera el rango, periodo y foco originales.

La restauración del scroll de Movimientos espera dimensiones válidas y una ruta
visible. Una respuesta de lectura de una lista cubierta por un editor no roba
foco ni intenta leer límites de un viewport todavía sin layout.

Sin base activa, el arranque crea una única ruta de copias locales. No hay informe
debajo ni navegación financiera disponible. Las operaciones en curso conservan
su bloqueo de retorno y restauración. Entrar o cambiar destino no autoriza
subidas, descargas, restauraciones o escrituras.

## Verificación

Los casos usan datos sintéticos y dobles o SQLite desechable. Las pruebas de
navegación y periodos comprueban selección, contexto, aliases, guards, reintento,
capturas, foco y scroll entre 320, 412, 839, 840, 1024 y 1440 px. Los recorridos
históricos verifican guardado/cancelación, categorías, fotos, importación,
presupuesto anual, navegación secundaria, recuperación y ausencia de mutaciones
al visitar destinos. Se adaptaron los localizadores a iconos, agrupaciones y
acciones visibles, conservando las comprobaciones de datos y persistencia.

El 2026-10-12 se verificaron Flutter 3.47.0/Dart 3.13.0 y el lockfile fijado.
`node docs/ep-001/verificar-casos.mjs` conserva los 48 presupuestos, 10 reales
y los resultados del contrato. Las 42 pruebas de presupuesto, pendientes y
periodos también pasan en ejecución secuencial. Una ejecución general anterior
agotó el tiempo al cerrar SQLite en el recorrido de presupuesto Windows; la
repetición de ese recorrido pasó en ambas plataformas, sin cambiar persistencia.
La ejecución completa final de `./scripts/check-quality.ps1` pasó: 389 archivos
sin cambios de formato, análisis sin incidencias, 1681 pruebas y los cuatro
arranques con `APP_ENV=development/test/production/invalid-synthetic`.
También pasaron `flutter build windows --release --no-pub
--dart-define=APP_ENV=test` y `flutter build apk --debug --no-pub
--dart-define=APP_ENV=test`, usando el JDK 17 y SDK Android fijados. La configuración
de Flutter para este build es local a `.tools`, sin cambiar la configuración global.

`test/navigation_shell_visual_test.dart` carga las fuentes, aplica la escala
real del sistema y compara cuatro goldens en `test/shell_goldens/`: Windows,
Android y dos posiciones de scroll a 320 px/texto 200 %. Las imágenes proceden
del renderizador Flutter y se inspeccionaron visualmente. Son pruebas de widgets,
no capturas de aplicaciones instaladas. TalkBack/Narrador, Back del dispositivo
y la revisión nativa integral de las cinco pantallas siguen siendo evidencia T14.

## Propiedad de la entrega

Se completó la implementación previa local de este mismo ticket, identificada
por sus scripts y registros `.tools/ma-tsk-209-*`. Se incluyen solo composición,
navegación, adaptadores de contenido y sus pruebas/documentación. README, backend
Drive, subida validada y prototipos de otras épicas encontrados al inicio quedan
fuera del commit. No se cambia SDK, lockfile, esquema o contratos financieros.

La base Git anterior ya referencia `lib/app/drive_upload_factory.dart` y
`lib/features/synchronization/domain/drive_upload.dart`, todavía sin seguimiento
al empezar. Las verificaciones del checkout usan esos archivos previos; su entrega
corresponde al trabajo de Drive. No se incorporan a T06 ni se afirma que una
extracción aislada del commit pueda sustituir esa entrega pendiente.
