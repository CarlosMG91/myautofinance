# MA-TSK-048 · Localización de la copia remota

`DriveCopyLocator`, exportado por `synchronization.dart`, recibe `DriveAccess`
y `DriveMetadataClient` por constructor. Es Dart común a Windows y Android;
construirlo no restaura sesión ni hace red. `findCopy()` es una consulta del
futuro flujo manual, tras obtener acceso y resolver/vincular la carpeta con
`DriveFolderLocator` (MA-TSK-047). No se conecta al arranque ni añade pantallas.

Se implementa el ticket completo facilitado por el usuario. No hay conector
Epic Board disponible en esta sesión; no se ha consultado ni cambiado el estado
actual del tablero. Se revisaron los contratos de sesión, carpeta y metadatos,
la arquitectura EP-003 y la copia manual de EP-001 §7.1.

## Identidad de la copia

El nombre objetivo de la primera subida es **`autofinance.sqlite`**, publicado
como `driveAutofinanceCopyName`. Su identidad se descubre por
`appProperties={autofinanceRole: databaseCopyV1}`
(`driveAutofinanceCopyProperties`), común a ambas plataformas del mismo proyecto
OAuth. La futura épica de subida deberá asignar esta marca al publicar la
primera copia válida. Este ticket solo define y consulta el contrato: no escribe
la marca, no crea archivos vacíos ni transfiere contenido.

El nombre actual puede cambiar: se devuelve el de Drive, manteniendo ID y marca.
Un archivo ajeno llamado `autofinance.sqlite` no se adopta por nombre. Tampoco
se elige entre varias candidatas por nombre, versión o fecha.

`findCopy(knownCopy: DriveCopyBinding(...))` acepta opcionalmente una referencia
de copia ya conocida con cuenta, carpeta e ID. El futuro consumidor será
responsable de conservarla fuera de la copia SQLite; el localizador no tiene
caché ni persistencia propia. Rechaza referencias de otra cuenta o carpeta antes
de hacer red. Un ID conocido debe conservar marca y pertenencia a la carpeta:
no acredita por sí solo que el recurso siga siendo la copia de la aplicación.

## Consulta y resultado

En cada consulta se comprueba sesión activa y permiso exacto `{drive.file}`.
Se obtiene el ID real de Mi unidad y se revalida la carpeta vinculada: ID,
marca, MIME de carpeta, ausencia de papelera y padre único igual a la raíz.
Si existe referencia conocida, se consulta su ID. Después se buscan todas las
páginas por marca dentro de la carpeta, con `trashed=false`, sin filtro de
nombre ni MIME. Se verifica de nuevo la pertenencia y la identidad de cada
candidata; se rechazan carpetas, accesos directos y documentos nativos Google.

Se combinan las respuestas por ID. Un mismo ID repetido no es un duplicado;
la respuesta de lista posterior aporta sus metadatos actuales. La referencia
conocida no tiene preferencia sobre otras candidatas. La sesión, cuenta y
carpeta se comprueban después de cada espera remota, antes de continuar o
devolver resultados. Un cambio de cuenta, carpeta, caducidad o desconexión
descarta el resultado de la consulta anterior.

| `DriveCopyStatus` | Resultado del ticket | Datos |
|---|---|---|
| `present` | presente | `copy` con ID, nombre actual, `version` y `modifiedTime` obligatoriamente completos |
| `noCopy` | sin_copia | Consulta completa sin candidatas, sin crear recursos; esperar a la primera subida válida |
| `ambiguous` | ambiguo | Lista inmutable de metadatos de todas las candidatas, sin `copy` seleccionada |
| `inaccessible` | inaccesible | Motivo tipado de identidad/ubicación, sesión o fallo de metadatos; nunca equivale a ausencia |

Todos los resultados conservan la cuenta inicial y el vínculo de carpeta de la
consulta. Solo pueden faltar cuando no hay sesión/carpeta local; una instalación
desconectada sin identidad devuelve `inaccessible` con cuenta nula. Tras un
cambio de cuenta en curso, el fallo conserva la cuenta consultada, no atribuye
sus datos a la nueva. Una nueva llamada vuelve a usar la cuenta activa.

`DriveCopyIssue` explica carpeta no seleccionada, carpeta inválida, copia
inválida o copia fuera de la carpeta. `accessIssue` conserva el código de sesión.
`metadataFailure` conserva `DriveMetadataFailure`, incluido HTTP y `retryAfter`.
Un 404 de carpeta o ID conocido es `inaccessible`: Drive no distingue ausencia
de falta de acceso. No se sustituye silenciosamente por otro ID ni se anuncia
`sin_copia`. Un archivo conocido en papelera también es inaccesible; la búsqueda
por marca excluye papelera. Una lista incoherente/incompleta o un fallo en otra
página nunca se interpreta como lista vacía.

La versión se conserva como cadena decimal de Drive, sin convertirla a entero
ni confundirla con la versión del esquema SQLite. La fecha procede de
`modifiedTime` (el adaptador HTTP la normaliza a UTC). `present` no certifica
integridad o compatibilidad SQLite: eso corresponde a la futura sincronización.
Los metadatos no son una instantánea atómica ni una protección contra carreras
de subida; se deberán reconsultar y proteger al publicar conforme a EP-001.

Las consultas simultáneas sobre el mismo localizador se rechazan con
`DriveAccessFailure(operationInProgress)`. No hay autorización, renovación,
reintentos ni ejecución en segundo plano. No se registran IDs, nombres,
cuentas, mensajes externos o credenciales en `toString()`.

## Verificación

`test/synchronization/drive_copy_locator_test.dart` utiliza exclusivamente
cuentas, sesiones, metadatos y HTTP sintéticos. Cubre cero/una/varias copias,
deduplicación por ID, renombrado con/sin ID conocido, homónimos ajenos,
papelera, carpetas/copias inválidas o movidas, ID conocido inaccesible,
metadatos incompletos, todos los códigos de fallo de metadatos, desconexión,
caducidad y cambios de cuenta durante cada fase de consulta. Comprueba además
referencias de otra cuenta/carpeta, exclusión de consultas simultáneas y el
recorrido con el cliente HTTP de producción: filtros, paginación y peticiones
exclusivamente GET de metadatos, sin `alt=media`, POST ni contenido.

Comprobaciones locales del 2026-10-02:

- `flutter --version` y `scripts/check-toolchain.ps1`: Flutter 3.47.0 y
  Dart 3.13.0 correctos, sin actualizar SDK.
- `flutter pub get --enforce-lockfile`: correcto, sin cambios en dependencias
  o lockfile. El sandbox bloqueó inicialmente pub.dev; la resolución funcionó
  con la revisión de permisos de ejecución.
- Localizador y arquitectura: **60 pruebas correctas**, **58** nuevas.
- `scripts/check-quality.ps1`: **76 archivos Dart** sin cambios de formato,
  análisis sin incidencias, **418 pruebas correctas** y las cuatro variantes
  adicionales de arranque `APP_ENV` correctas.
- Persiste la advertencia previa de Drift sobre instancias múltiples en la
  prueba SQLite integrada; no produjo fallos ni se modificó ese módulo.
- `git diff --check`: correcto. La entrega incluye únicamente los seis
  archivos propios del ticket y utiliza datos sintéticos.

La comprobación con Drive real y dispositivos sigue pendiente del alta OAuth
de MA-TSK-042 documentada en [verificación OAuth](verificacion-oauth.md).
No se requieren builds nativos: este ticket solo añade Dart común, sin cambios
de plataforma o dependencias.

## Fuentes oficiales

Se contrastaron los campos `version`, `modifiedTime`, `parents` y `appProperties`
del [recurso File](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
y las [propiedades privadas](https://developers.google.com/workspace/drive/api/guides/properties).
