# MA-TSK-186 · Vista de Indicadores

La ruta `/indicadores` consulta el catálogo y el motor reales; `/indicadores/detalle`
presenta las entradas y los motivos de las definiciones. Producción publica
exclusivamente `colchon_emergencia` v1. No hay configuración de fórmulas,
umbrales, consejos ni resultados financieros persistidos.

## Contrato y presentación

- `IndicatorEvaluation.inputs` conserva las entradas de la misma lectura que
  produjo el resultado. La vista no hace una segunda consulta para sus cifras,
  ni deduce valores, motivos o destinos de los textos formateados.
- `createIndicatorSource` compone `IndicatorCatalog.v1`, el proveedor SQLite
  EP-023/183 y `EmergencyCushionCalculation`. `LocalBackupSession.indicators`
  resuelve la conexión activa en cada lectura, incluida la restauración.
- `IndicatorScreen` recibe loader, mes, shell, callbacks y posición por constructor.
  Recorre el catálogo y renderiza `CalculatedIndicator` / `UnavailableIndicator`.
  La fórmula y explicación del colchón son presentación específica de su definición;
  otra definición registrada se presenta sin añadir controles ni modificar entidades.
- Líquidos, ingreso anual y promedio se presentan desde entradas tipadas. El
  promedio visible se redondea a dos decimales, pero la razón del motor conserva
  céntimos y `BigInt` sin redondeo intermedio. `0,00 meses` es un valor calculable.
- Los cinco motivos mantienen códigos/textos y precedencia EP-001. Las ausencias
  enumeran fichas o meses pendientes; un año incompleto no se presenta como total.
  Carga y fallo técnico ocultan cifras anteriores; el fallo conserva causa y reintento.

Se reutilizan `AfShell`, tema/Roboto/tokens, `AfCard`, `AfValueRow`,
`AfNumericText`, `AfStatus`, acciones y periodo compartido de EP-026 T05/T06.
La tarjeta es la entrada principal; el detalle explica entradas y precedencia.
No se copia lógica ni servicios del HTML.

## Navegación, actualización y protección de datos

`IndicatorOrigin` valida un origen local con mes/año, resumen/detalle, scroll y
foco. Lo consume `SessionLocation` y se permite explícitamente en `BudgetOrigin`.
Resumen y detalle conservan también rama/alcance/concepto de origen, incluso
al reconstruir el resumen desde un detalle abierto sin pila; esos metadatos
no restringen la consulta global del indicador.
Los enlaces abren foto del mes y captura mensual existente del año/mes pendiente;
no dependen de la matriz EP-021. Con pila se restaura el origen; sin pila los
parsers reconstruyen el destino y su contexto. Back de la captura mensual usa
el retorno propietario también sin pila, manteniendo su guard de borrador.

Cada consulta lleva una generación. Cambiar mes/año o cubrir la pantalla invalida
las respuestas anteriores. Al volver se resuelve de nuevo el loader y se releen
datos; no se conserva un motor ligado a una conexión sustituida. La invalidación
existente de categorías/importación/restauración y la reanudación de la app
también releen. La posición se conserva y limita al contenido actual; se restaura
el foco de la acción o el encabezado si esa acción ya no es necesaria.

Consultar no crea fotos, presupuestos ni movimientos, no guarda resultados y no
accede a Drive. Las escrituras de los formularios, importación y restauración
conservan sus servicios y confirmaciones de origen.

## Fuentes y autorización

Se leyeron EP-001 §6.1/caso G, contratos del motor/proveedor/cálculo y suplemento
EP-023/185, contrato de shell/contexto, kit Flutter y prototipo global EP-026.
Se consultó `GET http://localhost:4310/api/data`: tablero **My autofinance**,
MA-EPIC-181, MA-TSK-186 y dependencias 183/184/185, todas `done`. La instrucción
actual del usuario autoriza implementar este ticket. El documento local de 185
todavía dice «pendiente»; no se altera ni se inventa evidencia humana literal.
La aceptación visual final MA-TSK-217 sigue siendo independiente.

## Verificación reproducible

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub test/indicators test/architecture_test.dart
./scripts/check-quality.ps1
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
flutter drive --debug --no-pub -d windows --target=integration_test/indicator_screen_test.dart --driver=test_driver/indicators.dart --dart-define=APP_ENV=test --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false
./scripts/verify-indicators-android.ps1 -AndroidId emulator-5554
```

El último script utiliza el mismo target/driver y envía un `KEYCODE_BACK` real
cuando el runner Android publica un marcador único. No usa datos personales.
`test_driver/indicators.dart` conserva las capturas nativas y metadatos de origen
en `flutter-capturas`; el tamaño de superficie y texto se fuerzan para comparar
escenarios, sin confundir las capturas con el HTML aprobado.

| Cobertura | Prueba |
| --- | --- |
| Catálogo, entradas, fórmula, cinco motivos y cero | `test/indicators/indicator_screen_test.dart` |
| 320/412/1440, texto 100/200 %, teclado y detalle | Mismo test; los siete estados a 320/200 en runner nativo |
| Precisión con promedio menor de un céntimo | Presentación de `12/7`: `1,71 meses` |
| Respuestas y fallos tardíos al cambiar año/mes | Completers controlados, resultado anterior oculto durante carga |
| Error con causa y reintento | Fallo de lectura independiente de «sin dato» |
| Extensibilidad sin UI por ID para el resultado | Definición y cálculo sintéticos exclusivos de test |
| Foto 6.200 → 2,07; corrección 6.300 → 2,10 | `test/support/indicator_journey.dart`, formularios reales SQLite |
| Marzo pendiente desde febrero y retorno | Captura y alta de presupuesto existentes; conserva detalle/foco/origen |
| Liquidez histórica, árbol actual, importación y restauración | Mismo recorrido compartido Windows/Android; conexión sustituida y reapertura |
| Consultas sin escritura | Comparación de todas las tablas financieras y revisión antes/después |
| Enlace secundario sin pila y Back | Foto y captura mensual reconstruyen el origen de Indicadores |

Los resultados finales de ejecución y los límites se registran a continuación.

## Ejecución del 15 de octubre de 2026

- Flutter 3.47.0 / Dart 3.13.0 comprobados. Resolución del lockfile correcta,
  sin cambiar SDK, paquetes ni `pubspec.lock`. El primer intento sin red falló
  al consultar pub.dev; se resolvió offline y la calidad general volvió a resolver
  con acceso permitido.
- **159 pruebas correctas** de Indicadores, contrato histórico de navegación,
  categorías, captura mensual, enlaces presupuestarios, foto y arquitectura.
  Incluyen los dos recorridos SQLite Windows/Android y retorno sin pila.
- Tras la revisión visual del encabezado y la unidad, **52 comprobaciones** de
  presentación y cálculo pasaron de nuevo: estos casos se solapan con la batería
  anterior, no se suman como pruebas distintas.
- **Dos recorridos nativos por plataforma**, correctos: recorrido real completo y
  siete estados a 320 px / 200 %. Back Android procede de `adb KEYCODE_BACK`, con
  foco de Autofinance comprobado en el host y retorno al resumen verificado por
  el runner. [Registro del host](flutter-capturas/android-back.txt).
- [26 capturas y galería](flutter-capturas/index.html), con metadatos del runner,
  dimensiones y SHA-256 en [manifiesto](flutter-capturas/manifiesto.json).
  `node docs/ep-023/verificar-capturas.mjs --check` exige trece imágenes por
  plataforma y siete hashes diferentes para los siete estados compactos.
  Se inspeccionaron resúmenes, detalle y muestras de cero/ausencias ampliadas
  contra el suplemento EP-023 y el kit/prototipo EP-026.
- Windows release y APK debug de la **entrada principal final** con `APP_ENV=test`:
  correctos. Windows usa el Visual Studio 2026 Insiders preinstalado; Android usa
  JDK 17.0.20.1 y paquetes fijados en `toolchain.json`. El runner Android usa el
  emulador API 37 preexistente; la compilación sigue usando plataforma/build-tools
  36. Configuración de JDK/build de pruebas aislada en `.tools`, sin cambiar
  configuración global. No hay validación en dispositivo físico.

Los primeros intentos paralelos de pruebas/builds bloquearon la DLL SQLite y
provocaron timeouts. La verificación afectada se repitió sin esos procesos
simultáneos. El emulador presentó un diálogo ANR de System UI que interceptaba
Back; tras cerrar ese diálogo, se repitió el recorrido y el Back real pasó.
El script comprueba el foco para no atribuir una tecla interceptada a la app.
Las capturas conservadas corresponden a las ejecuciones correctas finales.

La aceptación humana final MA-TSK-217 y lectores de pantalla Narrador/TalkBack
no se acreditan con estas pruebas ni capturas.

### Integración del checkout compartido

La verificación funcional y los builds se hicieron con el checkout compartido.
Se preservaron y excluyeron de la entrega el fragmento ajeno de README,
sincronización, propuestas de categorías/bandeja y fixtures ajenos. README solo
añade el acceso a la documentación de esta vista. Hay un bloqueo previo verificable en el
checkout limpio: `lib/app/drive_reconciliation_factory.dart`, ya confirmado en
`28dbe64`, importa `drive_upload_factory.dart`, que sigue sin seguimiento.
La entrega concurrente de sincronización debe confirmar sus dependencias antes
de poder reproducir la aplicación desde una descarga limpia. Este ticket no
incluye ni sustituye esos archivos.

### Comprobación final de la entrega

`scripts/check-quality.ps1` terminó con **1.876 pruebas correctas y tres fallos**:
`movement_lifecycle_test.dart` (Android) y `pending_lifecycle_test.dart`
(Windows y Android), todos por `Bad state: No element`. Son los mismos casos
documentados y reproducidos antes de esta vista en MA-TSK-182/183; se conserva
esa evidencia de contraste, sin atribuir el checkout compartido a un HEAD puro.
No hay fallos en los casos de Indicadores. El script completo no queda verde.

Los 447 archivos pasaron formato sin cambios y el análisis general no encontró
incidencias. Tras reforzar el retorno sin pila, se repitió el análisis de los
dos archivos afectados: correcto. La batería final incluye respuestas tardías
tanto correctas como fallidas, metadatos de origen entre resumen/detalle y dos
definiciones simultáneas en el catálogo exclusivo de prueba.

Se comprobaron de nuevo las 26 capturas nativas conservadas y sus hashes. El
verificador admite CRLF al leer el manifiesto y la galería, para reproducir la
comprobación después de un checkout Windows; los hashes PNG se comparan sobre
sus bytes originales. Las capturas siguen representando la presentación final.

Como el script general se detiene en los fallos previos, se ejecutaron aparte
los cuatro arranques `APP_ENV` (`development`, `test`, `production` e
`invalid-synthetic`): todos correctos. También se recompiló el estado final
de la entrada principal: Windows release (72,7 s) y APK debug (56,3 s), ambos
con `APP_ENV=test`, correctos. Android utilizó el JDK 17 y la configuración
aislada descritos arriba. `toolchain.json` y `pubspec.lock` no cambiaron.
