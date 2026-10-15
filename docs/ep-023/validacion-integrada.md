# MA-TSK-188 · Verificación integrada de Indicadores

Se usa EP-001 §6.1 y caso G, el contrato CSV, los contratos MA-TSK-182/183/184,
la vista MA-TSK-186 y los fixtures MA-TSK-187. El 2026-10-15 se consultó
`GET http://localhost:4310/api/data`, tablero **My autofinance**: MA-TSK-188
en curso, MA-TSK-186 y MA-TSK-187 terminados. La rama configurada actualmente
es `ticket/ma-tsk-179`. No se cambia el estado del tablero desde estas pruebas.

La entrega añade pruebas; no modifica entidades, migraciones, cálculo ni UI de
producción. EP-026 sigue siendo la referencia visual. La aceptación visual
humana MA-TSK-217 es independiente de esta verificación funcional.

## Cobertura y resultados esperados

`test/support/indicator_acceptance.dart` conecta el catálogo de producción,
proveedor transaccional, servicios SQLite reales, cálculo exacto, formateador y
`IndicatorScreen`. Cada comprobación verifica el resultado tipado y el widget
renderizado; compara `sqlite_master`, las tablas financieras, revisión y
`total_changes()` antes y después de consultar. No basta con que la pantalla
muestre una cifra ni con que una consulta deje iguales las filas finales.

| Regla | Evidencia ejecutable |
| --- | --- |
| Caso G: 9.000 EUR / (36.000 EUR / 12) | Razón exacta `3/1`; `3,00 meses`, con deuda de 5.000 y cartera media de 10.000 que no alteran el numerador. |
| Febrero ausente y parcial | `foto_ausente`; después `foto_incompleta`, pendientes Cuenta de ahorro y Cartera. |
| Precedencia con ausencias simultáneas | Foto ausente antes que presupuesto incompleto/negativo; foto parcial antes que presupuesto; marzo pendiente antes que total negativo; doce ceros → nulos; doce negativos → negativos. |
| Foto corregida y periodo | Febrero `31/15` → `2,07`, después `21/10` → `2,10`; enero conserva `3/1`. |
| Cero líquido válido | Razón `0/1`, `0,00 meses`, con deuda y cartera aún presentes. |
| Sin redondeo intermedio | Líquidos 1 céntimo e ingresos anuales 7 céntimos, con once ceros explícitos: `12/7`, `1,71 meses`. |
| Cantidades grandes en SQLite | Cada ingreso mensual y el líquido son 900719925474099301 céntimos; suma anual y producto por doce superan int64; resultado exacto `1/1`. Cada importe individual sigue cabiendo en SQLite int64. |
| Presencia por mes | Doce partidas hermanas en enero, una de cero y once negativas: siguen pendientes febrero–diciembre. |
| Clasificación por raíz | Una salida positiva de 999999999 céntimos no altera los ingresos ni el resultado. Signos negativos y ceros de raíces de ingreso sí se incluyen. |
| Extensión exclusiva de pruebas | Se añade `indicador_sintetico_test` con entradas patrimoniales reales y unidad EUR; la misma vista presenta `9.000,00 EUR` junto al colchón. El catálogo de producción sigue conteniendo solo `colchon_emergencia`. Esquema y datos idénticos antes/después. |

El escenario grande de MA-TSK-187 con líquido superior a int64 es un fixture
matemático, no un importe almacenable en una foto SQLite. Se mantiene como
referencia independiente; las pruebas puras de cálculo/formato cubren razones
`BigInt` y la prueba integrada usa importes válidos en el almacenamiento real.
No se amplía ni se falsea el contrato int64 de `WealthReading`.

## Cambios de origen y navegación

Se reutiliza `test/support/indicator_journey.dart`, ejecutable en widget tests y
en ambos runners nativos. Este ticket añade edición real de la partida de
febrero desde el detalle: 3.000 → 4.200 → 3.000 EUR; el colchón cambia
2,10 → 2,03 → 2,10 meses, manteniendo febrero, detalle y foco de retorno.

El recorrido verifica además completar/corregir foto mediante su formulario,
completar marzo desde febrero, liquidez efectiva desde febrero sin cambiar
enero, traslado de Salario fuera de ingreso y de vuelta, alta importada con
procedencia, copia local real, modificación posterior, restauración que
sustituye la conexión y reapertura. La fotografía completa de las tablas y la
revisión vuelve al estado guardado y las consultas no lo alteran. También se
prueban foto y presupuesto abiertos sin pila con retorno a Indicadores.

La importación del recorrido utiliza el repositorio real de lotes con importes
ya normalizados. El lector del CSV EP-001, inversión del signo, categorías
archivadas/reparentadas, sumas firmadas, meses de suma neta cero y errores
SQLite/overflow se verifican adicionalmente en
`test/indicators/indicator_input_provider_test.dart`. No se atribuye al recorrido
del indicador una selección de archivo ni una transferencia de Drive.

`indicator_screen_test.dart` controla respuestas y errores tardíos al cambiar
mes/año, oculta cifras anteriores durante carga, conserva causa técnica y
prueba reintento sin presentar «sin dato». Son pruebas de widget con entradas
controladas; la coherencia transaccional real se prueba con dos conexiones
SQLite en el test del proveedor. Las pruebas puras cubren toda la matriz de
precedencia y redondeo half-up, incluidos empates y valores grandes.

## Reproducción

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
node docs/ep-023/fixtures/verificar-ma-tsk-187.mjs
flutter test --no-pub --concurrency=1 test/indicators test/architecture_test.dart
./scripts/check-quality.ps1
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
flutter drive --debug --no-pub -d windows --target=integration_test/indicator_acceptance_test.dart --driver=test_driver/indicator_acceptance.dart --dart-define=APP_ENV=test --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false
flutter drive --debug --no-pub -d emulator-5554 --target=integration_test/indicator_acceptance_test.dart --driver=test_driver/indicator_acceptance.dart --dart-define=APP_ENV=test --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false
```

El driver exige las dos fases completadas y guarda metadatos del runner en
`evidencias-ma-tsk-188/{windows,android}.json`. Estos archivos son resultados de
ejecución, no capturas ni aceptación visual. Las 26 capturas nativas previas
siguen identificadas en [MA-TSK-186](vista-indicadores.md); no se regeneran ni se
les atribuye el origen de este ticket. No se usa información personal.

## Ejecución y límites

Registro de ejecución del 2026-10-15:

- Flutter 3.47.0 / Dart 3.13.0 comprobados con el script fijado.
- Resolución del lockfile correcta sin cambiar `pubspec.lock` ni toolchain.
  La consulta inicial a pub.dev sin permiso de red falló; la resolución offline
  y la repetición con red permitida pasaron.
- Los 15 fixtures independientes de MA-TSK-187 pasan su verificador Node.
- Las 102 pruebas dirigidas de Indicadores y arquitectura pasan, incluidos los
  dos recorridos de origen y las dos variantes de aceptación integrada.
- Formato de 450 archivos sin cambios y análisis completo sin incidencias.
- Repetición final de `scripts/check-quality.ps1`, sin builds ni emulador
  simultáneos: formato correcto, análisis sin incidencias (98,8 s) y batería
  general de 10 min 6 s, con **1878 pruebas correctas y tres fallos**. El script
  completo no queda verde. Los fallos son `movement_lifecycle_test.dart`
  (Android) y `pending_lifecycle_test.dart` (Windows y Android), todos por
  `Bad state: No element` al buscar controles de navegación. Son los mismos
  casos documentados y contrastados antes de esta entrega en
  [MA-TSK-182](motor-indicadores.md) y [MA-TSK-183](proveedor-entradas.md).
  Se revisó también el registro local de aquel contraste, sin repetir ni
  atribuir a un HEAD puro la comparación anterior. No hay fallos de Indicadores.
  Los trece fallos adicionales de la tanda interrumpida no se reproducen en
  esta repetición completa.
- Los cuatro arranques `APP_ENV` (`development`, `test`, `production` e
  `invalid-synthetic`) pasan, una prueba cada uno. Se ejecutan aparte porque
  los tres fallos anteriores detienen el script antes de esa fase.
- Dos recorridos funcionales nativos por plataforma, correctos:
  [Windows](evidencias-ma-tsk-188/windows.json) y
  [Android](evidencias-ma-tsk-188/android.json). El contador del runner termina
  en tres porque incluye `tearDownAll`: son dos pruebas funcionales, no tres.
  Windows compiló el runner debug en 64,0 s y ejecutó las fases en 1 min 36 s.
  Android ejecutó las fases en 3 min 48 s. La compilación inicial Android
  atravesó la pausa prolongada del entorno descrita debajo; sus 6373 s no
  representan un tiempo de compilación normal.
- Entrada principal, `APP_ENV=test`: Windows release correcto (182,3 s) y
  APK debug correcto (39,0 s). Windows usa Visual Studio 2026 Insiders
  preinstalado; Android usa JDK 17.0.20.1 y los paquetes fijados. El emulador
  preexistente es API 37; no se ha cambiado plataforma/build-tools 36 ni NDK
  28.2.13676358 de compilación. Se reutilizan configuraciones locales en
  `.tools` para JDK y salidas, sin cambiar ajustes globales.

Las primeras pruebas de recorrido bajo el aislamiento de archivos no pudieron
abrir el almacenamiento temporal. Al repetir con acceso permitido pasaron.
Un intento de prueba mientras seguía cargada la DLL SQLite del intento anterior
falló al sustituirla; se detuvo ese proceso propio y se repitió correctamente.
No se consideran fallos funcionales del producto ni ejecuciones correctas esos
intentos interrumpidos.

Una espera solicitada de 30 segundos devolvió el control tras más de 100
minutos. La primera batería general atravesó esa pausa y acabó con 1865
pruebas correctas y 16 fallos: tres de navegación previos y otros timeouts,
con fallos posteriores en esos archivos. Además había compilaciones
simultáneas, que añadían carga. No se deduce una causa única ni se presenta
esa tanda como una verificación limpia. Se repitió la calidad completa sin
builds simultáneos y con el emulador cerrado; el resultado final se registra
por separado.

Durante Android se observó el diálogo «System UI isn't responding» del
emulador. El runner terminó sus dos fases correctamente; las acciones de
estos recorridos se inyectan desde Flutter, y no acreditan interacción física
ni visibilidad libre de diálogos del SO. Se identificó el diálogo con la
jerarquía UI de Android y se solicitó su cierre. Después se cerró el emulador
iniciado para estas pruebas. La prueba de Back por `adb` pertenece a la
evidencia anterior MA-TSK-186, no a esta nueva ejecución.

No se acredita dispositivo físico, Narrador/TalkBack ni aceptación visual
humana. El checkout es compartido: no se incluyen cambios de sincronización,
README ni propuestas de otras épicas. La descarga limpia sigue dependiendo de
que sincronización confirme `lib/app/drive_upload_factory.dart`, importado por
su factory de reconciliación ya versionada. La verificación de esta entrega
se hace sobre el checkout compartido, no se presenta como build de un HEAD puro.

Los tres archivos de fixtures MA-TSK-187 estaban pendientes de confirmar según
el resultado de ese ticket en Epic Board, por permisos Git/SSH. Se verifican y
se incorporan al cierre como pendientes de esta misma épica expresamente
solicitados por su regla de finalización; no se incluyen pendientes de otras
épicas. El resto de cambios de MA-TSK-182–186 ya estaba versionado.
Los fixtures quedan confirmados y subidos en `9d98ba2`. MA-TSK-188 entrega
únicamente sus pruebas, los dos registros nativos y este informe, sin código
de producción ni cambios de terceros. `git diff --cached --check` correcto;
`toolchain.json` y `pubspec.lock` permanecen intactos.
