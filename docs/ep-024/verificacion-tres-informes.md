# MA-TSK-194 · Verificación conjunta de desgloses

Se consultó Epic Board (`GET http://localhost:4310/api/data`), tablero
**My autofinance**, el 2026-10-16. MA-TSK-192/193 y las vistas/enlaces
MA-TSK-160/161/162, 168/169/170 y 176/177/178 figuran terminados. Se ejercitan
esas entregas originales, las listas EP-010/011 y el kit EP-026 v1. No se
añaden informes, editores, consultas de producto ni fórmulas.

## Pruebas incorporadas

`test/drilldowns/report_source_reconciliation_test.dart` carga SQLite con la
muestra sintética de MA-TSK-193. Para cada categoría, total, mes y año,
contrasta las cifras de los tres motores con los UUID esperados de la muestra
y los registros leídos a través de los enlaces públicos originales. Comprueba
directo/rama, contador y subtotal global con páginas de tres, ausencia de
duplicados, cero neto, vacío, Sin clasificar, categorías homónimas, archivo y
traslado al árbol actual. Las consultas comparten identidad/revisión y no
modifican la revisión. También prueba cuenta C2 y rango entre años para OLD.

La fixture ejecutable está en `test/support/drilldown_reference.dart` y usa
importación real para conservar procedencia. Se corrigieron las contradicciones
de la matriz documental: P07 pasa a febrero para evitar el solapamiento con
P02; R10/R14 son dos movimientos opuestos en lugar de un real cero, rechazado
por EP-010/SQLite. Una categoría inexistente produce error, no un vacío válido.
La muestra ampliada suma presupuesto anual +4.193,00 € y real +3.324,65 €;
se mantiene independiente del CSV de referencia EP-001.

`test/support/report_drilldown_journey.dart` monta `AutofinanceApp` con
`LocalBackupSession` y una instalación SQLite en archivo desechable. El test
de widgets lo ejecuta en variantes Windows (1440 px) y Android (412 px).
`integration_test/report_drilldowns_test.dart` ejecuta el mismo guion en el
runner nativo, sin sustituir rutas ni formularios por marcadores.

El recorrido comprueba:

- Estado → movimientos y partidas, ámbito heredado y relectura tras guardar.
- Filtros locales de categoría/directo/cuenta en reales, edición cancelada sin
  escrituras, edición guardada y retorno con filtros, posición y foco.
- Partidas sin cuenta ni Sin clasificar; edición por formulario EP-011.
- Presupuesto anual → partidas, rango inclusivo entre años, cancelación,
  retorno con posición/foco y restablecimiento del año del informe.
- Real anual → cero neto con dos UUID, vacío y dos Cafés legítimos separados;
  cambio local de periodo y restablecimiento sin cambiar el mes del informe.
- 218 movimientos en tres páginas con subtotal global +3.109,90 €; escritura
  con selección activa, descarte de cursor/selección y relectura actual.
- Restauración real con lista abierta, sustitución de conexión, total/UUID
  restaurados y retorno al informe con su periodo original.
- Metadatos de movimientos y partidas invariantes salvo importe/fecha de
  modificación; procedencia, cuentas y fotos patrimoniales intactas.

La regresión existente sigue cubriendo lecturas tardías, errores, restauración
con lectura fallida y categoría desaparecida en `movement_list_test.dart` y
`budget_local_filters_test.dart`; coherencia ante otra conexión en las consultas
de los tres informes; paginación de más de 200 partidas en
`budget_list_result_test.dart`. Se reutiliza esa cobertura, sin otro motor.

## Comandos reproducibles

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
./scripts/check-quality.ps1
flutter test --no-pub test/drilldowns test/budget/budget_local_filters_test.dart test/movements/movement_list_test.dart test/budget/budget_list_result_test.dart
flutter test -d windows --no-pub --dart-define=APP_ENV=test integration_test/report_drilldowns_test.dart
flutter test -d emulator-5554 --no-pub --dart-define=APP_ENV=test integration_test/report_drilldowns_test.dart
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
node docs/ep-001/verificar-casos.mjs
git diff --check
```

Las pruebas SQLite en archivo necesitan los bloqueos nativos del host fuera
del sandbox. Los builds usan configuración Flutter local aislada, JDK 17 y
los paquetes de `toolchain.json`; no se actualizan SDK ni lockfile. Los logs
locales permanecen en `.tools/tsk194-*.log`, fuera del commit.

## Resultado y límites

Comprobaciones del 2026-10-16:

- Flutter 3.47.0 / Dart 3.13.0 y `check-toolchain.ps1` correctos. Resolución
  estricta del lockfile correcta, sin cambios de paquetes, SDK ni plataformas.
- Formato de 458 archivos sin cambios y análisis estático final sin incidencias.
  Referencias EP-001 y `git diff --check` correctos. Los cuatro arranques
  development/test/production/invalid-synthetic pasan por separado.
- Regresión final de desgloses/filtros/resultados: **35 pruebas correctas**,
  incluidos el contraste completo de cifras/UUID y los dos recorridos SQLite
  Windows/Android. También pasan carga tardía, lectura fallida, invalidación
  durante lectura y restauración con categoría inicial desaparecida.
- Runner nativo **Windows debug**: recorrido completo correcto; runner nativo
  **Android debug**, emulador x86_64 API 37: recorrido completo correcto.
  Android compila con API 36 del SDK fijado. La primera ejecución Android
  rechazó el alias de su carpeta temporal; el guion final usa una instalación
  de prueba canónica bajo soporte, igual que el recorrido nativo de Estado.
- Entrada principal **Windows release** y **APK Android debug**, ambos con
  `APP_ENV=test`, compiladas correctamente. Windows usa Visual Studio 2026
  Insiders preinstalado; no se acredita ejecución local con Visual Studio 2022.
  Android usa JDK 17.0.20.1. No se añade firma de distribución.
- `check-quality.ps1` ejecutó formato, análisis y suite completa:
  **1.899 pruebas correctas y cuatro fallos** en esa pasada. Uno era el selector
  del scroll del guion nuevo Windows: elegía el scroll del menú, cuyo controller
  es nulo; se corrigió y pasa en la regresión final y el runner Windows. Otro
  fue un timeout de `wealth_lifecycle_test.dart` Windows; el recorrido completo
  pasó al repetirlo por separado, sin cambiar Patrimonio.
- Los otros dos fallos son `pending_lifecycle_test.dart`, Windows/Android:
  `pending_lifecycle_journey.dart:144` busca un `PopupMenuButton` que Real anual
  ya no presenta. Son los mismos fallos documentados por MA-TSK-192. Este ticket
  no modifica código de producto ni ese guion. No se afirma que la suite global
  esté verde ni se cambia Pendientes para ocultar la incidencia.

Un intento de regresión paralelo encontró la DLL SQLite cargada por la suite
completa. La ejecución final usó configuración y salida propias, y pasó. Las
pruebas nativas son ejecuciones del runner, no capturas HTML, goldens ni una
revisión visual humana. No se tomaron nuevas capturas como parte de este ticket.

Este checkout ya contenía cambios ajenos de sincronización, incluido código
consumido por la composición de la aplicación pero aún sin seguimiento. Se
mantienen fuera del commit. Los resultados describen este checkout compartido;
no acreditan que un checkout remoto sin esa entrega pendiente compile por sí solo.
La aceptación visual humana MA-TSK-217, Narrador/TalkBack y un teléfono Android
físico son comprobaciones independientes; no se infieren de estas pruebas.
