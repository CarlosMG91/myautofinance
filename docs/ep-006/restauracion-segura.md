# MA-TSK-055 · Restauración segura con respaldo anterior

## Integración y confirmación

`createLocalRestorer(store: store)` compone `LocalRestorer` con el propietario
SQLite único de EP-004 y el mismo directorio privado de soporte que copias y
catálogo. Construirlo no abre SQLite ni contacta Drive. La presentación futura
obtiene confirmación expresa antes de llamar:

```dart
final restorer = createLocalRestorer(store: store);
final result = await restorer.restore(backupId, confirmed: confirmedByUser);
```

`confirmed: false` devuelve `cancelled` sin resolver soporte, tomar bloqueo,
preparar candidatas, abrir conexiones, escribir catálogo ni crear respaldos.
Solo se admiten IDs del catálogo/manifiesto privado; no rutas externas.
Este ticket no implementa pantalla. MA-TSK-058 necesita las aprobaciones de
MA-TSK-019 y MA-TSK-057.

Se usa el ticket íntegro facilitado por el usuario y se contrasta la instantánea
local `.tools/epic-board-read.json`. Esta no acredita el estado actual del tablero
My autofinance; no hay conector disponible y no se cambia su estado administrativo.

## Exclusión, protección e intercambio

1. Obtener `.local-backups.lock`, compartido con creación, validación y catálogo,
   durante toda la operación. Los métodos internos `prepareUnderLock` y
   `capturePreRestoreUnderLock` evitan adquirir recursivamente el mismo bloqueo.
   No son puertos públicos de dominio y requieren al propietario del bloqueo.
2. Bloquear apertura/captura/cierre externos en el store, cerrar admisión a nuevas
   unidades de escritura y esperar las ya admitidas, incluidos sus savepoints.
   Restaurar desde una unidad de trabajo se rechaza. Se mantiene el contrato
   EP-004: todos los repositorios comparten un store y escriben mediante la unidad;
   SQL público queda para infraestructura y fixtures, sin conexiones externas.
3. Preparar la candidata con MA-TSK-054 bajo ese mismo bloqueo y comprobar de nuevo
   sus bytes. Validar la activa existente antes de clasificarla. Si puede abrirse,
   crear y catalogar una automática `preRestore` mediante la primitiva consistente
   MA-TSK-038. Una falta de espacio o fallo de captura no autoriza sustituirla.
   Si está dañada o ausente, no inventar una base vacía ni un respaldo válido.
   Errores de acceso y versiones futuras no autorizan el aislamiento como corrupción.
4. Persistir fases del diario, cerrar conexiones y comprobar de nuevo la imagen.
   Mover los originales y sidecars que existan a `previous` dentro del directorio
   privado de operación. Instalar la candidata cerrada mediante movimiento nativo
   en el mismo volumen y volver a comprobar tamaño y SHA-256 del archivo instalado.
5. Reabrir mediante el store: validación integral EP-004, reglas financieras,
   estructura, formato y coincidencia de linaje, revisión y versión esperados.
   No incrementar artificialmente la revisión financiera.
6. Recargar el catálogo tras la captura y confirmar nuevo `localRestoreEpoch` y
   `syncContrastRequired = true`. Persistir `completed` antes de devolver éxito.
   No se hacen llamadas remotas. La señal queda disponible en los slots del
   catálogo; su consumo y recuperación al reiniciar se integran en MA-TSK-056.
7. Archivar la operación resuelta en `local-backups/diagnostics/<operationId>`.
   Los originales de una activa dañada se conservan íntegros, indefinidamente y
   fuera de retención. Con activa sana, el estado anterior queda en su respaldo
   consistente catalogado; solo después del éxito se retiran sus originales
   conocidos, sin borrado recursivo. Solicitar retención a MA-TSK-053 únicamente
   tras confirmación duradera, protegiendo la candidata usada. Las manuales se
   conservan y las automáticas válidas se reducen a las tres más recientes.

Si falla después de comenzar el intercambio, cerrar la candidata, apartar sus
archivos en `failed`, devolver cada original que llegó a moverse y reabrir y
validar la anterior. Si hay respaldo confirmado, contrastar también su linaje
y revisión. Revertir epoch y señal si se intentó escribirlos, incluso cuando el
movimiento del slot llegó a disco antes de lanzar una excepción. Nunca podar en
un intento fallido. Un rollback imposible conserva originales, candidata y
respaldos y devuelve `recoveryRequired`, bloqueando acceso y nuevas escrituras.

El resultado público distingue `cancelled`, `rejected`, `rolledBack`, `restored`
y `recoveryRequired`, con mensajes españoles sin SQL ni rutas privadas. Incluye
el ID del respaldo anterior y `maintenancePending`: un fallo de archivo de
diagnóstico, limpieza o retención posterior no oculta una restauración ya
confirmada. Un diario que no se pudo archivar bloquea otro intercambio.

## Diario y traspaso a MA-TSK-056

Ruta pendiente: `local-backups/restore/<operationId>/journal-NNN.json`. Cada fase
es un archivo nuevo con sobre SHA-256, flush, relectura y publicación nativa;
no se trunca la fase anterior. Un `.next` no confirma una fase. NNN es secuencia
decimal creciente; un fallo puede dejar un hueco. Fases:

| Fase | Garantía antes de publicarla / siguiente acción |
|---|---|
| `protected` | Clasificación de activa y respaldo confirmado si era utilizable; después cerrar |
| `isolating` | Conexiones cerradas e imagen contrastada; después aislar originales |
| `installing` | Originales apartados; después instalar candidata |
| `installed` | Imagen instalada y bytes contrastados; después reabrir |
| `validated` | Reapertura e identidad/revisión comprobadas; después confirmar catálogo |
| `completed` | Catálogo con nuevo epoch y contraste pendiente confirmado |
| `rolledBack` | Anterior reabierta/validada y epoch/señal anterior restablecidos |

Payload v1: `kind = autofinance.localRestoreJournal`, `formatVersion = 1`,
`operationId`, `candidateBackupId`, `previousBackupId` (nullable),
`previousDatasetId` / `previousRevision` (nullable, de respaldo confirmado),
`phase`, `previousUsable`, `previousEpoch`, `previousContrastRequired`, `newEpoch`,
`candidateSha256`, `candidateSizeBytes`, `datasetId`, `revision`.
Contadores son cadenas decimales exactas; IDs y rutas se derivan de UUIDs
validados, sin rutas absolutas persistidas ni datos financieros descriptivos.
La candidata inicial está en `autofinance.sqlite`; los originales y la candidata
fallida usan `previous/autofinance.sqlite{,-wal,-shm,-journal}` y
`failed/autofinance.sqlite{,-wal,-shm,-journal}` dentro de la operación.

Una excepción de movimiento puede ocurrir tras cambiar el namespace: la fase
indica intención y el recuperador debe comprobar los archivos reales, hashes,
manifiestos y metadatos antes de decidir. No basta leer una etiqueta de fase.
MA-TSK-056 implementará lectura estricta y resolución tras interrupción antes
de abrir la app. **Este ticket deja el diario y bloquea la apertura normal si
detecta uno pendiente; no afirma recuperar automáticamente un proceso muerto.**
Nunca crear una nueva activa por ausencia de main durante ese intercambio.

## Verificación local · 2026-10-02

`test/synchronization/local_restore_test.dart` añade 24 casos con SQLite real y
datos sintéticos: cancelación por comparación de todos los archivos, restauración
de datos y revisión esperados, respaldo recuperable, originales corruptos y
sidecars conservados byte a byte, fallos antes/después de aislar o instalar,
diario y catálogo (también fallo posterior al movimiento), reapertura fallida,
captura/cierre fallidos, hashes alterados antes/después del intercambio,
drenaje de una transacción, bloqueo de nuevas escrituras, exclusión nativa,
rechazo dentro de unidad, rollback imposible, bloqueo al reiniciar, limpieza
pendiente y cuatro restauraciones con tres automáticas y manual conservada.

Flutter 3.47.0 / Dart 3.13.0 y check-toolchain verificados;
`pub get --enforce-lockfile` correcto sin modificar SDK/lockfile/esquema.
`scripts/check-quality.ps1`: formato, análisis sin incidencias, 579 pruebas y
cuatro variantes adicionales de APP_ENV correctas. EP-001 y `git diff --check`
correctos. Se necesitaron permisos revisados para pub.dev y resolución nativa
de rutas privadas, bloqueados por el sandbox.

Builds intentados: Windows bloqueado por Visual Studio C++ ausente y Android
por Android SDK ausente. No se acredita ejecución en dispositivo Android,
integración visual, resultado de CI ni resistencia a corte eléctrico. Los fallos
son inyectados; no se llenó el disco ni se interrumpió físicamente el proceso.
