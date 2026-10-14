# MA-TSK-180 · Real anual y registros de origen

Ticket y requisitos MA-TSK-176/177/179 consultados el 2026-10-14 en
`GET http://localhost:4310/api/data`, tablero **My autofinance**. Los tres
requisitos constan terminados. Se conserva EP-001 y la presentación entregada
según EP-026; este ticket añade verificación, sin cambiar motores ni reglas.

## Recorrido reproducible

`test/support/annual_actual_lifecycle_journey.dart` usa `AutofinanceApp`,
`LocalBackupSession`, SQLite en disco y los formularios/listas EP-010 reales.
Solo abre una instalación sintética temporal; nunca la base personal.
Lo ejecutan dos pruebas de widgets, Windows 1440×1000 y Android 412×1000,
y el destino nativo `integration_test/annual_actual_lifecycle_test.dart`.

| Criterio | Evidencia automatizada |
| --- | --- |
| F, céntimos, signos, doce meses y raíces | Enero +1.229,75; febrero +1.099,90; resto cero; año +2.329,65 EUR. Raíces +6.120 / −2.000 / −770,35 / −1.000 / −20 EUR. |
| Origen exacto | Abre los doce totales mensuales, anual, Ocio, Alimentación con directos de padre/hijo/hoja y Sin clasificar. Compara subtotal y conjunto UUID tanto del controlador como de la lista presentada; los dos Café idénticos siguen siendo dos registros. |
| Neto cero | Abre las dos piernas de transferencia compensadas y comprueba importe cero con dos UUID de origen. Las pruebas de fixtures K y de pantalla usan dos cuentas. |
| Captura y edición EP-010 | Cancela alta sin escribir, crea −12,34 EUR en el mes enfocado, descarta edición sin escribir, cambia importe a −15,67 y selecciona categoría por la interfaz. Quita categoría y mueve fecha a marzo y después al año siguiente. |
| Retorno y periodo | Las cifras se actualizan al volver, conserva febrero como mes enfocado y las ramas abiertas; Android conserva meses desplegados. Cambiar fecha ofrece Ver mes sin cambiar el periodo de origen. |
| Borrado | Cancela la confirmación sin cambiar ninguna tabla, confirma y comprueba año vacío cero. |
| Persistencia y catálogo | Cierra y reabre la instalación, compara tablas completas; archiva y reubica la hoja con historia, abre la rama nueva y conserva UUID/totales. |
| Recuperación local | Crea copia, edita desde Movimientos, restaura de verdad, comprueba conexión sustituida, cifras y tablas originales, y reabre. |
| Entidades ajenas | Compara presupuestos y todas las fotos/valores antes y después, incluidas edición, catálogo y restauración. |
| Respuestas tardías y error | Las pruebas existentes de pantalla ejercitan ambos destinos, cambio de año mientras carga, resultado tardío, error/reintento sin falso cero y año vacío. La consulta prueba invalidación durante lectura, overflow y snapshot coherente entre conexiones. |
| Accesibilidad y contexto completo | Las pruebas existentes de pantalla cubren Android 320 px/texto 200 %, 412/840 px, tres niveles, foco, scroll, retorno/Back mediante binding y Windows estrecho/teclado. No equivalen a Back físico ni TalkBack. |

## Corrección de los fixtures entregados

La prueba integrada detectó que J declaraba Alimentación anual −782,35 e
Ingresos +6.080 EUR. Los movimientos de EP-001 dan **−780,35**
(`−770,35 −12 +2`) y **+6.116** (`6.120 −4`), respectivamente.
Se corrige únicamente el manifiesto de MA-TSK-179 y su comprobador; no se
cambian EP-001 ni las cifras de la aplicación. Enero sigue en +1.224,75
y el año J en +2.324,65 EUR. Los directos de enero se separan explícitamente
de los anuales. Se corrige también la explicación de L: su real anual es
2.400 EUR; 28.800 EUR corresponden al presupuesto y quedan excluidos.

`annual_actual_fixtures_test.dart` carga el manifiesto F/J/K/L, crea categorías
y movimientos mediante los repositorios SQLite, vincula alias a UUID y
contrasta meses, raíces, contadores y detalle por rama. L añade los 24
presupuestos sin incorporarlos al real. El oráculo de UUID recorre registros
y el árbol independientemente de los agregados SQL. `verificar.mjs` ahora
calcula raíces y directos F/J desde registros, además de meses y anual.

## Comandos y evidencia del entorno

Flutter 3.47.0 / Dart 3.13.0, comprobados con `flutter --version` y
`scripts/check-toolchain.ps1`. SDK, `toolchain.json` y lockfile sin cambios.

```powershell
node docs/ep-022/fixtures/verificar.mjs
flutter pub get --enforce-lockfile --offline
flutter test --no-pub test/actual_spending/annual_actual_fixtures_test.dart --concurrency=1
flutter test --no-pub test/actual_spending/annual_actual_lifecycle_test.dart --concurrency=1
flutter test --no-pub test/movements/movement_list_test.dart test/wealth/wealth_lifecycle_test.dart --name 'Gestión e informes conservan mes y selección al redimensionar y volver del detalle|Caso D completo en archivo SQLite:' --concurrency=1
./scripts/check-quality.ps1
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
flutter drive -d windows --no-pub --driver=test_driver/annual_actual_lifecycle.dart --target=integration_test/annual_actual_lifecycle_test.dart --dart-define=APP_ENV=test
```

Las cuatro pruebas F/J/K/L y los dos recorridos integrados de widgets pasan.
Windows release y APK debug compilan. Android utiliza el JDK 17 instalado
en `.tools/jdk17-094`; se restaura después la configuración previa de Flutter.
Windows utiliza el Visual Studio instalado; no se instala ni actualiza SDK.

El script de calidad original falla en la consulta a pub.dev dentro del
sandbox. Se repite el mismo script mediante una función local que añade
`--offline` a pub get y `--concurrency=2` a test, sin editar el script versionado.
SQLite/recuperación necesitan el bloqueo de Windows: los recorridos se
ejecutan con permisos ampliados. Un primer intento paralelo de calidad
colisionó con la DLL SQLite ocupada; la ejecución final es secuencial.

El recorrido **nativo Windows pasa**, incluido archivo, reubicación,
restauración real y reapertura (5 min 5 s de ejecución). Se ejecuta en una
copia aislada para no compartir la DLL SQLite de los widgets; fuentes y helper
son los del checkout, con SHA-256 idéntico. Se preparan junctions a los plugins
ya instalados porque la creación de symlinks requiere Developer Mode; no se
cambia esa configuración del sistema. El runner emite el aviso de plugin
integration_test no detectado en Windows; las aserciones del recorrido y el
resultado del driver terminan correctamente con código 0. No se producen
capturas nuevas ni se usa este resultado como aprobación visual.

Formato final: 425 archivos sin cambios; análisis sin incidencias. Las cuatro
variantes de arranque development/test/production/invalid-synthetic pasan
en la copia aislada con las mismas fuentes. La ejecución global termina con
**1.769 correctas y 7 fallidas** (18 min 14 s); no se declara calidad global
correcta.

Seis fallos se reproducen al ejecutar sus pruebas originales de HEAD
`87a55ba`, con solo las ocho fuentes concurrentes iniciales de sincronización
necesarias para compilar la app: recorrido EP-010 Android, retorno de la lista
de Movimientos, recorridos EP-015 Windows/Android y Patrimonio Windows/Android.
El séptimo, Estado mensual Android, pierde un control tras intentar pulsar
Actualizar fuera de la superficie; pasa aislado sobre la misma base de
contraste. No se identifica su causa definitiva ni se declara resuelto.

Se corrigen tres expectativas relacionadas directamente con EP-022: el
retorno de Movimientos identifica el año del informe conservando el mes
enfocado; Patrimonio ya no busca el marcador técnico de Real anual, espera
la lectura real y comprueba ruta, año, mes, resumen y ausencia de escrituras.
No se cambian las pantallas de esos módulos. Las **tres regresiones pasan**
en la verificación dirigida final (1 min 32 s), junto al formato y análisis
repetidos después de actualizar las expectativas.

Los otros cuatro fallos de la ejecución global quedan documentados: EP-010
Android y EP-015 Windows/Android buscan controles de navegación ausentes y
se reproducen en HEAD; Estado mensual Android no falla aislado. No se cambian
sus módulos ni sus pruebas. No se repite la batería global tras corregir las
tres expectativas; se ejecutan las pruebas afectadas y formato/análisis finales.

Una copia de HEAD con **solo cambios propios** pasa las cuatro pruebas de
fixtures, pero la prueba integrada no compila: faltan los archivos ajenos
`drive_upload.dart`, `drive_upload_factory.dart` y contratos de sincronización
que HEAD ya consume. Las comprobaciones de la app/builds/nativo utilizan las
fuentes concurrentes presentes al comenzar; esas fuentes quedan excluidas del
commit de MA-TSK-180. La verificación de la app sobre un checkout limpio queda
limitada por esa entrega de sincronización pendiente de confirmar.

Android nativo queda **sin verificar**: ADB detecta `emulator-5554`, pero
`service check package` devuelve `Service package: not found`; instalar el
APK compilado falla con `Can't find service: package`. No se afirma recorrido
nativo, Back físico ni TalkBack en Android. Los widgets/goldens existentes
y el build no sustituyen esa evidencia ni una aceptación visual humana.

Logs y copia aislada en `.tools/ma-tsk-180-*`, ignorados por Git. El helper
principal y el de la copia nativa tienen el mismo SHA-256. Se excluyen del
commit README, sincronización, fixtures y prototipos concurrentes ajenos a
EP-022. La rama configurada al comenzar es `ticket/ma-tsk-179`, upstream
`origin/ticket/ma-tsk-179`; no se cambia de rama ni se fuerza la subida.
