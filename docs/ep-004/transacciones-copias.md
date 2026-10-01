# MA-TSK-038 · Unidad de trabajo, revisión y copia consistente

`LocalDatabase` implementa el puerto técnico `UnitOfWork` de core. App inyecta
la misma instancia en todos los repositorios y en el coordinador. `run` agrupa
referencias, lote, filas, presupuestos y fotos en una transacción SQLite. Los
repositorios también abren una unidad al usarse individualmente. Las llamadas
anidadas usan savepoints: un error revierte su operación; si llega al coordinador,
revierte toda la unidad. Esperar todas las llamadas dentro del callback.

```dart
await unitOfWork.run(() async {
  // Resolver/crear referencias mediante los repositorios inyectados.
  // Confirmar el lote con sus movimientos y presupuestos ya normalizados.
  await batches.create(/* datos ya interpretados */);
});
final state = await unitOfWork.readState();
```

No hay parser ni pantallas. La importación futura debe preparar sus datos antes
de entrar en la unidad; no esperar interacción humana dentro de una transacción.
No abrir conexiones adicionales ni escribir mediante SQL externo a los
repositorios/unidad: el acceso SQL público queda para infraestructura y fixtures.

Un marcador y triggers TEMP detectan INSERT/DELETE y UPDATE con cambio de campos
de negocio en las nueve tablas principales. Cambiar solo timestamps no cuenta.
El marcador se revierte con transacciones/savepoints; no se usa total_changes,
que también contaría escrituras revertidas. Solo la unidad exterior valida
integridad y reglas de relaciones y aumenta revision una vez antes del COMMIT.
Lecturas, actualizaciones idénticas, archivo ya importado y errores no aumentan
la revisión. Si falla incluso la escritura de revision, también revierten datos.
dataset_id permanece intacto. Las migraciones mantienen su transacción técnica,
sin contar como mutación financiera. No cambia el esquema físico v6: los objetos
TEMP no se exportan ni forman parte de copias o snapshots Drift publicados.

`LocalDatabaseStore` implementa `LocalBackupSource`, exportado por synchronization.
`createConsistentBackup` mantiene abierta la base y ejecuta `VACUUM INTO` en su
conexión Drift. Genera un archivo nuevo en un directorio único dentro de
`<soporte>/sqlite/copies/snapshot-*/autofinance.sqlite`. SQLite captura una imagen
consistente, incluidos cambios confirmados pendientes en WAL; no se copia el
archivo principal ni se requiere cerrar o truncar WAL. No se permite llamar
desde una unidad abierta: falla sin publicar una copia parcial. Una llamada
concurrente externa espera la transacción activa a través de Drift.

Después se abre la copia en modo solo lectura y se valida con la política
existente: formato, versión, esquema, integrity_check, foreign_key_check y reglas
financieras. El resultado `LocalBackup` contiene ruta y `DatasetState` leído de
esa misma copia, no de la base activa posteriormente. Una edición posterior
incrementa la revisión local y no altera la copia capturada. No se entrega el
resultado hasta terminar la validación. Un fallo elimina únicamente el directorio
temporal creado por esta operación cuando sea posible; nunca modifica ni borra
la base activa ni copias previas. Si el proceso muere, puede quedar un temporal
incompleto; su mera existencia no acredita que sea válido.

Las copias válidas se conservan. El consumidor futuro debe gestionar su retención
y eliminación tras usarlas. Este puerto no descarga, reemplaza ni transfiere
archivos. La versión remota conocida y credenciales siguen fuera de la base
compartida. No se llama a Google Drive.

## Verificación del 2026-10-01

Flutter 3.47.0 y Dart 3.13.0 comprobados; check-toolchain y pub get con
enforce-lockfile, sin actualizar dependencias. check-quality completo: formato,
análisis sin incidencias, 72 pruebas y las cuatro variantes de APP_ENV.

Ocho pruebas nuevas usan SQLite real y datos sintéticos: rollback completo de
referencias/lote/registros/fotos, revisión única y persistida, no-op/lecturas,
savepoint fallido, escrituras concurrentes, mutaciones individuales, reimportación,
fallo al guardar revisión, fallo de almacenamiento y reintento, copia concurrente,
WAL pendiente, reapertura de copia con relaciones, revisión capturada, copias
sucesivas y rechazo dentro de transacción. Dos fixtures anteriores se actualizan
para cumplir el modelo vigente de liquidez y fotos. Se amplía la integración
nativa existente para unidad de trabajo, rollback y copia validada.

Los builds locales se intentaron: Windows bloqueado por soporte de symlinks para
plugins; Android por ausencia de SDK. No se acredita ejecución de integración
en dispositivos ni compilación nativa. Epic Board no está disponible: se usa el
ticket completo proporcionado, sin modificar su estado administrativo.

Fuentes técnicas: [VACUUM INTO](https://www.sqlite.org/lang_vacuum.html) y
[transacciones y savepoints Drift](https://drift.simonbinder.eu/dart_api/transactions/).
