# MA-TSK-156 · Verificación de propuesta y sustitución

Verificación del 2026-10-10 sobre la propuesta entregada por MA-TSK-150–154,
con datos exclusivamente sintéticos y SQLite de archivo. Se usa el ticket
completo facilitado por el usuario, EP-001 §3/caso H y el diseño aprobado
de EP-002/MA-TSK-153. No se cambia código de producto, esquema, SDK ni lockfile.

## Recorridos y referencias

`test/support/budget_proposal_acceptance_journey.dart` ejecuta el mismo contrato
financiero en el host y en las dos plataformas nativas. Importa los 10 reales
y 48 presupuestos del CSV sintético EP-001, usando su signo normalizado y
registrando huella, nombre y procedencia. La copia portátil del CSV permite
ejecutarlo en Android sin depender de rutas del PC; una prueba comprueba su
igualdad con `docs/ep-001/historico-ejemplo.csv`, normalizando solo CRLF/LF.

El recorrido visible de `integration_test/budget_proposal_test.dart` añade
cancelación completa de generación y comprueba que no modifica destino,
presupuesto fuente ni revisión. Conserva edición de enero Alimentación a
−370,00, desglose a Supermercado, cancelación de confirmación por Escape/Atrás,
autorización expresa de sustitución y reapertura SQLite.
`integration_test/budget_proposal_acceptance_test.dart` ejecuta ese recorrido
y el contrato financiero completo. No usa la base personal; crea una carpeta
temporal bajo el directorio de pruebas y verifica su ruta antes de eliminarla.

| Criterio | Evidencia automatizada |
|---|---|
| Caso H completo | Las 60 propuestas raíz/mes coinciden con los importes aprobados; enero/febrero y los ceros posteriores. Presupuesto fuente: 48 partidas intactas. |
| Sumar antes de redondear | −100,01 + 100,00 en descendientes produce neto −0,01 y propuesta −10,00, también con descendiente archivado bajo raíz activa. |
| Cero, ausencia y signo | Mes con dos reales compensados y mes sin reales producen cero explícito; se distinguen por cantidad de movimientos. Ingreso negativo y salida positiva bloquean guardar sin revisión. Editar invalida la revisión. |
| Exclusiones | Sin clasificar y raíz archivada se conservan como exclusiones no bloqueantes; no reciben partidas. El selector de desglose omite descendientes archivados. |
| Edición y desglose | Enero Alimentación −370,00 pasa al hijo y retira el padre únicamente de enero; febrero conserva su propuesta raíz −430,00. |
| Padre e hijo inválidos | Revisión del borrador con ambos rechazada sin ninguna escritura; el repositorio mensual EP-011 también rechaza añadir el padre al destino guardado. |
| Cancelar y autorizar | Calcular, editar, descartar sesión, comparar, cancelar o aportar confirmación incorrecta no cambia ninguna tabla ni revisión. La UI cancela tanto propuesta como confirmación. |
| Sustitución exacta | Comparación de cinco filas: dos retiradas, dos altas y una actualización. Solo se incluyen Alimentación enero/febrero e Ingresos enero. Raíz archivada, Alimentación marzo, año fuente y 2028 quedan idénticos. |
| Datos concurrentes | Otra conexión cambia una partida destino sin incrementar revisión global. Guardar detecta datos obsoletos, conserva el presupuesto concurrente y no pisa la edición −370 del borrador. Regenerar/revisar es explícito. |
| Procedencia | Actualizar Ingresos conserva UUID, importRowId, batchId, ordinal, concepto y discrecionalidad. Todas las filas y lotes de importación, nombre y huella permanecen idénticos, incluidas partidas retiradas. Reimportar la misma huella sigue rechazado. |
| Rollback y reintento | Trigger SQLite real falla en INSERT después de retirar partidas: se revierte la totalidad de tablas y revisión. Retirar el fallo permite reintento manual de la revisión. |
| Doble envío | Dos guardados simultáneos de una revisión devuelven el mismo acuse y una sola subida de revisión. Repetir el éxito no escribe ni duplica partidas. |
| Protección y persistencia | Comparación completa de todas las tablas salvo presupuestos/revisión, y comparación exacta de presupuestos ajenos al ámbito. REAL, cuentas, fotos e importación intactos. Tras cerrar y abrir, todas las tablas coinciden; calcular de nuevo comienza sin borrador ni revisión de signos persistidos. |

Además se reutilizan las pruebas existentes del motor, editor, guardado y UI:
límites int64, redondeo positivo/exacto, profundidad tres, categorías archivadas,
cambios de reales/árbol/dataset, carreras WAL, fallos DELETE/UPDATE/INSERT/revisión,
doble envío en pantalla y relevo de la base activa. La batería general incluye
las regresiones EP-010/011 de gestión, lotes, formularios, consultas, importación,
lecturas y recorridos de archivo con interfaces Windows/Android.

## Ejecución real

Flutter 3.47.0 y Dart 3.13.0 comprobados con `flutter --version` y
`scripts/check-toolchain.ps1`; `flutter pub get --enforce-lockfile` correcto.
Para Gradle se utiliza Temurin 17.0.20.1 mediante configuración temporal privada
del ticket en `.tools/ma-tsk-156-flutter-config/.flutter_settings` y `APPDATA`.
No se modifica la configuración global. Android dispone de Platform 36,
Build-Tools 36.0.0 y NDK 28.2.13676358.

```powershell
flutter test --no-pub test/budget/budget_proposal_acceptance_test.dart
./scripts/check-quality.ps1
flutter test --no-pub -d windows integration_test/budget_proposal_acceptance_test.dart --dart-define=APP_ENV=test
flutter drive -d windows --profile --driver=test/support/budget_native_driver.dart --target=integration_test/budget_proposal_acceptance_test.dart --no-pub --dart-define=APP_ENV=test
flutter test --no-pub -d emulator-5554 integration_test/budget_proposal_acceptance_test.dart --dart-define=APP_ENV=test
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

- Calidad completa: correcta, 327 archivos con formato correcto, análisis sin
  incidencias, **1.510 pruebas correctas** y las cuatro variantes de APP_ENV.
  Incluye las dos pruebas nuevas del host. Análisis dirigido posterior del
  recorrido nativo final: cinco archivos, sin incidencias.
- Android nativo: dos recorridos correctos en `Medium_Phone_API_37.0`, con JDK 17.
  La repetición final incluye el nuevo descarte visible de generación.
- Windows nativo: dos recorridos correctos en profile mediante `flutter drive`,
  con Ctrl+Intro, Escape, cancelación completa y reapertura SQLite. Las teclas
  físicas se indican explícitamente: `debugName` no está disponible en profile
  y el simulador anterior dependía de esos nombres. El driver recoge el resultado
  correcto y termina con código 0, aunque el binding advierte que no detecta el
  plugin nativo `integration_test` en Windows.
- Builds Windows release y APK Android debug: correctos con APP_ENV=test.
  El build Windows utiliza Visual Studio Community 2026 Insiders instalado.
  Artefactos locales en `build/windows/x64/runner/Release/` y
  `build/app/outputs/flutter-apk/app-debug.apk`; no se versionan binarios.

Los registros locales permanecen en `.tools/ma-tsk-156-*.log`, fuera del commit.
No se afirma verificación con teléfono físico, lector de pantalla ni Drive.
El emulador utiliza API 37.0; el proyecto se compila con los paquetes Android
fijados, sin actualizar su plataforma objetivo. Doctor advierte del canal local
`user-branch`, Visual Studio Insiders y algunas licencias Android pendientes;
esas advertencias no impiden los builds que se registran aquí.

La ejecución Windows en debug queda sin verificar: Visual Studio Insiders falla
al enlazar `_CrtDbgReport` del CRT. Se verifica el recorrido nativo en profile y
el build de producto en release, sin modificar CMake ni el compilador. Algunos
intentos iniciales de profile coincidieron con la batería del host y no pudieron
reemplazar `build/native_assets/windows/sqlite3.dll`, cargada por esas pruebas.
La ejecución final se hizo después de terminar la batería del host.

## Límites y entrega

MA-TSK-155 figura completado en la petición, pero sus resultados no se encuentran
en este checkout ni en los commits locales disponibles. Se solicitó su ruta o
commit y no se afirma haber leído esa entrega. La referencia utilizada es el
caso H aprobado de EP-001; no se inventan resultados ni se modifica MA-TSK-155.
No hay conector Epic Board disponible en esta sesión, por lo que no se actualiza
el tablero ni se cierra administrativamente la épica.

La rama configurada es `ticket/ma-tsk-113`. El commit de MA-TSK-156 incluye solo
sus pruebas, fixture portátil, ampliación del recorrido nativo y este informe.
Los cambios preexistentes de README, sincronización y otros prototipos quedan
fuera. El HEAD inicial `f8a2dad` ya consume archivos de subida Drive que permanecen
sin confirmar por su ticket: la calidad y los builds se verifican sobre el
checkout compartido con esos archivos presentes. Un checkout limpio del remoto
necesita que el ticket propietario entregue esas dependencias ajenas; no se
incluyen para resolverlo desde MA-TSK-156.
