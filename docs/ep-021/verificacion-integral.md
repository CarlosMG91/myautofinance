# MA-TSK-172 · Matriz anual, edición y persistencia

Ticket y dependencias consultados en Epic Board, tablero **My autofinance**,
el 2026-10-12. Se ejercitan las interfaces entregadas de MA-TSK-168/169,
la consulta MA-TSK-166, los enlaces MA-TSK-170, EP-011 y el periodo EP-016.
EP-018 está disponible y se verifica con su calculador, editor y guardado
existentes. No se añade un servicio de propuesta ni se cambia el contrato
financiero, el esquema SQLite o la interfaz de producto.

## Recorrido reutilizable

`test/support/annual_budget_lifecycle_journey.dart` monta `AutofinanceApp`
con `LocalBackupSession` y SQLite de archivo en una carpeta sintética aislada.
`test/budget/annual_budget_lifecycle_test.dart` ejecuta el mismo recorrido
con plataforma Windows/Android y tamaños 1440/412 px; el destino nativo
es `integration_test/annual_budget_test.dart`. El recorrido usa rutas,
controles y formularios reales; no sustituye la matriz por un consumidor
de callbacks ni usa repositorios de presupuesto falsos.

Los datos proceden de la copia portátil existente de
`docs/ep-001/historico-ejemplo.csv`, contrastada con el archivo original
por las pruebas EP-018. Se interpreta con `HistoricalCsvReader`, se normaliza
una vez mediante `BudgetInput.fromHistoricalCsv` y se guarda por el repositorio
de importación con la huella SHA-256 real. Se añaden una cuenta y una foto
sintéticas para detectar cualquier modificación accidental de entidades ajenas.
La creación y resolución de referencias del importador no son objeto de este
recorrido; se reutiliza su persistencia y las regresiones de importación.

MA-TSK-171 figura `done`, pero su salida de ejecución informa que el entorno
impidió preparar los fixtures. No hay una entrega de ese ticket en este checkout
y no se afirma haberla leído. Las fuentes utilizadas son EP-001 §3/§5.3,
el caso E y el contrato CSV, además de las referencias y pruebas existentes.
La incoherencia administrativa de MA-TSK-171 no se modifica desde este ticket.

| Criterio | Comprobación del recorrido |
| --- | --- |
| Caso E | Doce meses de +1.100,00 EUR; anual +13.200,00 EUR y 48 UUID únicos. Ingresos +36.000,00; vivienda −12.000,00; alimentación −4.800,00; ahorro −6.000,00. |
| Partidas de origen | Cada mes compara su conjunto UUID y suma con el detalle; apertura anual muestra +13.200,00, y Alimentación enero abre −400,00. Retorno conserva periodo y ramas. |
| Alta y cero | Alta desde ausencia en Ocio guarda cero explícito, aumenta el número de partidas sin cambiar el total y persiste tras reabrir. |
| Fallos de escritura | Triggers SQLite reales abortan INSERT, UPDATE y DELETE. Comparación exacta de todas las tablas y revisión antes/después; borrador conservado y reintento manual tras retirar el fallo. |
| Edición PC/Android | Windows confirma la celda; Android abre el formulario EP-011. Corrección de enero a −375,25 actualiza total a +13.224,75 y conserva febrero. |
| UUID y metadatos | Todas las columnas de la partida importada se conservan salvo importe/fecha de edición; concepto «Presupuesto compra» y fila de origen siguen presentes. |
| Conflictos | Crear padre con hija y crear hija con padre rechazan sin retirar registros. Padre enero e hija febrero de 2028 son válidos: anual −15,00, sin reparto del padre. |
| Edición fuera del año | Mover la partida a abril de 2027 conserva el origen 2026. El total 2026 pasa a +13.600,00 y 2027 a −375,25; alternar años no muestra cifras anteriores. |
| Borrado explícito | Cancelar no escribe. Fallo DELETE conserva partida y revisión; reconfirmar elimina tras persistencia. Repetir los bytes CSV rechaza la huella y no resucita la partida, incluso tras reabrir. |
| Archivo y reubicación | Una hoja archivada con once partidas sigue visible con sus antecesores; trasladarla actualiza la ruta a Reubicada / Compra semanal y conserva el total. |
| Neto cero y nombres repetidos | Dos hijos distintos llamados Igual tienen −12,34 y +12,34; el subtotal cero conserva dos UUID y abre ambos registros. |
| EP-018 | Cancelar propuesta conserva todas las tablas; generar y confirmar con el servicio existente vuelve a la matriz 2027. Caso H bajo el árbol actual: +2.310,00 y 84 partidas, incluidos ceros de siete raíces activas. |
| Restauración y reapertura | Crear una copia local, editar Ocio y restaurar mediante el controlador real sustituye la conexión. La matriz vuelve a la cifra de la copia; todas las tablas coinciden y se conservan tras reabrir. |
| Entidades ajenas | Comparación completa de reales, cuentas, liquidez, fotos y procedencia al terminar. Solo categorías se excluyen de esa comparación final porque se archivaron/reubicaron expresamente. |

El total visible de la pantalla se contrasta con importes esperados independientes
en cada fase. Las pruebas existentes de consulta, matriz, tarjetas, enlaces y
periodo completan cobertura de lecturas tardías, base reemplazada con borrador,
campo vacío, doble envío, límites monetarios, rutas inválidas, foco y accesibilidad
de 320 px/texto 200%.

## Comandos y evidencia

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub --concurrency=1 test/budget/annual_budget_lifecycle_test.dart
./scripts/check-quality.ps1
flutter drive -d windows --profile --driver=test/support/budget_native_driver.dart --target=integration_test/annual_budget_test.dart --no-pub --dart-define=APP_ENV=test
flutter test --no-pub -d emulator-5554 integration_test/annual_budget_test.dart --dart-define=APP_ENV=test
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

Flutter 3.47.0/Dart 3.13.0, verificador de toolchain y resolución con
`--enforce-lockfile` pasan, sin actualizar SDK ni lockfile.
Los dos recorridos nuevos del host pasan. `scripts/check-quality.ps1` pasa
completo: **371 archivos** con formato correcto, análisis sin incidencias,
**1.620 pruebas** y las cuatro variantes de arranque development/test/
production/invalid-synthetic.

La primera ejecución global con concurrencia cuatro encontró un timeout
del recorrido existente EP-011 y una carrera del nuevo test Android tras
crear la copia. Se corrigió la espera del test antes de acceder a la tarjeta
y se repitió el script completo con concurrencia dos y timeout por defecto
de dos minutos mediante un wrapper local; no se modificaron el script,
aserciones ajenas o código de producto. La repetición termina con código 0.
Los logs `ma-tsk-172-quality-initial.log`, `ma-tsk-172-quality.log` y
`ma-tsk-172-journey.log` conservan los resultados.

- **Windows nativo:** recorrido completo correcto en profile mediante
  `flutter drive`; el driver recoge «All tests passed» y termina con código 0.
  El binding advierte que no detecta el plugin nativo `integration_test` en
  Windows; se conserva esa advertencia y el resultado del driver en
  `ma-tsk-172-native-windows.log`. No se ha ejecutado Windows nativo en debug.
- **Android nativo:** recorrido completo correcto en el emulador
  `Medium_Phone_API_37.0`, con resultado «All tests passed» y código 0 en
  `ma-tsk-172-native-android.log`. No se ha usado un teléfono físico.

Android usa Temurin **17.0.20.1+1** mediante configuración Flutter privada del
ticket y `APPDATA`/`JAVA_HOME` solo del proceso. El proyecto conserva Platform
36, Build-Tools 36.0.0 y NDK 28.2.13676358. El emulador es API 37.0; no se cambia
la plataforma de compilación fijada. Doctor advierte del canal local
`user-branch`, Visual Studio Community 2026 Insiders y algunas licencias Android
pendientes. Se registran esas condiciones reales en `ma-tsk-172-doctor.log`;
no se actualizan SDK, paquetes o configuración global para ocultarlas.

- **Build Windows release:** correcto con `--no-pub --dart-define=APP_ENV=test`;
  artefacto en `build/windows/x64/runner/Release/myautofinance.exe` con sus DLL
  y carpeta `data`. Log: `ma-tsk-172-build-windows.log`.
- **Build APK debug:** correcto con los mismos parámetros y JDK 17;
  artefacto en `build/app/outputs/flutter-apk/app-debug.apk`.
  Log: `ma-tsk-172-build-android.log`. No incluye firma de distribución.

Los logs locales quedan en `.tools/ma-tsk-172-*`, ignorados por Git. SDK,
bases sintéticas, copias, caches y binarios de prueba no forman parte del commit.

La rama configurada es `ticket/ma-tsk-113`, remoto `origin`. Los cambios
concurrentes de README, sincronización y prototipos quedan fuera de la entrega.
Los checks del checkout compartido consumen dependencias de subida Drive todavía
sin confirmar por su propietario: no acreditan una clonación limpia del remoto
hasta que ese ticket publique sus archivos. No se incorpora ese trabajo ajeno
ni se cierra administrativamente la épica con MA-TSK-171 sin entrega.
