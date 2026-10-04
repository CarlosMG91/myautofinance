# MA-TSK-085 · Gestión completa e integridad histórica

## Alcance y fuentes

Ticket consultado el 2026-10-04 mediante `GET http://localhost:4310/api/data`,
tablero **My autofinance**. MA-TSK-084 consta `done`; MA-TSK-085 estaba
`in-progress`. Se respetan el [contrato EP-001 §2.1](../ep-001/especificacion.md),
los [casos L–O](../ep-001/casos-referencia.md), la aprobación visual registrada
en [MA-TSK-083](interfaz-categorias.md) y los
[contratos de MA-TSK-084](selectores-lecturas.md).

Se amplía el recorrido de integración existente y se comparte su guion con
las pruebas de widgets. No se cambia la implementación financiera, el esquema
v7, los snapshots publicados, SDK, lockfile, navegación Gestión ni EP-009.
Los cambios concurrentes de sincronización, README y mockup quedan fuera de
esta entrega. No se modifica administrativamente el estado del tablero.

## Recorrido reproducible y evidencia de integridad

`test/support/category_lifecycle_journey.dart` utiliza la aplicación, router,
formularios y selector reales, compuestos con `LocalBackupSession`. La base
SQLite es un **archivo** de una carpeta temporal exclusiva. No hay repositorios
simulados, base personal, OAuth ni tráfico Drive.

`test/movements/category_lifecycle_test.dart` ejecuta el mismo guion en 1440 px
con plataforma Windows y 412 px con plataforma Android.
`integration_test/category_management_test.dart` lo ejecuta en el dispositivo
nativo sin imponer tamaño ni simular plataforma. Crea una carpeta nueva bajo
`category-ui-tests`, obtiene su ruta física y la elimina al terminar. Esto
evita confundir la redirección de Roaming del host empaquetado Windows con una
ruta inválida; no se desactivan las protecciones de persistencia.
La escritura usa la entrada de texto de Flutter Test registrada con un cliente
válido (necesario en profile); no acredita el teclado/IME físico del sistema.

Las categorías se crean mediante interfaz y sus UUID generados se capturan.
Se reproduce el caso L con INGRESOS / SALARIO / IMPUESTOS y su hermana NÓMINA,
más GASTOS. La clasificación de fixtures se hace por los puertos EP-004:
los formularios de movimientos y presupuesto pertenecen a otras épicas.
Los fixtures incluyen salario bruto +300.000 céntimos, retención −60.000,
24 partidas de 2026 (NÓMINA +300.000 e IMPUESTOS −60.000 por mes),
procedencia de un movimiento importado, discrecionalidad y una foto manual
de 900.000 céntimos. Nunca se deriva esa foto de los movimientos.

| Criterio | Aserciones del recorrido compartido |
|---|---|
| Crear tres niveles | Altas por interfaz; raíz de ingreso, herencia y nivel 3; cada alta aumenta revisión una vez. |
| Cifras y UUID originales | Real +240.000; presupuesto mensual +240.000 y anual +2.880.000 céntimos; 2 reales y 24 partidas. Comparación de todas las columnas SQL y del conjunto de UUID de categorías. |
| Renombrar, mover y promover | IMPUESTOS → RETENCIONES; SALARIO bajo GASTOS y luego bajo INGRESOS; promociones desde ambos tipos conservan el tipo previo. Rutas, tipo y agrupación se releen; la raíz anterior deja de devolver los reales trasladados. |
| Signos y ausencia de doble conteo | El salario positivo bajo Salida sigue positivo; impuestos negativos bajo Ingreso siguen válidos. Cada real se devuelve una vez y se agrega una vez por ancestro. `incomeOnly` pasa de 24 a 0 y vuelve a 24 según la raíz actual. |
| Bloqueo de tipo usado | Campo de tipo solo lectura en la raíz con datos de descendientes; el servicio también rechaza una edición con nombre y tipo propuestos juntos. Comparación completa del estado tras rechazo. |
| Ciclo y cuarto nivel | Ciclo al elegir un descendiente; creación bajo nivel 3; traslado de una raíz cuyo subárbol completo quedaría en nivel 4. Ningún rechazo cambia columnas ni revisión. |
| Archivo/reactivación | SALARIO/NÓMINA/RETENCIONES cambian juntos, una revisión por operación. Histórico, cifras y foto permanecen; nuevas asignaciones de real y presupuesto fallan, incluso una partida cero. |
| Selector con archivadas | La referencia histórica se presenta con ruta, tipo y Archivada; el nodo no aparece entre las opciones nuevas. Cancelación no escribe. |
| Reabrir aplicación | Se desmonta el árbol de widgets, cierra SQLite, descarta la sesión y construye otra sobre el archivo: después del archivo, tras rechazo histórico y al finalizar el selector. Dataset, revisión y columnas persistentes se comparan antes/después. |
| Conflicto de mes pasado | Retención −60.000 y GASTOS cero en enero de 2025. Traslado desde 2026 con renombre simultáneo rechazado; mensaje con mes y UUID, borrador conservado, sin renombre parcial, sin revisión ni invalidación. Se verifica de nuevo tras reabrir. |
| Cancelación y contexto | Renombre descartado; confirmación de traslado cancelada; alta desde selector descartada. Un consumidor sintético conserva su misma instancia, periodo/filtro, concepto pendiente y UUID anterior. Alta confirmada vuelve al selector con UUID nuevo y solo se aplica al pulsar Seleccionar. No guarda movimientos. |

Los snapshots excluyen el contador técnico temporal `local_mutation`: se
reinicializa al abrir y no es una revisión de negocio. Incluyen
`database_state` en rechazos/reaperturas y todas las columnas de categorías,
movimientos, partidas, cuentas, liquidez, procedencia y fotos. Durante las
mutaciones de categorías se compara aparte el histórico completo sin árbol
ni revisión, incluidos UUID, signos, conceptos, fechas, cuentas,
discrecionalidad, procedencia y timestamps.

## Regresión y contratos para consumidores

La suite completa conserva los casos numéricos EP-001 y las pruebas de
persistencia anteriores. En particular `category_reorganization_test.dart`
cubre SQL directo, rollback de unidades de trabajo, todos los meses,
archivados, cero, v6 → v7 con respaldo y rollback, linaje y snapshot exportado.
`local_database_test.dart` mantiene las migraciones publicadas anteriores.
Las pruebas existentes de interfaz comprueban navegación desde los cinco
destinos, foco, scroll, expansión y layouts pequeños con texto al 200 %.
El nuevo guion comprueba contexto y persistencia; no sustituye estas pruebas.

Contrato de consumo vigente, sin cambios respecto a
[MA-TSK-084](selectores-lecturas.md):

- `selectCategory` devuelve `CategoryDetails?`. Aplicar únicamente un resultado
  no null; persistir `node.id`. `path` y `node.isIncome` describen el árbol actual,
  no una clasificación histórica congelada. Null conserva todo el borrador.
- `assignmentOptions` ofrece activas. Una referencia histórica archivada se
  muestra y puede conservarse; nuevas asignaciones son revalidadas en SQLite.
- Usar el loader `session.categories` para resolver la conexión actual tras
  reapertura/restauración. No retener repositorios de conexiones cerradas.
- Suscribirse a `categoryInvalidation.changes`, descartar rutas/árbol/agregados
  anteriores y releer tras commit. No-op y rechazo no notifican. Las señales
  no sustituyen dataset/revisión persistentes.
- `CategoryGrouping.aggregate` recibe sumas **directas** por UUID y conserva
  signos. Sumar solo registros directos para el total general; incluir aparte
  Sin clasificar, que continúa siendo UUID null.
- `readMonth/readYear(categoryId: ...)` consulta la rama actual una vez por
  registro. `BudgetRepository.readYear(incomeOnly: true)` sigue la raíz actual,
  incluidos negativos y archivadas. La fórmula y estados del indicador siguen
  en EP-001; este ticket no implementa sus pantallas.

## Comandos de reproducción

SDK fijado: Flutter 3.47.0 / Dart 3.13.0. En esta máquina se añade
`.tools/flutter/bin` al PATH de cada ejecución, sin cambiar configuración global.

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub test/movements/category_lifecycle_test.dart
node docs/ep-001/verificar-casos.mjs
./scripts/check-quality.ps1

# Runner nativo estándar (necesita runtime C++ debug):
flutter test integration_test/category_management_test.dart -d windows --no-pub --dart-define=APP_ENV=test

# Alternativa nativa Windows con driver y runtime C++ de profile:
flutter drive --profile --no-pub -d windows --target=integration_test/category_management_test.dart --driver=test/support/category_native_driver.dart --dart-define=APP_ENV=test --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false

flutter test integration_test/category_management_test.dart -d <id-android> --no-pub --dart-define=APP_ENV=test
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

## Resultado local del 2026-10-04

- Versiones verificadas, resolución con `--enforce-lockfile` sin cambios.
  `check-quality.ps1` completo correcto: formato de 157 archivos, análisis
  sin incidencias, **851 pruebas** y las cuatro variantes de arranque
  development/test/production/invalid-synthetic. Se ejecutó sobre el checkout
  con cambios concurrentes excluidos de esta entrega.
- Verificación de entrega posterior a los ajustes del runner: formato de los
  cuatro archivos Dart sin cambios, análisis completo sin incidencias y los
  **dos recorridos de widgets correctos** (Windows y Android, SQLite en archivo).
  Bundle Windows release correcto en `build/windows/x64/runner/Release/`
  con `APP_ENV=test` y lockfile resuelto previamente.
- El comprobador EP-001 pasa: 48 partidas, 10 reales originales, enero
  +1.229,75 EUR, real anual +2.329,65 EUR, presupuesto anual +13.200,00 EUR,
  casos L/M +2.400,00 EUR al mes y +28.800,00 EUR al año.
- **Windows nativo: recorrido completo correcto mediante `flutter drive
  --profile`**, compilación y ejecución con SQLite en archivo. El runner
  registra una prueba de recorrido y su teardown; finaliza con
  `All tests passed.` y código 0. No equivale a IME físico ni Narrador.
- El runner estándar Windows debug se intentó y sigue bloqueado en el
  enlazador por LNK2001/LNK2019/LNK1120 (`_CrtDbgReport`, `_malloc_dbg`,
  `_free_dbg`, etc.) con Visual Studio 18 Insiders / Windows SDK 10.0.26100.0.
  Se entrega la alternativa profile ejecutada, sin cambiar reglas CMake,
  bibliotecas ni configuración de plataformas.
- Android: el build debug se intentó y falla con `No Android SDK found`.
  `flutter devices` solo detecta Windows y navegadores; `flutter emulators`
  no encuentra imágenes. **APK y recorrido Android nativo sin verificar**.
  La variante de widgets Android utiliza SQLite real en archivo del host,
  pero no acredita ejecución en Android ni interacción táctil/TalkBack.
- Teclado/IME físico, Narrador y TalkBack quedan sin verificar. No se promete
  sincronización, importación completa ni pantallas financieras de otras épicas.

Diagnósticos iniciales resueltos exclusivamente en el runner: carpeta Roaming
redirigida por el host empaquetado y entrada `enterText` sin cliente válido
en profile. Las esperas del guion bombean frames mientras SQLite responde,
antes de esperar el fin de animaciones, para no atascar el selector móvil
en su indicador de carga. No se eliminaron ni relajaron las aserciones.

Logs locales ignorados por Git: `.tools/085-quality-final.log`,
`.tools/085-lifecycle-final.log`, `.tools/085-analysis-final.log`,
`.tools/085-native-windows-profile.log`, `.tools/085-native-windows-debug.log`,
`.tools/085-build-windows.log`, `.tools/085-build-android.log`,
`.tools/085-doctor.log` y `.tools/085-emulators.log`. Se conserva aquí la
evidencia resumida sin rutas personales ni identificadores de dispositivo;
los comandos anteriores permiten repetirla en otro entorno preparado.
