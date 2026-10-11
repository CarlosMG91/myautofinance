# MA-TSK-164 · Verificación integrada de Estado

Ticket y dependencias consultados el 2026-10-11 en la API local de Epic Board,
tablero **My autofinance**. Prevalecen EP-001 §5.1 y casos B/C/J/K/L,
la entrega visual aprobada EP-002 y los contratos de EP-010/011/016.
MA-TSK-163 figura `done`, pero su salida declara que no pudo ejecutar comandos
y no entregó archivos. Se reutilizan los datos sintéticos comprobables de
`test/support/recovery_reference.dart` y las pruebas numéricas de MA-TSK-158;
no se presume la existencia de fixtures de MA-TSK-163.

## Recorrido reproducible

`test/support/monthly_status_journey.dart` contiene un guion compartido entre
las composiciones Windows/Android de widgets y el runner nativo de
`integration_test/monthly_status_test.dart`. Usa una carpeta temporal propia,
SQLite en archivo, `LocalBackupSession`, repositorios y formularios reales.
No consulta Drive, no usa cuentas personales y no sustituye los servicios
financieros por simulaciones. La limpieza solo afecta a la carpeta sintética.

El guion comprueba:

- Previsto/real agregado/diferencia: enero +1.100,00/+1.229,75/+129,75 EUR y febrero
  +1.100,00/+1.099,90/−0,10, además de Alimentación y Ocio.
- Raíces contraídas y expansión a tres niveles. Todas las filas de referencia
  abren real directo, real agregado, previsto y los dos caminos de diferencia.
  Confronta UUID, número de fuentes y suma en céntimos; los dos Café idénticos
  conservan sus identidades. El total abre todos los registros una sola vez.
- Periodo civil, todas las cuentas, retorno con ramas/scroll/foco y ausencia
  de escrituras al consultar. Febrero sin foto mantiene sus cifras correctas.
- Alta, edición/categorización y borrado de real mediante los formularios de
  EP-010; edición de partida mediante EP-011. Cada retorno relee las cifras.
  Compara las tablas patrimoniales antes/después sin cambiar sus fotos.
- Sin clasificar y sus partidas vacías, cero explícito, neto cero con dos
  fuentes y presupuesto padre sin partida ni prorrateo en el hijo.
- Traslado y archivo con rutas actuales. Crea/restaura una copia local real,
  verifica respaldo previo y reconexión, recupera rutas/importes y elimina
  de la presentación las categorías posteriores a la copia.
- Respuesta retenida descartada al cambiar mes, error del cargador sin
  cifras falsas, reintento y año sin reales ni presupuesto.

Las pruebas existentes de `test/monthly_status` complementan el recorrido con
los signos excepcionales J/K/L, homónimos, distintas cuentas, límites int64,
fallo de persistencia, snapshots concurrentes, enlaces inválidos, retorno sin
pila y accesibilidad visual a 320 px/texto 200 %.

Comandos nativos (tras resolver las dependencias fijadas):

```powershell
flutter drive --profile --no-pub --driver=test/support/monthly_status_native_driver.dart --target=integration_test/monthly_status_test.dart -d windows --dart-define=APP_ENV=test
flutter test --no-pub -d emulator-5554 --dart-define=APP_ENV=test integration_test/monthly_status_test.dart
```

Comprobación de producto con las versiones fijadas:

```powershell
./scripts/check-quality.ps1
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
node docs/ep-001/verificar-casos.mjs
```

## Evidencia y límites

La verificación del checkout incluye cambios de sincronización ajenos que
permanecen sin confirmar, como ya documentaron MA-TSK-160/161. No se incluyen
en esta entrega. La evidencia sobre el checkout completo no acredita una
clonación limpia de HEAD mientras esas dependencias sigan pendientes.
En concreto, HEAD importa `lib/app/drive_upload_factory.dart` desde
`drive_reconciliation_factory.dart`, pero el primero y su contrato
`lib/features/synchronization/domain/drive_upload.dart` no están versionados.
Confirmar esos archivos corresponde a su ticket propietario.

La prueba nativa automatizada se distingue de las variantes de widgets. No
acredita recorrido manual, TalkBack/Narrador, teclado físico, gestos predictivos
ni teléfono Android físico. La restauración se verifica desde el controlador
real con confirmación explícita; no se pulsa su diálogo de interfaz ni se
prueba descarga remota. La lectura tardía/error se provoca en el cargador;
los fallos SQLite reales se verifican en las pruebas de consulta existentes.

El runner nativo usa `onlyPumps`, la política del SDK que representa únicamente
los frames solicitados por el test. El guion bombea frames mientras espera
SQLite y exige que desaparezcan los estados de carga; los guardados/borrados
esperan también su pantalla de retorno. Cada operación SQLite tiene un límite
de 30 s. Se conservan todas las aserciones, sin sustituir las esperas por datos
simulados. El primer intento Android con frames adicionales agotó el límite
global de 12 min durante la edición de partida, antes de verificar borrado y
restauración; no se considera un recorrido correcto. Su log se conserva como
`.tools/164-native-android-timeout.log`, ignorado por Git.

Resultados del 2026-10-11 (logs locales ignorados por Git):

- `scripts/check-quality.ps1`: correcto, código de salida 0. Formato de
  354 archivos sin cambios; análisis sin incidencias; 1.560 pruebas correctas
  en 32 min 51 s, incluidas las dos variantes del guion nuevo. Las cuatro
  configuraciones de APP_ENV también pasan (una prueba por configuración).
  Log: `.tools/164-quality.log`. Las pruebas existentes de movimientos y
  copias emiten avisos Debug de Drift por múltiples instancias; no fallan.
- Build Windows Release de producto con APP_ENV=test: correcto (47,4 s,
  código de salida 0), `build/windows/x64/runner/Release/myautofinance.exe`.
  Log: `.tools/164-build-windows.log`.
- Build APK Debug de producto con APP_ENV=test: correcto (27,2 s,
  código de salida 0), `build/app/outputs/flutter-apk/app-debug.apk`.
  Log: `.tools/164-build-android.log`. Ambos builds usan `lib/main.dart`,
  separados del ejecutable/APK que contienen el runner de integración.
- Recorrido nativo Windows: correcto mediante `flutter drive --profile`,
  2 min 38 s de guion y código de salida 0. Profile compila en 95,7 s.
  Log: `.tools/164-native-windows-profile.log`.
  El aviso «integration_test plugin was not detected» permanece: el driver
  VM Service sí recibe los resultados y termina con «All tests passed».
  No se presenta ese aviso como éxito de instrumentación Windows.
- `node docs/ep-001/verificar-casos.mjs`: correcto; contratos financieros
  de referencia conservados.
- Recorrido nativo Android final: correcto (1 prueba, 6 min 8 s de guion;
  código de salida 0). APK de pruebas compilado en 78,0 s, instalado y
  ejecutado en el emulador x86_64/API 37. La carpeta canónica evita las rutas
  con enlaces internos rechazadas por el restaurador. El emulador iniciado
  para esta entrega se cierra al terminar el recorrido.
  Log: `.tools/164-native-android.log`.

El script `scripts/check-quality.ps1` se ejecuta sin modificarlo. Una función
PowerShell temporal añade `--concurrency=1` a sus llamadas `flutter test`;
el resto de argumentos, el análisis y las cuatro variantes de APP_ENV se
conservan. Evita la contención de las pruebas SQLite del checkout y no cambia
preferencias ni archivos del proyecto.

Doctor confirma Flutter/Dart 3.47.0/3.13.0 y JDK Temurin 17.0.20.1+1;
advierte de canal local `[user-branch]`, licencias Android pendientes y Visual
Studio Community 2026 Insiders (18.11.12224.323), distinto de VS 2022 previsto.
El intento Windows Debug falla con LNK2019/LNK1120 en símbolos CRT como
`_malloc_dbg` y `_CrtDbgReportW`. Se emplea `profile` para el recorrido nativo,
siguiendo la alternativa documentada en EP-014/016, y `release` para el build
requerido. No se cambian SDK, CMake, lockfile ni preferencias globales; APPDATA
del proceso apunta a `.tools/164-flutter-config` para seleccionar JDK 17.
El emulador disponible es x86_64/API 37; compilar con SDK 36 no acredita un
recorrido en emulador API 36. No se aceptan licencias pendientes.
