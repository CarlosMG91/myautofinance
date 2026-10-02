# MA-TSK-056 · Recuperación de restauraciones interrumpidas

Implementa R11/R12 del contrato local, sobre MA-TSK-055. No cambia reglas
financieras, esquema SQLite, plataformas, SDK, OAuth ni pantallas. Se usa el
ticket completo facilitado por el usuario; no hay conector Epic Board disponible
en esta sesión y no se modifica el estado administrativo del tablero.

## Resolución previa a la apertura

`LocalDatabaseStore.open()` resuelve el diario antes de crear conexiones Drift,
migrar o crear una base nueva. La recuperación usa el mismo bloqueo nativo que
captura, catálogo y restauración. Valida rutas sin enlaces, checksum y formato
de todos los diarios publicados, identidad del directorio y metadatos constantes.
Un diario corrupto, futuro, ambiguo o un fallo de almacenamiento bloquea la
apertura conservando archivos. Nunca se adopta un archivo `.next`.

| Estado confirmado | Decisión |
|---|---|
| Staging sin diario | No hubo autorización para mover la activa; abrirla normalmente y conservar staging |
| `protected` | Validar la activa anterior y conservar epoch/contraste previos |
| `isolating`, `installing`, `installed`, `rollingBack` | Si existía activa utilizable, validar de nuevo el respaldo consistente, instalarlo y devolver epoch/contraste previos |
| `validated`, `completed` | Validar íntegramente la activa y su identidad; confirmar nuevo epoch y contraste pendiente |
| Activa anterior dañada/ausente | Usar la candidata verificada de staging o la ya instalada; conservar los originales aislados |
| `rolledBack` | Comprobar la anterior y archivar el diario sin anunciar restauración nueva |

Si la imagen validada ya no es válida, se vuelve al respaldo anterior cuando
existe. `completed` permite revisiones posteriores de la misma base: un fallo
de archivado tras anunciar éxito no debe borrar ediciones posteriores válidas.

## Recuperación de la recuperación

Antes de recuperar un respaldo se publica `journal-900.json` con `rollingBack`.
Cada intento prepara una imagen nueva desde el respaldo inmutable, contrastando
manifiesto, catálogo, tamaño, hash y validación integral de EP-004/MA-TSK-054.
Aparta main y sidecars presentes en un directorio único, sin reemplazar archivos
de intentos anteriores; después instala y valida la imagen anterior.

El catálogo se confirma mediante sus dos generaciones y se publica
`journal-901.json` con el resultado. El directorio completo se mueve a diagnóstico.
Un reinicio puede repetir estas operaciones: ningún intento necesita borrar el
respaldo catalogado, la copia seleccionada o los originales de diagnóstico.
La ruta normal de MA-TSK-055 también publica `rollingBack` antes de revertir.

Tras una finalización confirmada y archivada se solicita la retención existente
de MA-TSK-053, fuera del bloqueo de recuperación. Un fallo de mantenimiento
conserva el exceso para el siguiente éxito. Un rollback no autoriza poda.

## Entrega a sincronización

`createLocalSyncContrastReader()` entrega `LocalSyncContrastReader` desde la
composición de app. `read()` devuelve `restoreEpoch` y `required` desde el
catálogo independiente de SQLite. Un catálogo ausente/dañado o un diario pendiente
requiere contraste. Fallos de lectura o formatos futuros se propagan; no acreditan
coincidencia remota. Este lector no abre la activa, autoriza OAuth ni llama a red.

La futura operación manual de Drive deberá comprobar el epoch bajo la exclusión
de instalación y contrastar la versión remota conocida. Igualdad de dataset y
revisión no elimina esta obligación. El lector no proporciona una operación de
limpieza del indicador: confirmarla pertenece a la futura sincronización.

## Verificación

Las pruebas usan únicamente SQLite y datos sintéticos. Guardan snapshots del
estado de disco en staging, protección, cierre, aislamiento, instalación,
reapertura validada, confirmación del catálogo, finalización y rollback. Cada
snapshot se abre con un propietario nuevo y se vuelve a abrir tras otro cierre.
Comprueban contenido/revisión, epoch/contraste y conservación de copias manuales
y respaldos automáticos. Además interrumpen la propia recuperación después de
publicar su decisión, apartar main, instalar el respaldo, confirmar catálogo y
archivar. Incluyen activa dañada, diario corrupto y restauración con igual revisión.

Estos snapshots simulan cierres inesperados; no son pruebas de corte eléctrico
del hardware ni ejecución en dispositivo Android. La persistencia utiliza el
adaptador existente (MoveFileExW WRITE_THROUGH y fsync en Android/Linux).

Evidencia local del 2026-10-02:

- Flutter 3.47.0 / Dart 3.13.0 y `check-toolchain.ps1` correctos.
- `flutter pub get --enforce-lockfile` correcto con permisos revisados para
  pub.dev; SDK, dependencias y lockfile sin cambios. El intento inicial dentro
  del sandbox falló por restricción de red.
- `scripts/check-quality.ps1`: formato sin cambios, análisis sin incidencias,
  **598 pruebas correctas** y cuatro variantes adicionales de `APP_ENV` correctas.
  Las pruebas nativas necesitaron permisos revisados porque el sandbox deniega
  resolver enlaces de los antecesores del directorio temporal de Windows.
- `node docs/ep-001/verificar-casos.mjs`: referencias financieras intactas.
- `git diff --check`: correcto.
- Builds intentados con los comandos fijados: Windows bloqueado por ausencia
  de Visual Studio C++; APK bloqueado por ausencia de Android SDK. No se acredita
  compilación nativa de la aplicación ni ejecución en Android.

El código de recuperación y su lector no reciben cliente HTTP, sesión OAuth,
localizador Drive ni credenciales. Las pruebas de este ticket no acceden a Drive.
