# MA-TSK-089 · Gestión individual de movimientos

`MovementManagement`, publicado por `movements.dart`, implementa alta, lectura
individual, edición parcial, cambio/retirada de discrecionalidad y borrado sobre
`MovementRepository`. `createMovementManagement(database: ...)` compone el
adaptador EP-004 y su `UnitOfWork` con la conexión abierta de la sesión.
No abre otra base, cambia esquema, importa datos ni añade pantallas.

Las fechas de entrada son civiles ISO `AAAA-MM-DD`, validadas por `ValueDate`.
Los importes aceptan signo opcional, coma o punto decimal, sin miles y con hasta
dos decimales. Se convierten mediante `BigInt` a céntimos exactos no cero en
rango int64, sin `double` ni redondeo. Concepto obligatorio y UUID canónicos.
La cuenta corriente y su vigencia mensual, así como existencia y asignabilidad
de categoría, se revalidan por el repositorio existente al guardar.

La edición conserva los argumentos omitidos. Para categoría y discrecionalidad,
`MovementChange(valor)` indica una asignación explícita y `MovementChange(null)`
una retirada. Una categoría archivada preexistente se puede conservar; asignarla
a otro movimiento o volver a asignarla tras retirarla se rechaza. La
discrecionalidad explícitamente editada se recorta y queda NULL si está vacía;
el adaptador aplica esa misma normalización a altas y cambios directos.

Los campos financieros y la discrecionalidad se guardan en una unidad de trabajo:
un fallo de la segunda escritura revierte la primera y la revisión. Una operación
que cambia datos incrementa revisión una vez; una edición sin cambios no escribe.
UUID y procedencia nunca se sustituyen; las altas idénticas mantienen identidades
distintas. Borrar conserva `import_rows` y su lote, por lo que repetir la huella
original no resucita el movimiento. El caso de uso de borrado se invoca después
de la confirmación que corresponde a la futura interfaz.

Se utiliza el ticket completo facilitado por el usuario. No hay conector Epic
Board disponible en esta sesión y no se ha cambiado su estado administrativo.
El contrato y los casos MA-TSK-087 estaban presentes como archivos sin seguimiento
al comenzar y no se incluyen en este commit. Tampoco se incluyen los cambios
concurrentes de sincronización ni los mockups de categorías.

## Verificación

Las pruebas sintéticas en `test/movements/movement_management_test.dart` ejercitan
la composición real con SQLite: importes y límites, altas idénticas, conservación
de campos, revisión única, no-op, retirada explícita, reapertura, vigencia y tipo
de cuenta, categoría archivada, rechazo sin cambios parciales, rollback de un
fallo inducido después de editar y borrado con procedencia retenida. Comprueban
también que presupuesto y fotos permanecen intactos.

Comprobaciones locales del 2026-10-04: Flutter 3.47.0 / Dart 3.13.0,
`check-toolchain.ps1` y resolución con `--enforce-lockfile`; lockfile sin cambios.
Las 21 pruebas dirigidas de gestión, repositorio, unidad de trabajo y arquitectura
pasan. `check-quality.ps1` verifica formato sin cambios, análisis sin incidencias,
938 pruebas generales y las cuatro variantes de arranque `APP_ENV`.
`git diff --check` sin errores. La primera ejecución restringida no pudo abrir
SQLite por las restricciones del entorno; la verificación válida usa permisos
ampliados. Se corrigieron los avisos de estilo antes de la ejecución final.

No se cambian plataformas ni interfaz; no se requieren nuevos builds nativos
para este ticket. No se acredita ejecución en dispositivos Windows/Android.
