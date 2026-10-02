# MA-TSK-054 · Validar candidatas sin tocar la base activa

## API y composición

App compone `createLocalRestoreCandidatePreparer()` e inyecta el directorio
privado de soporte de la instalación. Construirlo no abre ninguna base. El
puerto público `LocalRestoreCandidatePreparer.prepare(backupId)` acepta un UUID
de artefacto local; no admite rutas elegidas por el usuario ni archivos externos.
No requiere `LocalDatabaseStore`, fuente de snapshots, sesión OAuth o Drive.

```dart
final preparer = createLocalRestoreCandidatePreparer();
final result = await preparer.prepare(backupId);
switch (result) {
  case ReadyLocalRestoreCandidate():
    // Imagen cerrada en soporte/sqlite/result.relativePath.
    // Entregar al coordinador junto con operationId, image, sizeBytes y sha256.
    break;
  case RejectedLocalRestoreCandidate():
    // result.issue es estable; result.message es legible en español.
    break;
}
```

El resultado preparado contiene identidad y revisión exactas, esquema original,
esquema validado, tamaño y SHA-256 de **staging**. Si se migró, su hash es distinto
del hash de la copia original. La revisión no se incrementa por migración técnica.
La preparación no modifica manifiesto, slots del catálogo, epoch ni señal local
de contraste. El ticket íntegro proporcionado y `.tools/epic-board-read.json`
coinciden en alcance y criterios; la instantánea no acredita el estado actual
de Epic Board. No hay conector disponible y no se modifica su estado administrativo.

## Recorrido y rechazos

1. Bajo el mismo bloqueo nativo por instalación que creación/catálogo, derivar
   rutas del UUID y rechazar enlaces, reparse points y resoluciones externas.
   Exigir manifiesto verificado y SQLite como únicos dos archivos del artefacto.
   Cualquier baja duradera impide usar la copia, aunque sus bytes sigan presentes.
2. Leer ambos slots confirmados si existen. Contrastar tamaño, hash y descriptor
   con la entrada seleccionada; una caché `valid` nunca evita revalidar. Un slot
   futuro, conflicto o catálogo sin generación legible produce rechazo, no un
   catálogo vacío. Sin catálogo/entrada se permite validar el manifiesto completo
   de un artefacto recuperable. No adoptar `.next` ni reconstruir catálogo aquí.
3. Comprobar longitud y SHA-256 originales. Copiar exclusivamente esa imagen
   inmutable y cerrada a
   `local-backups/restore/<operationId>/autofinance.sqlite.part`. Confirmar flush,
   tamaño y hash de la copia de trabajo antes de interpretarla.
4. Abrir solo staging en modo lectura y comprobar AFNC, versión, ausencia de
   sidecars, `integrity_check`, `foreign_key_check`, estructura exacta y metadatos.
   Reutilizar `validateExistingDatabase` de EP-004 para reglas financieras y
   comparar linaje, revisión y versión con el manifiesto. El hash por sí solo no
   prueba la validez de SQLite.
5. Admitir las versiones publicadas 1–5 mediante el `onUpgrade` transaccional de
   `LocalDatabase`, usando un ejecutor exclusivo sobre staging. La v0 sintética
   se rechaza y no hay downgrade de versiones futuras. Cerrar y validar de nuevo
   bajo la misma política; exigir v6 y conservación de linaje y revisión.
6. Confirmar flush, calcular tamaño/hash de staging y comprobar de nuevo el
   original y manifiesto. Publicar la imagen de trabajo con el adaptador de
   persistencia nativo a su nombre final nuevo y verificar sus bytes. Solo
   entonces devolver `ReadyLocalRestoreCandidate`.

Los rechazos diferencian tamaño/hash alterados, metadatos inconsistentes,
producto ajeno, formatos/esquemas futuros, esquema no soportado o modificado,
integridad SQLite, FK, reglas financieras, migración y almacenamiento. Los
mensajes públicos no contienen SQL, rutas privadas ni excepciones nativas.
Un fallo de acceso es `storageFailure`, sin afirmar corrupción ni crear una
base activa nueva. Los temporales fallidos se conservan para diagnóstico y
nunca se devuelven como candidatos listos.

## Traspaso y límites

MA-TSK-055/056 deben confirmar la acción, proteger el ID en uso, crear el respaldo
previo cuando corresponda, bloquear escrituras, cerrar la activa, implementar
diario/intercambio/reapertura y confirmar divergencia. Reciben `operationId` del
staging y deben volver a comprobar sus bytes antes del intercambio; el resultado
no autoriza restauración ni supone protección indefinida tras liberar el bloqueo.
El catálogo señala directorios en `restore` como operación no resuelta y suspende
poda: el futuro coordinador debe resolverlos y retirar únicamente su trabajo
antes de pedir retención. Este ticket no implementa limpieza de operaciones
abandonadas, intercambio, confirmación visible ni pantalla.

## Verificación

`test/synchronization/local_restore_candidate_test.dart` usa SQLite real y datos
sintéticos. Comprueba staging válido, nombres independientes, revisión > 2^53,
activa corrupta, artefacto sin catálogo, migraciones 1–5 con datos conservados,
tamaño/hash alterados, B-tree dañado, FK y reglas financieras inválidas, producto
ajeno, estructura inesperada, v0/futuras, discrepancias de metadatos, formato JSON
futuro/dañado, sidecars, bajas, archivo ausente, rutas externas/junction, I/O,
fallos de flush/publicación, migración fallida, sustitución concurrente del
original y exclusión compartida. Las comprobaciones verifican conservación de
activa, manifiesto, copia original y catálogo en cada preparación aplicable.

La resistencia a pérdida eléctrica, el intercambio interrumpido y la ejecución
de la aplicación en Android no quedan acreditados por estas pruebas de host.

### Evidencia local · 2026-10-02

- Flutter 3.47.0 / Dart 3.13.0 y `check-toolchain.ps1` correctos.
  `pub get --enforce-lockfile` correcto; SDK, lockfile y esquema publicados
  permanecen sin cambios. Se requirieron permisos revisados por el bloqueo
  de red a pub.dev y de resolución de rutas privadas en el sandbox.
- `scripts/check-quality.ps1`: 96 archivos con formato correcto, análisis sin
  incidencias, **555 pruebas correctas**, incluidas **38 pruebas nuevas** de
  candidatas. Las cuatro variantes adicionales de arranque (`development`,
  `test`, `production` e `invalid-synthetic`) también se verifican con el script.
- `node docs/ep-001/verificar-casos.mjs` y `git diff --cached --check` correctos.
  Windows ejecutó SQLite real, migración Drift, flush/cierre, movimientos nativos,
  bloqueo y rechazo de junction. Fallos de I/O y migración se inyectaron; no
  se llenó físicamente el disco ni se interrumpió la alimentación.
- Builds intentados: Windows bloqueado por ausencia de Visual Studio C++ y
  Android por ausencia de Android SDK. No se ejecutó integración dentro de la
  app ni pruebas en Android y no se afirma el resultado de CI.
