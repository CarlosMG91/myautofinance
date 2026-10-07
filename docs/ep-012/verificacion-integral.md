# MA-TSK-114 · Verificación integral y entrega del núcleo

El 2026-10-07 se consultaron MA-EPIC-106 y MA-TSK-114 mediante
`GET http://localhost:4310/api/data`, tablero **My autofinance**, workspace
coincidente. MA-TSK-112/113 están completados y MA-TSK-108 registra aprobación
explícita del mockup por el usuario. No se modifica el estado del tablero.

## Implementación

Se añade un recorrido compartido en
[`import_lifecycle_journey.dart`](../../test/support/import_lifecycle_journey.dart),
ejecutado como widgets en tablas Windows y tarjetas Android y como aplicación
nativa mediante [`import_management_test.dart`](../../integration_test/import_management_test.dart).
Usa el adaptador JSON sintético entregado en MA-TSK-113, rutas de app,
`LocalBackupSession`, servicios de importación y repositorios SQLite reales.
Cada ejecución recibe una carpeta temporal propia; nunca abre la base personal.
El adaptador continúa exclusivamente en `test/`, sin selección productiva.

Se corrigen dos avisos de análisis en ese adaptador y su prueba (llaves de un
`if` e import no utilizado). No cambian contratos, esquema, pantallas,
SDK, lockfile, lógica financiera, sincronización ni lectores CSV/XLS.

La [guía de integración](guia-lectores.md) concreta responsabilidades,
composición, errores, signos, ordinales, originales, planes de referencia,
consentimiento, resultados y pruebas para EP-013/EP-014. Identifica también
la entrada productiva pendiente: el lanzamiento actual solo se admite en test.

## Cobertura comprobable

| Criterio | Evidencia |
|---|---|
| Base vacía, referencias aprobadas y previsualización sin escrituras | Preparar cuenta/raíz mediante los diálogos, elegir explícitamente No ingreso y cancelar consentimiento. Todas las tablas, revisión y estado temporal siguen idénticos hasta confirmar. |
| REAL Sin clasificar, presupuesto normalizado/cero | Alta mixta de 3 reales y 2 presupuestos; categoría nula, signo original +400,00 → interno −400,00 una vez y partida cero existente. Revisión aumenta una vez. |
| Duplicados legítimos y originales | Café en ordinales 2/3 produce UUID distintos; conserva orden y nombres repetidos de campos originales. Historial ordenado por ordinal. |
| Inválidos y conflictos: todo o nada | Lote vacío, fecha imposible junto a REAL válido, categoría presupuestaria ausente, ordinal repetido y conflicto mensual de padre/descendiente. Cero cambios en todas las tablas. |
| Cuenta obligatoria para banco | REAL con selección global pendiente no se confirma. Elegir UUID desde la pantalla no escribe; luego confirma manteniendo Sin clasificar. |
| Reapertura e historial | Desmontar app, cerrar conexión, crear nueva `LocalBackupSession` y volver a consultar lote/origen desde rutas reales. Todas las tablas persistentes permanecen idénticas. El estado temporal de conexión se reinicia, por lo que se excluye únicamente de la comparación entre conexiones. |
| Repetición exacta tras editar/borrar | Editar un REAL y borrar otro por repositorio; procedencia muestra original separado del dato actual/borrado. Mismos bytes renombrados muestran Ya importado y no cambian ninguna tabla ni recrean destinos. |
| Solapamientos y revalidación concurrente | Otra conexión SQLite confirma otro archivo con concepto equivalente normalizado tras previsualizar. La solicitud obsoleta es rechazada sin cambios; la pantalla exige marcar aviso explícitamente y luego conserva los dos movimientos. |
| Fallo tardío y rollback | Trigger ABORT en metadatos, después de insertar referencias/registros. Rechazo revierte todas las tablas y revisión; conserva sesión/planes y permite reintentar tras retirar el trigger. |
| Doble confirmación | Dos solicitudes simultáneas al confirmador: una carga y una repetición por SHA, sin duplicar registros. Los tests de controlador/pantalla existentes verifican además el bloqueo de doble acción y salida durante Confirmando. |
| Contrato financiero EP-001 completo | Fixture JSON equivalente de 48 presupuestos/10 reales, 3 niveles, marca de ingreso y discrecionalidad. Reapertura, dos Café, sumas mensuales/anuales y repetición sin revisión adicional. No interpreta CSV. |

El fixture financiero está en
[`import_reference_journey.dart`](../../test/support/import_reference_journey.dart)
y se ejecuta también dentro del recorrido nativo de ambas plataformas. Exige:
enero real **+1.229,75 €**, febrero **+1.099,90 €**, real anual **+2.329,65 €**,
presupuesto de cada mes **+1.100,00 €** y anual **+13.200,00 €**. Se transponen
importes, fechas, categorías y discrecionalidad de los casos aprobados; los
bytes y nombres del fixture JSON son propios, no los de un CSV de usuario.

La suite previa de importación complementa este recorrido con ambigüedades,
vigencia, descendientes/planes, SHA falso, int64, cambios de referencias desde
otra conexión, ABORT/IGNORE en cada etapa, confirmadores de dos conexiones,
migraciones, originales inmutables, cursores, lotes antiguos, restauración,
cancelación, accesibilidad y entrada de producción bloqueada. Se ejecuta
junto al recorrido nuevo en la comprobación completa de calidad.

## Reproducción

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
./scripts/check-quality.ps1
node docs/ep-001/verificar-casos.mjs
node docs/ep-012/verificar-mockup.mjs

flutter drive --profile --driver=test/support/import_native_driver.dart --target=integration_test/import_management_test.dart -d windows --no-pub --dart-define=APP_ENV=test

# JDK 17 local; no cambiar configuración global de Flutter ni Java.
$env:JAVA_HOME = (Resolve-Path '.tools/jdk17-094/jdk-17.0.20.1+1').Path
$env:GRADLE_OPTS = "-Dorg.gradle.java.home=$env:JAVA_HOME"
flutter drive --driver=test/support/import_native_driver.dart --target=integration_test/import_management_test.dart -d emulator-5554 --no-pub --dart-define=APP_ENV=test

flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

Las rutas locales del JDK y dispositivo se adaptan a cada máquina. El arranque
del emulador disponible se realiza sin ventana y las pruebas crean únicamente
carpetas sintéticas desechables bajo `import-ui-tests` del soporte de la app.
Los logs locales quedan en `build/import-114-*.log`, ignorados por Git.

## Entorno y límites

Flutter **3.47.0** / Dart **3.13.0**, comprobados con el verificador fijado.
Doctor advierte canal local `[user-branch]` y Visual Studio Community 2026
Insiders; se conservan las versiones existentes. Android compila con API 36,
Build-Tools 36.0.0, NDK 28.2.13676358 y JDK 17; la configuración global de
Flutter prefiere JBR 25, por eso el daemon Gradle se selecciona por operación.
El log de su contexto confirma `javaVersion=17`.

El recorrido Windows debug inicialmente falla antes de ejecutar pruebas por
LNK2019/LNK2001/LNK1120 en símbolos del runtime debug (`_CrtDbgReportW`, etc.).
El recorrido profile sí ejecuta y aprueba todas las comprobaciones por Flutter
Driver. Al finalizar, el plugin emite el aviso de detección de `integration_test`
en escritorio; el driver obtiene el resultado y termina con código cero.
No se acredita ejecución nativa Windows debug.

Android usa el único emulador existente, **Medium Phone API 37.0**, aunque el
build mantiene API 36. No se acredita un teléfono físico ni un dispositivo
API 36. Los recorridos automatizados reinician composición y conexión SQLite
en el mismo proceso; no simulan un cierre forzoso del proceso ni corte eléctrico.
No se acredita inspección manual, Narrador/TalkBack ni parsing de archivos reales.
La accesibilidad y geometría de pantalla se verifican por las pruebas de widgets
existentes, no por esta ejecución nativa automatizada.

Los accesos a pub.dev, cachés, bloqueos SQLite y compiladores requieren ejecución
fuera del sandbox. El intento inicial de pub get dentro del sandbox no pudo
conectar a pub.dev; la resolución posterior con `--enforce-lockfile` fue correcta.
No se actualiza ningún paquete.

## Resultados finales

- `flutter --version`, `check-toolchain.ps1` y `pub get --enforce-lockfile`:
  versiones fijadas correctas y lockfile sin cambios.
- `scripts/check-quality.ps1` completo: formato sin cambios, análisis sin
  incidencias, **1.152 pruebas** correctas con la concurrencia predeterminada
  y las cuatro variantes APP_ENV (development/test/production/valor inválido).
  Esta ejecución no reproduce el fallo concurrente de Patrimonio registrado
  en MA-TSK-112.
- Recorrido de widgets: tablas Windows y tarjetas Android correctos, incluyendo
  fixture financiero completo. Las dos pruebas están incluidas en calidad.
- Recorrido nativo Windows **profile**: correcto, con resultado obtenido por
  Flutter Driver y código cero; duración del guion 1 min 5 s.
- Recorrido nativo Android **debug**, emulador API 37: correcto, con Flutter
  Driver y código cero; duración del guion 2 min 47 s. Incluye SQLite nativo,
  segunda conexión, rollback, reapertura y fixture financiero completo.
- `flutter build windows --release --no-pub --dart-define=APP_ENV=test`:
  correcto, desde `lib/main.dart`.
- `flutter build apk --debug --no-pub --dart-define=APP_ENV=test`:
  correcto, desde `lib/main.dart`, con daemon Gradle JDK 17.
- `node docs/ep-001/verificar-casos.mjs` y
  `node docs/ep-012/verificar-mockup.mjs`: correctos. El comprobador HTML por
  sí solo no acredita layout ni SQLite; el recorrido Flutter descrito sí usa
  pantalla y persistencia reales.

Los avisos debug de Drift por múltiples instancias aparecen al abrir
deliberadamente conexiones/bases independientes; no se comparte un executor
entre ellas y todas se cierran. No se ocultan ni se interpretan como un fallo
de las comprobaciones. Calidad y builds se ejecutan sobre el checkout compartido
incluyendo sus cambios concurrentes; el commit incluye exclusivamente el ticket.

## Entrega Git

Entrega limitada a archivos propios de MA-TSK-114, en la rama configurada
`ticket/ma-tsk-113`, con remoto `origin`. README, cambios de Drive y mockups
concurrentes EP-008 quedan fuera del commit. Sin push forzado ni cambios de
estado en Epic Board. Esta entrega verifica el cierre de EP-012 y deja los
lectores reales para sus épicas.
