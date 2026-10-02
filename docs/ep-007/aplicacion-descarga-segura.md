# MA-TSK-067 · Aplicación segura de la descarga

`createDriveDownloadApplication` compone el flujo manual para Windows y Android
sin consultar Drive. El consumidor llama `downloadAndApply` únicamente desde
«Descargar última copia» y presenta la revisión de MA-TSK-065: cuenta, fecha,
versión y aviso de pérdida de cambios. Una relación desconocida también exige
confirmación. El resultado expone el mensaje de éxito, los metadatos de la
versión instalada y el ID del respaldo anterior; no incorpora una nueva pantalla.

Después de descargar y validar, el coordinador drena las escrituras con EP-006.
Vuelve a comprobar cuenta/carpeta/archivo y metadatos remotos, revisión local y
epoch de restauración. Si cambian, exige empezar de nuevo; no reutiliza el permiso
para otra imagen o para descartar ediciones posteriores.

La candidata se copia dentro del staging privado de restauración. Se comprueban
tamaño y SHA-256, se valida SQLite y se migran esquemas publicados solo en esa
copia. EP-006 crea el respaldo previo consistente, cierra, aísla main/sidecars,
sustituye y reabre con validación integral. La descarga exige una base anterior
utilizable: no instala sin respaldo recuperable. Usa el diario y la recuperación
de MA-TSK-055/056, conservando las copias manuales y la retención local existente.

La operación de descarga se persiste antes del intercambio. Solo después de la
reapertura válida y del commit del nuevo epoch se vinculan versión remota y
revisión descargada, todavía bajo exclusión de escrituras. El callback recibe
ese epoch del coordinador: el diario propio aún abierto no constituye una
recuperación ajena. Fuera de ese callback sigue vigente el lector conservador
de contraste. El resultado exitoso muestra la fecha y versión de la imagen
descargada; no promete que otro dispositivo no haya subido después.

Cancelación o fallo antes del vínculo revierte o conserva la anterior. También
se revierte si falla la persistencia del vínculo. Si la reversión no termina,
se bloquea el acceso y se informa recuperación necesaria. Un fallo después de
guardar el vínculo y antes de completar el diario no acredita sincronía con
una base revertida: el epoch anterior invalida esa comparación.

Al reiniciar, EP-006 resuelve SQLite antes de abrirla, sin red. Una operación
que no alcanzó el vínculo continúa pendiente; no se deduce éxito por compartir
dataset/revisión. Una nueva pulsación de descarga puede abandonar ese pendiente
solo cuando el contraste local es fiable y bajo el bloqueo de restauración;
vuelve a descargar y solicitar revisión. Nunca abandona una subida pendiente
ni una operación de otro proceso que mantenga el bloqueo. No hay reintentos
automáticos. La cancelación después del vínculo duradero no revoca el commit.

## Verificación

`test/synchronization/safe_drive_download_application_test.dart` usa SQLite real,
datos sintéticos y HTTP simulado. Cubre confirmación rechazada, composición
pasiva, primera descarga sin catálogo previo, contenido de todas las tablas,
versión/fecha, respaldo y recuperación manual; fallos en respaldo/cierre/
sustitución/reapertura y guardado de sincronía; cambios locales/remotos y
manipulación de candidata antes de aplicar; cancelación en cuatro fases;
interrupciones antes y después de validar, reinicio sin red y repetición manual.
Las interrupciones de este ticket se inyectan como fallo persistente de E/S;
los procesos terminados realmente siguen cubiertos por MA-TSK-059.

La comprobación con Drive real, OAuth y dispositivos Windows/Android queda
pendiente del entorno de EP-005. No se han utilizado credenciales ni datos
personales. Los logs de ejecución son locales y no se incluyen en Git.

Resultados del 2026-10-02:

- `scripts/check-quality.ps1` en el checkout compartido: formato y análisis
  correctos, 759 pruebas y las cuatro variantes de arranque aprobadas.
- Copia aislada de HEAD más únicamente los cambios de este ticket: análisis de
  los ocho archivos/módulos seleccionados correcto y las 17 pruebas nuevas
  aprobadas; las 97 pruebas existentes de restauración, estado y descarga
  también pasan por separado. No se incorpora código de subida ajeno al commit.
- `flutter build windows --release --no-pub --dart-define=APP_ENV=test` en esa
  copia aislada: correcto. No se ha hecho recorrido manual con Drive real.
- APK debug: bloqueado por ausencia de Android SDK.
- Calidad global de la copia aislada: el código previo de MA-TSK-066 importa
  `drive_upload_factory.dart` y `domain/drive_upload.dart` de MA-TSK-064, y utiliza
  ampliaciones de estado de subida todavía sin confirmar en el checkout. Esas
  dependencias previas impiden el análisis global sin los cambios concurrentes;
  se conservan fuera de MA-TSK-067. La comprobación del checkout compartido y
  la comprobación aislada de los módulos modificados se distinguen expresamente.
