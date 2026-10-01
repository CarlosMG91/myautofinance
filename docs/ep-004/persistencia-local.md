# MA-TSK-032 · Apertura local y migraciones

## Alcance

`lib/app/data/sqlite/` contiene la infraestructura compartida que app inyectará
en los futuros repositorios por constructor. No depende de funcionalidades ni
cambia el grafo. No abre una base al importar el catálogo ni modifica pantallas
o el arranque técnico actual.

La primera versión física, schemaVersion 1, contiene database_state: singleton,
dataset_id UUID v4 y revision INTEGER no negativa. El modelo de negocio objetivo
sigue siendo el contrato de MA-TSK-031. Sus tablas y restricciones se incorporarán
en sus tickets con versiones físicas sucesivas. Este ticket no implementa
repositorios, revisión de transacciones de negocio ni copias para Drive.

## Uso, ruta y errores

Crear un LocalDatabaseStore, llamar `await store.open()` e inyectar la misma
LocalDatabase en los adaptadores. El propietario debe llamar `await store.close()`
antes de reemplazar archivos o terminar su ciclo de vida. Aperturas concurrentes
comparten instancia y close espera la apertura pendiente. Cerrar varias veces,
reabrir y reintentar tras un fallo son operaciones válidas. La aplicación debe
compartir ese propietario y no abrir conexiones independientes ni permitir
escrituras externas durante una migración.

Se resuelve getApplicationSupportDirectory() y se pasa explícitamente
`<soporte>/sqlite/autofinance.sqlite` a DriftNativeOptions.databasePath en Windows
y Android. Nunca se usa Documents. Los temporales SQLite también usan soporte.
El resolver es inyectable para fixtures; no hay rutas personales codificadas.
Windows hereda los permisos de soporte del usuario; no se añade cifrado.

Drift Flutter mantiene la conexión en un isolate. Cada conexión comprueba el
formato antes de escribir y activa/verifica foreign_keys en setup, antes de crear
o migrar. Se comprueban integrity_check y foreign_key_check al abrir. DatabaseFailure
ofrece códigos estables y mensajes españoles sin SQL ni rutas privadas.
Ningún fallo borra, resetea o sustituye automáticamente la base.

## Versiones

application_id = 0x41464e43 identifica el formato. user_version es la versión
física; dataset_id es el linaje; revision es la revisión financiera. No se
incrementa revision por una migración técnica.

Una base existente se inspecciona en modo solo lectura antes de entregarla a
Drift. Se rechazan versiones futuras, formatos ajenos, objetos SQL inesperados,
estructuras distintas, metadatos inválidos, archivos vacíos preexistentes y
archivos corruptos. La comprobación se repite en la conexión nativa. No hay
migración genérica, downgrade ni recreación por defecto.

La versión 0 admitida es exclusivamente un predecesor sintético definido por
syntheticPreviousSchema: application_id y dataset_id válidos, sin revision.
Nunca hubo una v0 publicada; una base genérica con user_version cero no se acepta.
Antes del paso 0 → 1 se obtiene y valida un respaldo único
`autofinance.sqlite.pre-v1-<uuid>.sqlite` mediante VACUUM INTO, que incluye el WAL.
Se conserva al éxito o fallo, y se expone su ruta técnica al propietario.

La migración usa SQL explícito del esquema anterior dentro de una transacción,
conserva dataset_id y añade revision cero. Valida integridad/FK antes de terminar;
Drift actualiza user_version al éxito. Un error intermedio revierte la transacción.
No se copia solo el archivo principal mientras hay WAL.

El snapshot publicado es drift_schemas/autofinance/drift_schema_v1.json. Las
pruebas comparan creación limpia, snapshot y política de reconocimiento. No
editar snapshots publicados: los cambios requieren incremento de schemaVersion,
pasos consecutivos explícitos, respaldo y pruebas desde cada versión soportada.
Los índices y triggers financieros deberán exportarse al incorporarse.
SQLite y sus sidecars se excluyen de Git.

```powershell
dart run build_runner build
dart run drift_dev make-migrations
./scripts/check-quality.ps1
flutter test integration_test/local_database_test.dart -d windows --no-pub --dart-define=APP_ENV=test
# Con dispositivo o emulador Android disponible:
flutter test integration_test/local_database_test.dart -d <id> --no-pub --dart-define=APP_ENV=test
```

## Verificación del 2026-10-01

Flutter 3.47.0 / Dart 3.13.0 comprobados, sin actualizar SDK. Dependencias añadidas
intencionadamente y resueltas con lockfile. Generación y exportación Drift
completadas. check-quality.ps1 completo: formato, análisis sin incidencias,
35 pruebas y cuatro variantes APP_ENV, más una prueba posterior de objeto SQL
inesperado. git diff --check y actionlint sin errores.

Las 15 pruebas nuevas usan SQLite real y fixtures sintéticos: ruta, reapertura,
FK con inserciones y borrados prohibidos por conexión, aperturas concurrentes,
cierre pendiente, CHECK, snapshot, migración, UUID conservado, respaldo con WAL
pendiente, rollback intermedio, versión futura, bases ajenas/vacías/corruptas,
esquema distinto, metadatos inválidos, bytes intactos al rechazo y reintento tras
error de almacenamiento. No acreditan reglas financieras futuras.

La integración usa path_provider en el destino real y un subdirectorio temporal
sintético de soporte: reapertura, conservación de estado, FK y versión futura.
CI de calidad ejecuta pruebas de host en Windows/Ubuntu. CI de compilaciones
ejecutará también integración Windows y Android con emulador API de toolchain.json.

Se intentaron ambos builds locales. Windows se detiene por falta de enlaces
simbólicos para plugins; Android por ausencia de SDK. No se acredita ejecución
nativa local ni éxito remoto por configurar CI. No hay herramienta Epic Board:
se usa el ticket completo facilitado, sin cambiar el estado administrativo.

## Fuentes

- [Drift y ruta explícita](https://drift.simonbinder.eu/setup/).
- [Migraciones](https://drift.simonbinder.eu/migrations/api/).
- [Exportación](https://drift.simonbinder.eu/migrations/exports/).
- [VACUUM INTO](https://www.sqlite.org/lang_vacuum.html).
- [Emulador CI](https://github.com/ReactiveCircus/android-emulator-runner).
