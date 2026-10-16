# MA-TSK-221 · Copia SQLite portable y verificable

Implementación de T03 según [T01](contrato-exportacion-v1.md). Se utiliza el
ticket íntegro facilitado por el usuario; no hay conector Epic Board disponible
en esta sesión y no se acredita un cambio de estado del tablero.

## Integración con guardado y UI

`createPortableBackupExporter(store: store)` en
`lib/app/portable_backup_export_factory.dart` compone el puerto público
`PortableBackupExporter`, `PortableSqliteBackupExporter` y el inspector SQLite.
No inicia acciones al construirlo ni modifica rutas, pantallas o plataformas.
No añade dependencias pub, módulos ni dependencias entre funcionalidades.

La acción separada «Exportar copia completa» llama
`prepare(cancellation: DataExportCancellation())`, sin parámetro de rango.
Devuelve `PreparedDataExport` con `zipPath`, `state` y `exportId` solo después de
verificar el ZIP. T04/T06 deben guardar este archivo mediante su flujo nativo y
llamar a `dispose()` en `finally`, también si se cancela el destino. El retorno
del preparado acredita generación, no guardado por la persona usuaria.
`dispose()` admite llamadas repetidas tras completar la limpieza.

Los errores usan `DataExportFailure` con código sin rutas, SQL, importes ni
conceptos. No hay envío, acceso Drive, cifrado nuevo ni restauración.
La UI y su aprobación explícita siguen perteneciendo a T05/T06.

## Imagen completa y validación

Cada operación llama exactamente una vez a
`LocalBackupSource.createConsistentBackup` de EP-004. No crea otro motor de
snapshot, copia el principal vivo ni utiliza `LocalBackupCreator`.
Solo adopta el archivo regular nuevo `copies/snapshot-*/autofinance.sqlite`,
sin enlaces; nunca adopta una ruta activa ni una copia del catálogo privado.

La imagen y su copia de staging se abren en solo lectura y se validan mediante
`validateExistingDatabase`, la política integral vigente EP-004/006: identidad
de aplicación, esquema/objetos, integridad SQLite, claves y reglas financieras.
Se exige la versión actual del código, sin fijar el 8 histórico en el servicio.
No se migra la imagen. Se rechazan WAL, SHM y journal junto a ella.

`database_state` debe coincidir con la identidad/revisión de `LocalBackup`.
`PRAGMA application_id`, `user_version` y todos los nombres/conteos de tablas de
usuario se leen de la imagen cerrada, excluyendo `sqlite_*` y objetos TEMP.
No se relee la activa para describir el resultado. Antes de empaquetar se
contrasta la copia de staging con la imagen: SHA-256/tamaño, identidad/revisión,
esquema, aplicación, inventario y conteos. El verificador ZIP comprueba de nuevo
todos los bytes finales contra esos descriptores; alterar una imagen durante
la inspección tampoco permite devolver un preparado correcto.

Se conservan todos los objetos y filas financieros, incluidas categorías,
cuentas, liquidez histórica, movimientos, presupuestos, cabeceras/valores de
fotos, lotes, filas y originales por fila ya persistidos. No hay filtro CSV,
redacción ni reconstrucción parcial. No se adjuntan archivos de sesión,
credenciales, configuración de instalación, estado Drive ni extractos completos
no persistidos. El esquema validado excluye tablas añadidas ajenas al formato.

## Contenido público v1

El ZIP estándar STORE contiene exactamente, en orden:

- `LEEME.md`: ámbito, contenido, privacidad, verificación, recuperación para
  consulta en carpeta nueva Windows y ejemplos de SELECT sin Autofinance.
- `autofinance.sqlite`: imagen financiera completa, independiente y cerrada.
- `manifest.json`: JSON UTF-8 directo `autofinance.portableBackup` v1.

El manifiesto cumple T01: EUR, filtro/diccionario nulos, UUID v4 de exportación,
fecha UTC al terminar captura, metadatos reales de imagen, tamaños/revisión y
conteos como cadenas decimales exactas, SHA-256 de bytes finales y lista de todas
las tablas con sus conteos. No se auto-hashea ni usa el sobre de copias privadas.
Según T01 no se añade `diccionario.json` a este ZIP: el diccionario de esquema
es la propia `sqlite_schema`, con columnas/restricciones/relaciones consultables
mediante PRAGMA, y su guía de contenido está en LEEME.

Se reutiliza el escritor/verificador ZIP de T02, ampliando su tipo SQLite y
rechazando crecimiento/truncado de un archivo durante su empaquetado. Relee el
ZIP final: cabeceras, inventario, tamaños, CRC32, SHA-256 y fin de archivo.
No permite entradas duplicadas por mayúsculas, rutas ni directorios anidados.
SHA-256 detecta corrupción; no autentica autoría ni protege de modificar
conjuntamente datos y manifiesto.

## Recursos y conservación

El límite inyectable por defecto es 1 GiB para el ZIP completo. El formato
estándar admite como máximo el límite explícito de 32 bits; no se genera ZIP64
truncado. Se comprueba el tamaño de imagen antes de procesarla, se copian y
hashean bloques y se comprueba cancelación por bloque. Captura y validación
SQLite existentes no son interrumpibles internamente: al terminar comprueban
la cancelación antes de publicar. No se carga toda la base en memoria.

Solo se eliminan archivos inmediatos del staging creado por la operación y su
snapshot adoptado (incluidos sidecars conocidos si la imagen fue rechazada).
No hay barridos, borrados recursivos de catálogos ni nueva política de retención.
Un contenido inesperado no autoriza borrar archivos ajenos. Fallar o cancelar
no devuelve un ZIP listo y conserva activa, revisión financiera, copias previas
y destinos existentes; el servicio ni siquiera recibe un destino del usuario.

## Verificación y límites

Las pruebas usan exclusivamente datos sintéticos de T01 y SQLite real.

- Flutter 3.47.0 / Dart 3.13.0 y `scripts/check-toolchain.ps1` correctos.
  Resolución estricta offline correcta tras fallar la consulta inicial de red;
  el control posterior también resuelve online sin actualizar lockfile/SDK.
- `scripts/check-quality.ps1`: formato de **492 archivos sin cambios**, análisis
  sin incidencias y suite completa en **13:02: 1.981 correctas y tres fallidas**
  en archivos ajenos. Son el recorrido Windows de
  `test/drilldowns/report_drilldown_journey_test.dart` y los recorridos
  Windows/Android de `test/movements/pending_lifecycle_test.dart`, todos con
  `Bad state: No element`. Ya constan como fallos ajenos en la evidencia de T02;
  no se corrigen desde este ticket ni se declara verde el control general.
  El script se detiene antes de las cuatro variantes APP_ENV finales; se
  ejecutan después por separado y las cuatro pasan (development, test,
  production e invalid-synthetic, que verifica el fallo seguro).
- **20 pruebas específicas correctas** en una extracción aislada de HEAD más
  los cambios propios, sin modificaciones concurrentes: nueve de copia portable
  y las once de regresión del exportador CSV, incluida su verificación ZIP.
  Se cubren fidelidad de todos los objetos/filas y originales persistidos,
  conteos, revisión int64 máxima, base vacía, consulta sin funciones de la app,
  cambios en la activa antes de recibir la captura, una escritura WAL pendiente
  durante la captura (solo incluye lo confirmado), metadatos declarados falsos,
  bytes corruptos, esquema/identidad alterados, claves y fechas fuera de vigencia,
  sidecars rechazados, alteración durante inspección final, cancelación, límites,
  almacenamiento fallido, limpieza, catálogo previo intacto y dos exportaciones
  simultáneas con temporales independientes.
- Análisis de los **siete archivos Dart afectados sin incidencias** también en
  esa extracción. El análisis completo del checkout compartido pasa; el completo
  de la extracción reproduce las **95 incidencias previas de Drive** ya descritas
  por T02: faltan `drive_upload.dart`, `drive_upload_factory.dart` y miembros de
  estado presentes solo en cambios concurrentes. La prueba de arquitectura que
  importa el arranque tampoco compila en esa extracción por esos archivos; las
  dos pruebas de arquitectura pasan en el checkout compartido. No se incorporan
  piezas ajenas para declarar verde la aplicación del commit.
- ZIP real generado por el servicio sobre la fixture sintética: .NET
  `System.IO.Compression.ZipFile` abre las tres entradas. Un lector Node
  independiente comprueba tres CRC32, directorio central, EOCD y los dos
  tamaños/hashes del manifiesto; extrae la SQLite a una carpeta nueva y abre con
  SQLite estándar **3.50.4**, en solo lectura, sin funciones de Autofinance ni
  sidecars. Contrasta las 12 tablas, esquema, identidad/revisión int64, conteos,
  integridad y claves. Rechaza bytes y cinco metadatos deliberadamente alterados.
  La prueba permite generar de nuevo la fixture mediante
  `AF_PORTABLE_SYNTHETIC_ZIP` apuntando a un archivo temporal nuevo; nunca a un
  archivo o base del usuario. No se añade la SQLite binaria al repositorio.
- `node docs/ep-027/verificar-contrato.mjs`: correcto. Formato de los archivos
  propios y `git diff --check`: correctos.

Las protecciones existentes de copias requieren resolver antecesores como
`C:\Users\carlo`, que el sandbox deniega; las pruebas se ejecutaron con acceso
fuera del sandbox, sin rebajar esas protecciones. Las ejecuciones Flutter de
la extracción usan una carpeta de build propia para no bloquear el DLL SQLite
del control de calidad del checkout compartido.

No se modifican plataformas y no se ejecutan builds ni arranques nativos como
evidencia de este ticket. La verificación integrada desde la app real
Windows/Android, guardado nativo y guía general corresponden a T04/T06/T07/T08;
este backend no acredita aceptación visual ni cierre de épica.

Se conserva la rama configurada `ticket/ma-tsk-193`. El commit incluye solo
archivos propios y la nueva exportación pública; la línea concurrente de Drive
y sus demás cambios quedan fuera.
