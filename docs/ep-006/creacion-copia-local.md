# MA-TSK-052 · Crear copia local consistente y verificable

## API y composición

`LocalBackupCreator`, exportado por `synchronization`, ofrece `createManual()` y
`createPreRestore(restoreOperationId)`. App compone `LocalBackupService` mediante
`createLocalBackupCreator`, inyectando el mismo `LocalDatabaseStore` y directorio
privado de soporte que usa la base. Construir el servicio no abre SQLite ni
inicia acciones. Las llamadas son explícitas; no hay pantalla, Drive o retención.

```dart
final creator = createLocalBackupCreator(store: store);
final copy = await creator.createManual();
// copy.relativeDirectory se interpreta respecto a <soporte>/sqlite.
// cleanupPending informa de temporales conservados después del registro.
```

Una copia se devuelve solo después de confirmar el catálogo. El resultado
contiene ID, ruta relativa, identidad/revisión capturadas, orden y origen.
`createPreRestore` exige un UUID v4 de operación y conserva esa relación en el
manifiesto; no restaura, poda ni cambia la señal local de divergencia.

## Publicación

El servicio implementa la creación del [contrato v1](contrato-copias-locales.md):

1. Adquiere exclusión nativa por instalación, incluso entre procesos. Windows
   bloquea un byte del archivo; Android/Linux usa `flock` no bloqueante. Un
   propietario concurrente recibe `operationInProgress`. El sistema libera el
   bloqueo si muere el proceso.
2. Lee los slots confirmados del catálogo sin abrir la activa. Crea un catálogo
   inicial solo si no existen artefactos previos; conserva epoch y señal de
   contraste de un catálogo existente. Reserva orden e intención duradera;
   los órdenes de intenciones anteriores nunca se reutilizan.
3. Invoca **una sola vez** `LocalDatabaseStore.createConsistentBackup()` de
   MA-TSK-038. No existe otro motor de snapshot. Verifica que la imagen recibida
   está en `copies/snapshot-*`, sin sidecars, y persiste su recibo.
4. Traslada esa imagen cerrada a staging, vacía buffers y calcula tamaño/SHA-256.
   `SqliteLocalBackupValidator` abre exclusivamente la imagen en lectura y
   reutiliza `validateExistingDatabase`: AFNC, esquema exacto, integridad,
   claves foráneas, metadatos y reglas financieras. Exige esquema vigente v6 y
   compara identidad/revisión con el resultado del snapshot. Confirma de nuevo
   tamaño/hash después de validar y cerrar.
5. Escribe, cierra y relee el manifiesto protegido por checksum. Publica un
   directorio nuevo con los dos archivos finales; todavía no devuelve éxito.
   Escribe una generación completa `.next`, la relee y sustituye únicamente
   el slot ausente o más antiguo. Confirma el contenido final antes de devolver.
6. Limpia solo intent/receipt propios y directorios vacíos. Si encuentra otros
   archivos, los conserva e informa `cleanupPending`, manteniendo el éxito ya
   registrado. No elimina snapshots huérfanos ni otras copias.

Los documentos usan UTF-8 sin BOM, claves únicas, checksums del payload,
fechas UTC canónicas, UUID y contadores decimales int64 exactos. Se rechazan
campos desconocidos y rutas externas, enlaces o resoluciones fuera de soporte.
Los errores públicos no incluyen SQL, rutas privadas ni excepciones nativas.

## Persistencia y límites de recuperación

`NativeBackupPersistence` comprueba flush y cierre de archivos. En Windows usa
`MoveFileExW` con `MOVEFILE_WRITE_THROUGH`, sin permitir copiar entre volúmenes.
En Android/Linux renombra y ejecuta `fsync` sobre los directorios de origen y
destino; no fija `O_DIRECTORY` de x86, cuyo valor difiere en Android ARM.
Una llamada nativa fallida impide anunciar éxito.

Referencias de implementación: [MoveFileExW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw),
[fsync de directorios](https://man7.org/linux/man-pages/man2/fsync.2.html) y
[constantes Android ARM64](https://android.googlesource.com/platform/bionic/+/cf02614a4bef8fe336cae8796df5cb6eeb368a6d/libc/kernel/uapi/asm-arm64/asm/fcntl.h).
Estas llamadas y una prueba de proceso no acreditan resistencia a pérdida
eléctrica del dispositivo, controlador o sistema de archivos.

Ante fallo se conserva la activa y las copias anteriores, junto con la intención,
temporales o copia final no registrada que permitan diagnosticar/recuperar.
Un catálogo futuro, dañado o conflictivo y un directorio final no catalogado
bloquean nuevas capturas con error tipado, sin sobrescribirlos. La reconciliación,
reconstrucción y listado públicos pertenecen a MA-TSK-053; la revalidación y
migración de candidatas antiguas a MA-TSK-054. El intercambio recuperable y la
señal posterior a restaurar pertenecen a MA-TSK-056. No se adelantan esas acciones.

## Verificación

`test/synchronization/local_backup_service_test.dart` usa SQLite real, fixtures
sintéticos y fallos de almacenamiento inyectados. Comprueba WAL, captura durante
una unidad concurrente, edición posterior, esquema/identidad/revisión, archivo
abrible, invisibilidad de temporales, IDs/órdenes independientes, fallos de
publicación/registro/flush, conservación de copias anteriores, bloqueo dentro de
UnitOfWork, corrupción/formato/reglas financieras, revisión superior a 2^53,
reinicio con intención, catálogo futuro/dañado, rutas y sidecars, sobres y
liberación del bloqueo tras terminar un proceso real.

`integration_test/local_backup_creation_test.dart` prepara el recorrido con
soporte privado real, adaptadores nativos, reapertura del store, creación manual
y previa a restauración, exclusión y fallo sin pérdida. CI lo ejecuta en Windows
y en emulador Android x86_64, después de sus builds. Android ARM requiere además
ejecución en un dispositivo o emulador ARM; no se presume por la prueba de host.

Se utiliza el ticket íntegro proporcionado y la instantánea local previa de
Epic Board; no hay conector disponible y no se modifica su estado administrativo.
Los archivos de implementación de este ticket ya estaban sin confirmar al
iniciar la sesión y se han revisado y completado como trabajo previo de MA-TSK-052.

### Evidencia local · 2026-10-02

- Flutter 3.47.0 / Dart 3.13.0 y `check-toolchain.ps1` correctos.
  `pub get --enforce-lockfile` correcto, sin cambios en SDK ni lockfile.
- `scripts/check-quality.ps1`: 87 archivos formateados sin cambios pendientes,
  análisis sin incidencias, **478 pruebas correctas** (30 del servicio de copia)
  y las cuatro variantes adicionales de `APP_ENV` correctas.
- Las pruebas de host ejecutan en Windows las llamadas nativas de movimiento,
  flush, cierre y bloqueo; el bloqueo entre procesos se libera al terminar el
  propietario. Los fallos de espacio/escritura/cierre se inyectan; no se ha
  llenado físicamente el disco ni interrumpido la alimentación.
- `actionlint` del workflow modificado, `git diff --check` y los casos numéricos
  EP-001 correctos. SDK, esquema SQLite y lockfile permanecen intactos.
- Builds intentados: Windows falla por ausencia de Visual Studio C++; Android
  falla por ausencia de Android SDK. La integración dentro de la app y Android
  no se han ejecutado localmente. CI queda configurado, sin afirmar aquí su
  resultado ni la verificación de Android ARM.

El sandbox bloqueaba la resolución de enlaces de los directorios del usuario y
el acceso a pub.dev; las comprobaciones completas se ejecutaron con permisos
revisados. No se redujeron las validaciones de rutas para eludir esos bloqueos.
