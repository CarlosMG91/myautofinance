# MA-TSK-063 · Transferencia binaria manual

`DriveTransferClient` extiende las capacidades de EP-005 sin cambiar el puerto
de metadatos. `DriveAccessInstallation.transfers` conecta Windows y Android al
mismo proveedor de credenciales y cliente HTTP que metadatos. Construir la
instalación no inicia red. No se conecta al arranque ni incorpora pantallas.
Se ha usado el ticket completo proporcionado por el usuario; no hay herramienta
Epic Board disponible en esta sesión ni se ha cambiado su estado.

## Subida y frontera de publicación

El consumidor entrega una ruta a un snapshot consistente, validado e inmutable
de EP-004/006, cuenta y carpeta verificadas y, para actualizar, el ID de la copia
conocida. Una primera subida usa POST con nombre `autofinance.sqlite`, padre y
marca `databaseCopyV1`; una actualización usa PATCH al mismo ID. Nunca se crea
una copia vacía mediante una petición separada de metadatos.

El inicio solicita una sesión reanudable; las peticiones posteriores usan PUT,
Content-Range y bloques de 256 KiB (el último puede ser menor). Solo se mantiene
un bloque de la base en memoria. Un acuse 308 debe confirmar exactamente el
prefijo enviado; un rango ausente, retrasado o incoherente detiene la operación.
No se reenvían bloques automáticamente ni se persiste la URL de sesión.
Las URLs de sesión se restringen a HTTPS, www.googleapis.com y el endpoint de
upload Drive v3; se deshabilitan redirects para evitar enviar tokens a terceros.

`onProgress` comunica bytes confirmados por Drive, total y fase. Antes del último
bloque se informa `beforeCommit` y se espera la función obligatoria del mismo
nombre. **El coordinador debe volver a consultar identidad/versión remota y
detener divergencias observables**, además de acreditar la acción manual. Puede
fallar o esperar la decisión del flujo. La cancelación durante esa espera evita
el último PUT. `committing` señala el envío final: desde ese momento no se
garantiza deshacer una publicación remota. La pérdida del acuse o cancelación
durante el último PUT produce `ambiguousResponse`, nunca «Copia subida».

El acuse final debe contener metadatos válidos, tamaño, versión, fecha, padre,
marca e ID esperado. Aun con HTTP 200, un acuse incompleto es ambiguo. El
consumidor registra la versión solo tras ese éxito y según MA-TSK-062; el cliente
de transferencia no cambia el estado de instalación ni las revisiones locales.

No se envía un If-Match inventado a partir de `version`. La evidencia local de
[MA-TSK-061](control-versiones-drive.md) todavía carece de ensayo OAuth real,
aunque el requisito figura completado en el ticket recibido. Se mantiene la
excepción de carrera aceptada por EP-001. Cuando el ensayo acredite una condición
efectiva en el commit reanudable, deberá incorporarse antes de prometer protección
atómica. El gate permite detener divergencias secuenciales, no reserva el archivo.

## Descarga y protección local

GET `alt=media` consume el stream y escribe bloques en un directorio único del
almacenamiento temporal privado entregado por el consumidor. La candidata se
llama `candidate.part`; no se renombra a SQLite activa ni se registra en catálogo.
Debe tener exactamente el tamaño remoto esperado. Un error, timeout o
cancelación cierra el fichero y elimina el staging. Si el disco impide limpiarlo,
se devuelve un fallo local: el huérfano sigue siendo `.part`, nunca una copia
válida. Una respuesta tardía de un transporte abortado no vuelve a escribir.

El resultado `DriveDownloadCandidate` solo acredita transferencia completa.
El coordinador aún debe contrastar metadatos/hash, validar SQLite, respaldar y
restaurar mediante EP-006, y eliminar el temporal tras consumirlo. La base activa
y el catálogo permanecen fuera del alcance del transporte. Interrumpir el
proceso puede dejar temporales sin registrar, que no deben descubrirse como copias.

## Fallos, cancelación y repetición manual

`DriveTransferFailure` conserva un motivo cerrado; los fallos remotos incluyen
`DriveMetadataFailure`, código HTTP y `retryAfter` saneados. Clasifica timeout,
401, 403 (permiso/cuota/límite), 404, 429, 5xx y pérdida de red. Un 5xx durante
el commit conserva `serverUnavailable` dentro de un resultado ambiguo. El límite
configurable `requestTimeout` es por intercambio HTTP completo (30 s por defecto),
incluido el stream de un GET; para bases grandes el coordinador debe configurar
un plazo acorde. El timeout dispara el abort del transporte además de terminar
la espera. El cliente inyectado debe soportar AbortableRequest, como el cliente
HTTP nativo usado en Windows y Android; un falso que lo ignore no puede escribir
posteriormente sobre el staging abandonado.

No se renuevan credenciales ni se abre consentimiento desde una transferencia.
Cada petición acredita cuenta, scope exacto y vigencia. Ante caducidad el flujo
solicita renovación expresamente y vuelve a validar el estado remoto. No hay
logs de tokens, URL de sesión, rutas o contenido; los errores no incluyen cuerpos
ni mensajes remotos. Las callbacks del consumidor tampoco deben registrarlos.

Repetir exige una nueva llamada manual y un nuevo objeto de cancelación si el
anterior fue cancelado. Se inicia otra sesión, sin continuación automática de la
anterior. **Tras un acuse ambiguo, el coordinador debe reconciliar Drive antes de
permitir esa nueva llamada**, conforme a EP-001 y MA-TSK-062/066; no puede asumir
que la publicación falló. `retryAfter` es información, no activa un temporizador.

## Verificación

`test/synchronization/drive_transfer_client_test.dart` usa datos sintéticos y
transporte falso. Cubre rangos y contenido, primera creación, gate, divergencia,
cancelación antes/durante commit, cabeceras tardías, abort/timeout, streaming,
longitud incorrecta, eliminación de parciales, disco, credenciales, errores HTTP,
cuota, metadatos finales inválidos y repetición exclusivamente manual.

Verificación local del 2026-10-02: Flutter 3.47.0/Dart 3.13.0 y verificador de
toolchain correctos; lockfile resuelto sin modificaciones. `check-quality.ps1`
completo: 117 archivos con formato correcto, análisis sin incidencias,
677 pruebas correctas (31 de transferencia) y cuatro variantes adicionales de
arranque correctas. `git diff --check` correcto. Se requirió acceso ampliado para
pub.dev; un intento simultáneo de prueba aislada chocó con la DLL SQLite ocupada
por la suite, por lo que se verificó la versión final con la suite completa.

La verificación real de Drive, OAuth y escritura condicional sigue pendiente;
los falsos no acreditan el comportamiento de los servidores de Google.
Los builds nativos se intentaron: Windows carece del toolchain Visual Studio C++
y Android no tiene SDK configurado. No se afirma validación en dispositivos.

Referencias oficiales contrastadas para el protocolo:
[subidas reanudables](https://developers.google.com/workspace/drive/api/guides/manage-uploads)
y [descarga binaria](https://developers.google.com/workspace/drive/api/guides/manage-downloads).
