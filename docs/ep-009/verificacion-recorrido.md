# MA-TSK-077 · Recorrido integrado de fichas y patrimonio

La comprobación Android posterior del 2026-10-09 se conserva en
[MA-TSK-148 · Verificación nativa](../ep-017/verificacion-android.md), con APK,
SQLite en emulador, Back real y evidencia sintética. La ausencia de SDK y
dispositivo descrita abajo corresponde a la entrega original del 2026-10-04.

Ticket consultado el 2026-10-04 mediante `GET http://localhost:4310/api/data`,
tablero **My autofinance**; dependencia MA-TSK-076 terminada. Fuentes:
EP-001 §4 y caso D, aprobación y entrega EP-002, mockup final y arquitectura
EP-003. Se reutilizan las rutas de producto, `LocalBackupSession`, servicios
de EP-009 y repositorios SQLite de EP-004. No se cambia esquema, contrato,
SDK, lockfile ni código de otras épicas.

## Guion automatizado

`test/support/wealth_lifecycle_journey.dart` ejecuta el mismo recorrido desde
los widgets y desde `integration_test/wealth_management_test.dart`. La base
es un archivo SQLite nuevo en una carpeta temporal de datos sintéticos, con
apertura, migraciones, transacciones y bloqueos reales de la instalación.
Las fichas, fotos, cambios de liquidez y bajas se guardan desde los formularios;
los repositorios se consultan además para comprobar céntimos y estado duradero.
La conexión se cierra, se crea una sesión nueva y se abre el mismo archivo.
La base habitual del usuario no se abre ni se sustituye.

| Paso | Comprobación |
|---|---|
| Base vacía y alta | Sin dato inicial; crear dos cuentas, cartera media y deuda sin liquidez. Cancelar vacío y descartar borrador no escriben. Seguir editando conserva el nombre. |
| Enero | Líquidos 9.000,00; medios 10.000,00; activos 19.000,00; deuda positiva 5.000,00; neto 14.000,00 EUR. |
| Febrero ausente | Sin valores y sin totales, sin arrastrar enero. Deuda negativa rechazada antes de persistir. |
| Foto parcial | Principal 6.200,00 y deuda 4.800,00; cartera y ahorro pendientes; los cuatro totales muestran Sin dato. |
| Completar | Ahorro cero registrado y cartera 10.500,00; líquidos 6.200,00, activos 16.700,00, deuda 4.800,00, neto 11.900,00. |
| Corregir | Principal 6.300,00; neto 12.000,00 y líquidos 6.300,00; referencia día 1, IDs de foto/valores y enero conservados. |
| Variante independiente | Se repone principal 6.200,00; cartera líquida desde febrero: líquidos 16.700,00, neto 11.900,00 y enero intacto. Corregir [febrero, marzo) a media devuelve líquidos 6.200,00. No se modifican valores ni fechas de las fotos. Marzo sin foto sigue Sin dato. |
| Vigencia | Alta de Cuenta nueva en marzo; no se exige antes. Marzo y abril incompletos hasta registrar su cero. Baja inclusiva en abril; mayo no la exige y junio sigue sin foto. Valores históricos marzo/abril conservados. |
| Reapertura e histórico | Comparación íntegra de cuentas, periodos, fotos, valores y estado/revisión de la base. Consultar marzo desde las doce fotos; la ficha cerrada sigue visible. Navegar a Real transmite año/mes sin escribir. |

No se implementa ni acredita el indicador: pertenece a otra épica. Se
verifica su numerador mediante las lecturas patrimoniales existentes.
El comprobador EP-001 conserva las cifras y la variante de liquidez de referencia.
Las pruebas existentes de `account_repository_test.dart` cubren el rechazo
de solapes y huecos de liquidez; no se duplica su implementación.

## Fallos y navegación

Triggers **TEMP** provocan fallos de alta, foto, liquidez y baja en SQLite.
Cada rechazo conserva el estado completo anterior, incluida revisión,
identidades y marcas de tiempo, y mantiene los campos del formulario.
Se comprueba mensaje de error y ausencia de aviso de éxito. En la foto el
fallo llega después de corregir otra fila; en liquidez llega al insertar
después de dividir el periodo; en baja después de ajustar los periodos.
La transacción debe revertir todo. Al retirar el trigger, liquidez y baja
pueden reintentarse desde el mismo borrador.

Tras el fallo de foto se prueba Seguir editando y Descartar cambios; se
conserva la foto previa y se guarda después una corrección explícita.
Cancelar las confirmaciones de liquidez y baja tampoco escribe.
El origen de cada formulario conserva su mes al volver. El guion usa entrada
de texto de prueba, con cliente registrado en el runner nativo: no acredita
el teclado físico ni el IME de Android.

## Reproducción

Con las herramientas de `toolchain.json`, desde la raíz:

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub test/wealth/wealth_lifecycle_test.dart --reporter expanded
./scripts/check-quality.ps1
node docs/ep-001/verificar-casos.mjs

# Windows nativo, reutilizando el driver genérico existente de integración:
flutter drive --profile --no-pub -d windows --target=integration_test/wealth_management_test.dart --driver=test/support/category_native_driver.dart --dart-define=APP_ENV=test --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false

# Android nativo requiere SDK y un dispositivo autorizado o emulador:
flutter test integration_test/wealth_management_test.dart -d <id-android> --no-pub --dart-define=APP_ENV=test

flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

Cada variante de widgets tiene timeout de cuatro minutos para el recorrido
completo; el runner nativo tiene seis. No se cambian tiempos de producto.
Las capturas de widgets se generan optativamente con
`$env:CAPTURE_WEALTH_JOURNEY='1'` y quedan en
`.tools/077-windows-widgets/` y `.tools/077-android-widgets/`. Esa opción usa
una fuente Segoe UI local para hacer legibles ambas variantes en el host;
no acredita la fuente Roboto nativa. La opción no se usa en calidad/CI.
El runner nativo guarda capturas en `wealth-ui-tests/captures-<sistema>/`
dentro del soporte de la aplicación. La carpeta temporal de base se elimina
al terminar, también en error. Capturas y logs quedan fuera de Git.

## Evidencia y limitaciones locales del 2026-10-04

Los dos recorridos de widgets pasan, con plataforma Windows a 1440×900 y
Android a 412×900, y SQLite en archivo. Se generan ocho capturas por variante:
enero completo, febrero ausente/parcial/completo, error con borrador, cambio
de liquidez, baja en abril y consulta histórica tras reapertura. Se revisan
visualmente parcial y error en ambos anchos: tablas/tarjetas, pendientes,
totales Sin dato, campos conservados y error visible. Estas capturas son del
host Flutter; no demuestran ejecución en Android.

Diagnóstico actual: Flutter 3.47.0 / Dart 3.13.0 correctos; SDK local con
advertencia de canal `user-branch`, sin cambiarlo. Visual Studio 18 Insiders
y Windows SDK disponibles. Android SDK ausente, sin AVD ni dispositivo
Android; `flutter devices` solo detecta Windows y Chrome. El acceso a pub.dev
y los bloqueos de persistencia requieren ejecutar fuera del sandbox.

Windows nativo: `flutter drive --profile` termina con código 0 y
`All tests passed.` (recorrido y teardown, 3 min 54 s). Se generan las ocho
capturas del runner real, a 1264×681 puntos en esta ventana. Se revisan
visualmente foto parcial y fallo de foto: pendientes y totales Sin dato,
entradas editadas conservadas y mensaje de fallo sin éxito. La carpeta de
base sintética se elimina al terminar; solo permanecen las capturas.

Windows release: build obligatorio correcto, `APP_ENV=test` y `--no-pub`,
salida `build/windows/x64/runner/Release/`. El build Android debug se intenta
con los mismos ajustes y falla: `No Android SDK found`. No se genera un APK
ni se ejecuta el guion Android nativo; queda preparado para una instalación
con las herramientas y dispositivo necesarios.

La ejecución directa de `check-quality.ps1` pasa formato y análisis, pero
el caso existente de recuperación EP-001 agota su timeout de 30 segundos
en `local_recovery_journey_test.dart`, seguido de un fallo de conexión
cerrada durante la limpieza. La misma limitación está registrada en
MA-TSK-076. La repetición completa termina con código 0: formato de
181 archivos sin cambios, análisis sin incidencias, **924 pruebas** correctas
y cuatro variantes de APP_ENV (development/test/production/invalid-synthetic).
Se ejecuta `check-quality.ps1` mediante el wrapper local
`.tools/077-check-quality.ps1`, que añade únicamente `--timeout=2m` a las
invocaciones de `flutter test`; no se cambia el script ni el test concurrente.
La suite se ejecuta sobre este checkout, incluidos los cambios concurrentes,
que quedan fuera del commit. El comprobador EP-001 termina con OK.
`git diff --check` correcto; `toolchain.json` y `pubspec.lock` intactos.

Logs locales, sin versionar: `.tools/077-journey.log`,
`.tools/077-native-windows.log`, `.tools/077-quality.log` (timeout original),
`.tools/077-quality-final.log`, `.tools/077-build-windows.log` y
`.tools/077-build-android.log`.
No se acredita Narrador/TalkBack, alto contraste, teclado físico, IME,
dispositivo Android ni un recorrido manual humano. Las pruebas previas de
MA-TSK-076 cubren otros anchos y texto al 200 %; este ticket añade la secuencia
integrada, sin afirmar una nueva inspección manual de toda esa matriz.

Solo se publican los cuatro archivos de MA-TSK-077 en la rama configurada
`ticket/ma-tsk-071`. Los cambios concurrentes de README, sincronización y
propuestas de categorías quedan fuera. No se cambia el estado de Epic Board
ni se cierra administrativamente EP-009.
