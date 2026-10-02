# MA-TSK-065 · Descargar y validar antes de aplicar

Se implementa el ticket completo facilitado por el usuario. No hay herramienta
Epic Board disponible en esta sesión; no se ha consultado ni modificado el tablero.

`createDriveDownloader` compone pasivamente el flujo común de Windows/Android.
La entrada pública es `features/synchronization/drive_download.dart`. Su método
`download` se invoca exclusivamente desde la acción manual «Descargar última
copia». No se añade una pantalla de producto en este ticket ni una consulta al
arranque. La integración visual debe seguir EP-002 y su aprobación MA-TSK-019.

Antes de transferir, el callback obligatorio `review` recibe cuenta, fecha,
versión y estado local. Debe presentar esos datos y devolver `true` tras la
confirmación expresa si `requiresConfirmation` es verdadero. Solo el estado
`clean` permite continuar sin confirmar pérdida de cambios; un estado desconocido
también requiere confirmación. `false`, cierre del diálogo o cancelación del
token conservan la base. La cancelación del token termina incluso si el diálogo
todavía no ha respondido. Una operación pendiente exige resolverla primero.

La transferencia de MA-TSK-063 escribe en un staging exclusivo dentro de soporte
privado `sqlite/drive-downloads`. Se exige longitud remota positiva, se comprueba
la longitud recibida y del archivo y se contrasta MD5 cuando está disponible.
Se calcula SHA256 local y se verifica que la inspección no cambió la imagen.
`SqliteRestoreImagePolicy` de EP-006/EP-004 inspecciona sin escribir: identifica
Autofinance, comprueba esquema admitido, integridad SQLite, claves externas y
reglas financieras. Una imagen antigua admitida permanece sin migrar; la futura
aplicación deberá migrar exclusivamente una copia de trabajo con EP-006.

Tras validar, se vuelve a consultar identidad única, cuenta, carpeta, versión,
fecha, tamaño y hash remotos. Un cambio, duplicidad o fallo impide devolver la
candidata. Se comprueban también revisión/linaje local, estado de sincronización
y época de restauración: una edición durante revisión o descarga exige empezar
otra revisión. Una lectura `clean` desactualizada nunca evita la confirmación.

`ready` significa **candidata validada**, no «Copia descargada» ni base instalada.
El resultado incluye imagen, ruta privada, SHA256, estado local revisado y
metadatos remotos. No se crea respaldo previo, se cierra/sustituye la base ni se
escribe una operación de descarga o versión conocida. La sesión Google tampoco
se sustituye. La futura aplicación segura debe volver a verificar copia remota,
estado local y hash al aplicar; la consulta final aquí no reserva una versión
remota indefinidamente.

El consumidor conserva el coordinador y llama `discard(candidate)` al cancelar
o después de consumir la imagen. Solo se admiten objetos de candidatas creados
por ese coordinador. Los rechazos limpian el directorio exclusivo, incluidos
parciales del transporte; no se aceptan rutas externas ni enlaces en la ruta de
trabajo. Un fallo de limpieza se comunica con `cleanupPending`, sin presentar
ese staging como una copia utilizable. No se eliminan directorios ajenos.

Los resultados distinguen cancelación, ausencia/ambigüedad/inaccesibilidad remota,
metadatos inválidos, red/transporte, longitud/hash, imagen inválida con motivo
específico de EP-006, cambio remoto/local y operación pendiente. No hay reintentos
automáticos ni mensajes remotos o credenciales en las excepciones públicas.

## Verificación

Las pruebas usan bases sintéticas, política SQLite, estado de instalación y
transporte reales; HTTP simulado sustituye exclusivamente Drive. Cubren revisión,
confirmación/cancelación, base limpia y con cambios, fallos en las tres fases de
red, versión/duplicidad remota, longitud incompleta, hash ausente/incorrecto,
SQLite corrupta/ajena/futura, cambios locales, cancelación durante validación,
mutación del staging, disco, sesión cambiada y concurrencia del coordinador.
Comprueban conservación de base y sesión, estado sync y eliminación de parciales.
Los casos defensivos alteran además el resultado del transporte o el staging
después de inspeccionarlo para comprobar límites de rutas, longitud y limpieza.

No se acredita OAuth/Drive real ni ejecución en dispositivos con estas pruebas.

Comprobación aislada del índice Git (sin MA-TSK-064): formato correcto en 122
archivos, análisis sin incidencias y 54 pruebas afectadas correctas, 35 de ellas
de descarga. La suite aislada detectó el borrado de una ruta sustituida por un
archivo; tras añadir la comprobación de tipo, estas pruebas verificaron la
corrección. La resolución aislada respetó el lockfile, pero la generación de
enlaces de plugins Windows impidió completar allí `check-quality.ps1`; formato,
análisis y pruebas afectadas se ejecutaron directamente con `--no-pub`.

En el checkout completo, `check-quality.ps1` final terminó correctamente:
Flutter 3.47.0/Dart 3.13.0, lockfile sin cambios, formato, análisis, suite completa
y las cuatro variantes de arranque. `git diff --cached --check` correcto. No se
modificaron plataformas ni se ejecutaron builds nativos en este ticket.
