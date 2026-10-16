# MA-TSK-192 · Desgloses con filtros locales

## Integración

Se consultaron MA-TSK-192/191 y T05 MA-TSK-208 en Epic Board mediante
`GET http://localhost:4310/api/data`. MA-TSK-191 figura aprobado el
2026-10-15 (`approvedAt=2026-10-15T16:43:54.707Z`). Su suplemento v1 y
EP-026 v1 son la referencia de presentación; no se infiere de ellos la
aceptación visual final de MA-TSK-217.

Se amplían las listas existentes, sin otra lista, editor ni motor financiero:

- Partidas usa `BudgetListReader.readResult` de MA-TSK-190. Permite mes,
  año, rango inclusivo entre años, categoría y directo/rama. Conserva UUID,
  signos, ceros y procedencia. No ofrece cuenta ni Sin clasificar.
- Movimientos conserva consulta, filtros, acciones y formularios EP-010.
  Captura una consulta inicial inmutable para restablecer fecha, cuenta,
  categoría, Sin clasificar, alcance y concepto.
- Ambas listas muestran el informe y ámbito iniciales, el nuevo ámbito local
  y «Restablecer filtros del informe». El contador y subtotal incluyen todas
  las páginas. Partidas pagina el resultado común en memoria, de cien en cien.
  No se convierte a paginación SQL ni a un snapshot fijo frente a escrituras.
- Las lecturas muestran datos actuales. Un aviso explica que pueden diferir de
  la cifra anterior del informe y que restablecer recupera filtros, no datos
  históricos. No se transmite ni se inventa una cifra antigua como vigente.
- Los filtros no cambian las rutas/contextos de los informes. Los formularios
  reciben el ámbito local vigente, incluso tras recomponer/redimensionar la
  ruta. El retorno conserva posición y foco; si el registro desaparece, el foco
  vuelve al encabezado. Se reutilizan las relecturas de EP-019/021/022.
  El encabezado del shell muestra el periodo original y deja el cambio de
  ámbito a los filtros locales; no publica otro periodo global desde el desglose.
- Cambiar ámbito reinicia página/cursor y selección. Generaciones de lectura
  descartan respuestas tardías. Al sustituir la conexión se invalida la
  selección anterior antes de intentar leer, incluso si la lectura falla.
  La revisión SQLite permite reiniciar cursores tras escrituras y rechaza una
  lectura atravesada por una mutación; no añade fórmulas ni tablas persistentes.
- Los errores conservan filtros y origen, retiran filas/agregados válidos y
  permiten reintentar. Si desapareció la categoría inicial, se informa y se
  desactiva su restablecimiento; se puede volver al informe o elegir otro ámbito.
- `BudgetLinks` escribe límites AAAA-MM y admite enlaces anteriores con MM;
  rechaza límites mixtos o inválidos. El mes enfocado de captura sigue siendo
  contexto independiente de los extremos efectivos.

La composición usa `PrimaryNavigation` existente y la entrada pública
`lib/ui/autofinance_ui.dart` (AfCard, AfStatus, AfNumericText y tema común).
Los controles refluyen en móvil y con texto ampliado. No se duplica el shell.

## Evidencia y límites

Las comprobaciones se ejecutan sobre el checkout compartido. Los archivos de
sincronización/documentación que ya estaban modificados al empezar quedan
fuera del commit de este ticket. La aplicación del checkout consume parte de
esa entrega de Drive aún no seguida; los resultados locales no acreditan que
un checkout remoto sin esos archivos concurrentes compile por sí solo.

Los PNG de este ticket son renders de **pruebas de widgets Flutter** con datos
sintéticos y las fuentes Roboto/MaterialIcons del kit cargadas para revisión. No son el mockup HTML,
goldens de referencia ni capturas del runner nativo. Las variantes de plataforma,
tamaño y escala comprueban composición y ausencia de errores; TalkBack,
Narrador y la aceptación humana global EP-026 siguen siendo comprobaciones
independientes.

Las [capturas Flutter](flutter-capturas/) muestran las listas dentro del shell
Windows/Android, el ámbito local modificado y la lectura con texto al 200 %.
Los renders de Movimientos a 412 px conservan el scroll hacia los filtros;
los de 320 px al 200 % corresponden a la pantalla de lista sin shell.
Se revisaron signos, colores real/presupuesto, origen, reflujo, campos y
ausencia de glifos perdidos. La selección del shell sigue al informe de origen.

## Comprobaciones reproducibles

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
./scripts/check-quality.ps1
flutter test --no-pub --dart-define=CAPTURE_DRILLDOWNS=true test/budget/budget_local_filters_test.dart test/movements/movement_list_test.dart
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
node docs/ep-001/verificar-casos.mjs
git diff --check
```

`CAPTURE_DRILLDOWNS` solo genera evidencias sintéticas desde las pruebas en
`.tools/tsk192-renders/`; no interviene en la aplicación. Las compilaciones de
esta entrega usan una configuración Flutter local aislada y JDK 17, sin
modificar el SDK, lockfile ni configuración global. Las ejecuciones SQLite
con archivos requieren permitir los bloqueos nativos del host fuera del sandbox.

La regresión de EP-010 usa la navegación pública vigente de Gestión y conserva
una ruta al reemplazar la lista aunque sea la raíz de la pila. También comprueba
el reinicio del cursor tras una escritura. No cambia las acciones financieras.

## Resultado del 2026-10-16

- Flutter 3.47.0 / Dart 3.13.0 y verificador de versiones correctos. Resolución
  con lockfile estricto correcta, sin cambios en paquetes. El intento inicial
  restringido se resolvió offline; calidad lo resolvió después con acceso de red.
- Análisis final sin incidencias; referencias financieras EP-001 y
  `git diff --check` correctos.
- Regresión final: **51 pruebas correctas** de filtros, apertura mensual/anual,
  retorno, rutas históricas y arquitectura, incluidos **26 casos de las listas**.
  Las cuatro variantes de arranque development/test/production/invalid-synthetic
  también pasan; formato final sin cambios.
- Windows release y APK Android debug con `APP_ENV=test` compilados. El host
  usa Visual Studio 2026 Insiders preinstalado y Temurin JDK 17.0.20.1 local;
  no se afirma haber compilado localmente con Visual Studio 2022.
- `check-quality.ps1` ejecutó formato, análisis y la suite completa:
  **1.895 pruebas correctas y tres fallos** en la pasada inicial. El caso nuevo
  de retorno de partidas tenía un viewport de prueba sin configurar al añadir
  el shell; se corrigió y pasó la comprobación específica posterior.
- Los otros dos fallos son de `pending_lifecycle_test.dart`, Windows/Android:
  el guion EP-015 busca un `PopupMenuButton` en Real anual que el diseño vigente
  ya no presenta (`pending_lifecycle_journey.dart:144`). El mismo fallo consta
  reproducido en la base `020f679`, sin los cambios de MA-TSK-192. No se cambia
  el flujo de Pendientes ni se oculta el fallo de la suite global.
- El fallo de viewport de la pasada inicial queda resuelto en la regresión
  final de 51 pruebas. Los resultados no se presentan como una suite global
  completamente verde. Las reejecuciones finales se hicieron en secuencia
  después de liberar la DLL de SQLite compartida por los procesos de prueba.
- Estado, Presupuesto anual, Real anual, movimientos y formularios reales
  completaron sus recorridos SQLite en las dos variantes de plataforma en esa
  suite. Se conservaron datos firmados, origen, contexto y relectura tras guardar.

No se ejecutaron recorridos nuevos en un dispositivo Android instalado,
Narrador o TalkBack. La evidencia visual entregada es de widgets Flutter;
la aceptación visual humana de MA-TSK-217 permanece independiente.
