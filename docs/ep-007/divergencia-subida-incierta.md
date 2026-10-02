# MA-TSK-066 · Divergencia y subida incierta

Implementación común Windows/Android, manual y sin fusión. Se consultó el ticket
facilitado por el usuario, EP-001 §7.1, la entrega visual aprobada de MA-TSK-019
y la captura `.tools/board-059.json` del tablero My autofinance. No hay conector
Epic Board disponible; la captura no acredita su estado actual ni se modificó.

## Entradas y decisiones

`createReconcilingDriveUploader` es la entrada de «Subir copia». Envuelve el
coordinador validado de MA-TSK-064. Si hay una operación pendiente durable,
esta pulsación solo consulta: nunca captura ni publica otra copia, incluso si
reconoce éxito. El coordinador original continúa bloqueando reenvíos directos.

`createDriveReconciliation` permite «Volver a consultar Drive». Busca la copia
única en la cuenta/carpeta de la sesión explícita; para una creación pendiente
descubre el ID real sin enviar el ID provisional local a Drive. Comprueba ID,
versión positiva, fecha, tamaño, marca de operación, SHA-256 y checksum MD5.
Una actualización reconocida debe tener versión superior a la base conocida.
El hash privado SHA-256 es una marca, y el MD5 consultado es el checksum del
contenido de Drive; esta consulta no sustituye la validación SQLite al descargar.

| Evidencia | Resultado | Efecto |
|---|---|---|
| Marca, hashes y versión acreditan la publicación pendiente | Publicación comprobada | Registra la imagen capturada, fecha, versión e ID; no reenvía |
| Versión distinta con otra marca, o primera creación con otra copia única | Conflicto confirmado | Detiene subida; conserva ambas bases y la operación pendiente |
| Red/OAuth/disco, varias candidatas, metadatos incoherentes o marca propia sin hash correcto | Indeterminado | Conserva pendiente; exige otra consulta |
| Misma versión sin marca propia durante subida incierta | Indeterminado | No supone que una petición en vuelo haya fallado |
| Sin pendiente y versión igual a la conocida | Coincidente | Registra solo la observación; no publica |

La publicación reconocida vincula la revisión del snapshot, no las ediciones
posteriores. Un epoch restaurado o un error al guardar el acuse conserva la
incertidumbre. Cuenta/carpeta distintas no autorizan dar por completada la subida.
No se consulta desde arranque, temporizadores, edición ni cierre.

## Opciones y descarga

`DriveConflictFlow` expone «Conservar datos locales», «Descargar última copia» y
«Volver a consultar Drive», con resultados y errores en español. Conservar no
consulta ni altera bases o estado pendiente. Descargar vuelve a consultar;
si sigue indeterminado no inicia la transferencia. En un conflicto confirmado,
la elección explícita abandona el pendiente local e invalida la correspondencia.
Esto no cancela una petición remota que ya esté en vuelo ni promete revertirla.

La descarga se entrega al coordinador de MA-TSK-065: presenta cuenta, fecha,
versión y advertencia de pérdida, exige la confirmación que corresponda y valida
en staging sin instalar. El reemplazo y respaldo seguro pertenecen a MA-TSK-067;
el montaje del diálogo/pantalla de Drive pertenece a MA-TSK-068. Esta entrega
ofrece las acciones conectadas y no añade una pantalla financiera.

## Límite de dos escritores

La simulación usa dos directorios privados con SQLite real y estado durable
independiente. Ambos parten de la misma imagen/versión; A pasa la comprobación
previa, B consulta todavía esa versión y publica, y después A publica. Ambos
reciben éxito, queda activa A y la siguiente consulta de B detecta divergencia.
No hay If-Match acreditado, bloqueo remoto, elección automática ni garantía de
retención del historial. La prueba simulada no demuestra capacidad condicional
del servicio: el ensayo OAuth real de MA-TSK-061 sigue pendiente según su informe.

## Verificación y publicación

Las pruebas usan datos sintéticos, transporte HTTP falso, snapshots SQLite,
hashes, estado persistido y reinicio reales. Cubren creación y actualización
sin acuse, cancelación después de enviar, cambios locales durante commit,
fallo de consulta, hashes incoherentes, candidatas múltiples, conflicto,
opciones de conservación/descarga y carrera de dos escritores.

El checkout comenzó con cambios ajenos pendientes de MA-TSK-064, incluidos su
factory y contratos de operación/hash. Se conservaron íntegros; no forman parte
del commit de MA-TSK-066. La verificación local incluye esa dependencia presente
en el checkout. `origin/main` consultado seguía en MA-TSK-065 y no contenía esos
cambios de MA-TSK-064: el commit de este ticket requiere publicarlos por su
propietario antes de que el remoto pueda compilar esta funcionalidad.

Comprobaciones del 2026-10-02:

- Flutter 3.47.0 / Dart 3.13.0 y `check-toolchain.ps1`: correctos.
- `check-quality.ps1`: lockfile resuelto sin cambios, formato correcto, análisis
  sin incidencias, **742 pruebas** correctas y cuatro variantes de arranque.
- Nueve casos nuevos de resolución/descarga/carrera incluidos en esa batería.
- `git diff --cached --check`: sin errores de espacios.

Las primeras pruebas en sandbox fallaron por bloqueo nativo/almacenamiento y
pub.dev; las comprobaciones finales terminaron con ejecución ampliada. No se
ejecutaron builds de plataforma, dispositivos ni Drive/OAuth reales: este
ticket no cambia código nativo y la carrera comprobada es una simulación.
