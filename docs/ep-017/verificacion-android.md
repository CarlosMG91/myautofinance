# MA-TSK-148 · Fotos patrimoniales en Android

Verificación del 2026-10-09. Ticket y épica MA-EPIC-147 consultados mediante
`GET http://localhost:4310/api/data`, tablero **My autofinance**. Los tickets
MA-TSK-074/075/076/077 constan terminados. Se reutilizan el diseño aprobado
MA-TSK-019, EP-001 §4/caso D y el
[guion de EP-009](../ep-009/verificacion-recorrido.md).

No se modifica código de producto, esquema, indicadores, SDK ni lockfile.
La navegación común de EP-016 se usa tal como está entregada. El cambio se
limita al arnés existente, al envío de Back desde el host y a esta evidencia.

## Entorno efectivo

| Componente | Verificado |
|---|---|
| Host | Windows 11, 10.0.26300.9550 |
| Flutter / Dart | 3.47.0 / 3.13.0; `check-toolchain.ps1` correcto |
| Canal local | `user-branch`; doctor avisa, se conserva sin actualizar |
| Java de compilación | Temurin 17.0.20.1+1, configuración Flutter temporal propia |
| Paquetes fijados presentes | Platform API 36, Build-Tools 36.0.0, NDK 28.2.13676358 |
| APK normal (`aapt dump badging`) | compileSdk/targetSdk 36, minSdk 24; paquete com.carlosmg91.myautofinance, 0.1.0+1 |
| Emulador | Android Emulator 37.2.12.0, build 16428233; WHPX disponible |
| AVD / dispositivo | Medium_Phone_API_37.0 / emulator-5554; sdk_gphone64_x86_64 |
| Sistema invitado | Android 17, API 37; CE2A.260420.019 / 15611780 |
| Pantalla | 1080 × 2400 px, 420 dpi; capturas Flutter de 412 × 915 px |
| Renderizado | Sin ventana, `-gpu swiftshader`, sin audio ni guardado de snapshot |

El SDK ahora está disponible: queda superada la ausencia descrita en EP-009.
La configuración habitual selecciona JDK 25; se emplea el JDK 17 ya existente
mediante un directorio `APPDATA` temporal bajo `.tools/148`, sin modificar la
configuración global. Doctor sigue avisando de algunas licencias pendientes;
no se aceptan nuevas licencias ni se instalan paquetes. Los paquetes necesarios
permiten compilar y ejecutar este recorrido.

## Alcance del arnés

`wealth_management_test.dart` sigue llamando a `wealthLifecycleJourney` con
un archivo SQLite temporal, apertura/migraciones y transacciones reales. La
base habitual de la app no se abre. El runner elimina su carpeta sintética al
terminar. Las capturas se extraen de su carpeta privada con `adb exec-out run-as`;
son PNG del `RepaintBoundary` renderizado en Android, sin barras del sistema.

El parámetro opcional `androidBack` no altera el recorrido de widgets ni el
runner Windows. Con `WEALTH_ANDROID_BACK=true`, el runner anuncia un punto de
espera con un identificador único. `verify-wealth-android.ps1` detecta ese punto
en logcat y envía `adb shell input keyevent KEYCODE_BACK` al dispositivo elegido.
La prueba exige el diálogo protector y conservar borrador y SQLite intactos.
No se llama a `handlePopRoute` para acreditar este evento.

Desde el mismo borrador tras el fallo se reintenta la corrección. Se añade al
recorrido nativo la comprobación ya existente en las pruebas de EP-009 de un
movimiento sintético posterior al día 1: las filas de fotos y valores quedan
idénticas. Se cierra SQLite, se descarta la sesión y se monta una nueva sobre
el mismo archivo antes de continuar; se compara íntegramente el estado duradero,
incluido el movimiento, la revisión y las identidades.

La primera ejecución agotó el timeout de seis minutos mientras se ejecutaba
también la suite general. El driver genérico imprimió `All tests passed.` y
devolvió cero aunque el test nativo había anunciado `Some tests failed.`.
Esa ejecución **no acredita el recorrido completo**. Se amplía exclusivamente
el timeout del test nativo a doce minutos. El script exige además el mensaje
nativo `All tests passed!`, rechaza `Some tests failed.` y exige el acuse de Back
del host; el código cero del driver por sí solo ya no basta.

## Comprobaciones

| Paso | Aserciones SQLite y de interfaz |
|---|---|
| Enero completo | Cuenta 6.000, ahorro 3.000, cartera 10.000, deuda 5.000; activos 19.000 y neto 14.000 EUR. |
| Febrero ausente | Sin valores ni totales; no arrastra enero. Cancelar y descartar no escriben. |
| Febrero parcial | Cuenta 6.200 y deuda 4.800; ahorro/cartera pendientes y todos los totales Sin dato. |
| Completar | Ahorro cero registrado, cartera 10.500; activos 16.700 y neto 11.900 EUR. |
| Fallo | Trigger TEMP aborta una escritura tras cambiar otra fila; se revierte todo, incluida revisión/identidades, sin aviso de éxito y con borrador conservado. |
| Android Back | KEYCODE_BACK real muestra Seguir editando / Descartar cambios; seguir conserva la cuenta 6.300 del borrador y no escribe. |
| Reintento / corrección | Retirado el trigger, guardar confirma cuenta 6.300, deuda 4.800, activos 16.800 y neto 12.000 EUR. Enero y los IDs se conservan; referencia siempre día 1. |
| Movimiento | Ingreso sintético +10.000 EUR del 20 de febrero no cambia ninguna fila de fotos/valores, enero ni febrero; marzo sigue ausente. No hay saldo calculado. |
| Cierre / reapertura | Nueva conexión y sesión conservan exactamente el estado y la corrección de febrero a neto 12.000 EUR. |
| Resto de EP-009 | Variante de liquidez, vigencia/baja, fotos ausentes e histórico tras otra reapertura; no se implementan nuevas funciones. |

La ejecución final termina con código cero, `06:35 +2: All tests passed!` del
test nativo y acuse de KEYCODE_BACK del host. Se completa el guion y su limpieza
sin corregir funciones de producto. El driver desinstala la app de prueba al
terminar; las nueve capturas conservadas se extrajeron durante la ejecución.
Las dos capturas finales de baja/histórico no se retienen, pero sus aserciones
figuran en el log completo del recorrido.

Evidencia versionada, exclusivamente sintética:

- [Entorno y APK final](evidencia/entorno-y-apk.txt), con tamaño y SHA-256 del
  APK normal compilado después del test de integración.
- [Recorrido nativo y Back](evidencia/recorrido-nativo.txt), con resultados
  comprobados en céntimos, movimiento y reaperturas.
- [Enero completo](evidencia/01-enero-completo.png),
  [febrero ausente](evidencia/02-febrero-ausente.png),
  [parcial](evidencia/03-febrero-parcial.png) y
  [completo](evidencia/04-febrero-completo.png).
- [Fallo con borrador](evidencia/05-error-con-borrador.png),
  [Back protegido](evidencia/05a-android-back-protegido.png),
  [reintento](evidencia/05b-correccion-reintentada.png) y
  [corrección tras reapertura](evidencia/05c-correccion-tras-reapertura.png).
- [Variante de liquidez del guion original](evidencia/06-liquidez-desde-febrero.png).
- [23 pruebas de fotos y recorrido](evidencia/pruebas-fotos.txt),
  [tres casos de recuperación repetidos](evidencia/recuperacion-repetida.txt)
  y [timeout inicial que no acredita éxito](evidencia/timeout-inicial.txt).

Se revisan visualmente parcial, error, Back y corrección tras reapertura:
pendientes/totales Sin dato, borrador conservado, mensaje sin falso éxito,
diálogo de protección y neto 12.000,00 EUR con referencia 01/02/2026.

## Calidad

`check-quality.ps1` original: versiones, lockfile, formato de 310 archivos sin
cambios y análisis correctos; 1.423 pruebas aprobadas y cuatro fallos. Tres son
de `local_recovery_journey_test.dart` (timeout de 30 segundos y bloqueos SQLite
posteriores); el cuarto es la espera del estado Foto completa en
`wealth_photo_screen_test.dart`. La primera suite coincidió con el emulador.

Repetición aislada de fotos/recorrido: **23 pruebas correctas**, incluido el
caso de salida protegida. Repetición aislada de los tres casos de recuperación
con `--timeout=2m`: **tres correctos**. Análisis tras los cambios sin incidencias;
las cuatro variantes de APP_ENV pasan y los casos EP-001/EP-008 terminan con OK.
No se reproduce un defecto de producto que justifique modificar su código.

Repetición completa, ya sin emulador: **código cero**, formato de 310 archivos
sin cambios, análisis sin incidencias, **1.427 pruebas correctas** en 6 min 24 s
y cuatro variantes de APP_ENV correctas. Se utiliza el wrapper local ya usado
en EP-009, `.tools/077-check-quality.ps1`, que añade exclusivamente
`--timeout=2m` a `flutter test`; no se cambia el script de calidad ni las pruebas
de otros tickets. [Resumen de ambas ejecuciones](evidencia/calidad.txt).

El guard del script Android también se contrasta contra el log real del primer
timeout: lo rechaza aunque el driver devolviera cero. Sintaxis PowerShell,
enlaces de evidencia, cabeceras/dimensiones PNG y `git diff --check` correctos.
`toolchain.json` y `pubspec.lock` permanecen intactos.

Las verificaciones se ejecutan sobre el checkout actual, incluidos los cambios
concurrentes de README/sincronización; estos quedan fuera de la entrega. La
publicación utiliza la rama configurada `ticket/ma-tsk-113`, con solo el arnés,
script, informe, evidencia y referencias de MA-TSK-148, sin forzar push.

## Reproducción

Con Flutter y Android configurados según `toolchain.json`, JDK 17 seleccionado
y un dispositivo sintético autorizado o el AVD arrancado:

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter doctor -v
flutter pub get --enforce-lockfile
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
./scripts/verify-wealth-android.ps1 -AndroidId emulator-5554
flutter test --no-pub --timeout=2m test/wealth/wealth_photo_screen_test.dart test/wealth/wealth_photo_management_test.dart test/wealth/wealth_lifecycle_test.dart --reporter expanded
./scripts/check-quality.ps1
node docs/ep-001/verificar-casos.mjs
```

El script admite `-AdbPath` y `-EvidenceDirectory`. No instala SDK, inicia AVD,
acepta licencias ni cambia JDK. Los logs completos locales quedan en `.tools/148`.
El APK normal está en `build/app/outputs/flutter-apk/app-debug.apk`, ignorado por
Git. Compilar de nuevo el APK normal después de `flutter drive` evita entregar
el binario cuyo punto de entrada es el test de integración.

Se acredita una ejecución automatizada nativa en este emulador. La entrada de
texto usa `testTextInput.register`, como EP-009; no se acredita IME/teclado real,
TalkBack, otro Android, teléfono físico, cierre forzado del proceso ni un
recorrido manual humano. Cierre/reapertura significa conexión SQLite y sesión
de la app recreadas sobre el mismo archivo dentro del proceso de pruebas.
