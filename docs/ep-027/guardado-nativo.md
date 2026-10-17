# MA-TSK-222 · Guardar ZIP en Windows y Android

Puerto implementado sin UI de producto (T06) ni dependencia del dialecto CSV.
Se usa el ticket íntegro facilitado por el usuario; no hay conector Epic Board
disponible y no se ha actualizado su estado.

## Integración

`ExportSaver` se consume desde
`lib/features/synchronization/export_saving.dart`; app inyecta
`NativeExportSaver` desde su adaptador de datos. Invocar solo por acción
explícita, una vez terminado/verificado/cerrado el ZIP del exportador T02/T03:

```dart
final result = await saver.save(ExportSaveRequest(
  zipPath: prepared.zipPath,
  suggestedName: 'autofinance-datos-20261016T120000Z.zip',
));
```

El consumidor mantiene vivo el temporal hasta recibir el resultado y después
llama a `prepared.dispose()` en `finally`, incluso al cancelar o fallar. Este
puerto no elimina el origen, no prepara ZIP, no abre SQLite, no hace snapshots,
no toca el catálogo privado y no conecta Drive ni servicios de envío.

El nombre sugerido se limita a `autofinance-(datos|copia|prueba)` más un sufijo
opcional de dígitos, `T`, `Z`, guiones o guiones bajos y `.zip`. Así evita
interpolar cuentas/personas; el usuario puede cambiar el nombre en el selector.
El MIME es siempre `application/zip`. Solo se transmite la ruta temporal y el
nombre: el canal jamás transporta los bytes del ZIP.

Resultados: `ExportSaved` (ubicación opcional), `ExportSaveCancelled`,
`ExportSaveFailed` (permiso, espacio, conflicto, destino no disponible, origen
inválido, escritura o en curso). `message` ofrece explicación en español.
Si `incompleteMayRemain` es verdadero, la UI debe advertir además que puede
quedar un documento incompleto en el destino y permitir repetir con otro nombre.
No mostrar éxito hasta que termine este Future; el resultado no promete
persistencia remota del proveedor. Un conflicto exige volver a elegir destino.

## Garantías efectivas

### Windows

`IFileSaveDialog`, sin carpeta fijada, obtiene una ruta del sistema de archivos.
El diálogo modal bombea mensajes; la transferencia se ejecuta en otro hilo con
búfer de 64 KiB y vuelve a la cola de la ventana para resolver el canal. Se abre
el origen sin compartir escritura. El destino usa `CREATE_NEW`, también frente
a carreras tras cerrar el diálogo. No ofrece confirmación de reemplazo:
el puerto rechaza el destino existente con `conflict`; no lo trunca.

Se comprueban lecturas, escrituras parciales, `FlushFileBuffers` y cierre antes
de éxito. Al fallar, `FileDispositionInfo` elimina **mediante el handle propio**
el archivo recién creado, sin buscar ni borrar por una ruta que otro proceso
pueda haber sustituido. Si falla la limpieza/cierre se comunica el posible
incompleto. No hay publicación atómica: el nombre final puede existir mientras
se copia, aunque el handle impide lectura compartida. No hay readback en el
puerto ni garantía adicional frente a desconexiones o sistemas de red.

### Android

`ACTION_CREATE_DOCUMENT` + `CATEGORY_OPENABLE`, MIME ZIP; el usuario escoge
document provider y nombre. Se trata la URI `content://` directamente con
`ContentResolver`, sin ruta de disco ficticia, root ni permisos generales.
No se llama a `takePersistableUriPermission`: únicamente se usa la concesión
temporal del resultado; no se guarda ni se solicita acceso persistente.

El contrato de `ACTION_CREATE_DOCUMENT` crea un documento nuevo y resuelve
nombres repetidos sin sobrescribir el anterior. Se rechaza además un resultado
con tamaño publicado positivo antes de abrir la salida. El puerto confía en
que el proveedor respete CREATE_DOCUMENT; no puede demostrar identidad nueva
en un proveedor arbitrario que incumpla ese contrato.

Un executor copia por bloques de 64 KiB, comprueba cancelación al destruir el
canal, hace flush y cierra los streams antes de éxito. Los errores del proveedor
y de cierre producen fallo. Se intenta borrar únicamente la URI nueva de esta
operación mediante `DocumentsContract.deleteDocument`; si no se consigue, se
advierte del posible incompleto. Nunca se borra la URI rechazada por conflicto.

No existe atomicidad, fsync o verificación de lectura universal para proveedores
(incluidos pipes o ubicaciones remotas). El éxito acredita escritura y cierre
sin error notificado, **no** durabilidad remota ni subida completada. El usuario
puede escoger un proveedor remoto desde el selector del sistema; Autofinance
no inicia llamadas Drive, shares ni envío automático.

Documentación primaria consultada:
[SAF / creación de documentos](https://developer.android.com/training/data-storage/shared/documents-files),
[opciones del selector Windows](https://learn.microsoft.com/windows/win32/api/shobjidl_core/ne-shobjidl_core-_fileopendialogoptions).

## Verificación reproducible

- `flutter test --no-pub test/synchronization/native_export_saver_test.dart test/architecture_test.dart`
- `./scripts/check-quality.ps1`
- `flutter build windows --release --no-pub --dart-define=APP_ENV=test`
- `flutter build apk --debug --no-pub --dart-define=APP_ENV=test` (JDK 17).

Recorrido nativo interactivo, en ambos dispositivos:

```text
flutter drive --debug --no-pub -d windows --target=integration_test/export_save_test.dart --driver=test_driver/export_save.dart --dart-define=APP_ENV=test --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false
```

Repetir con `-d emulator-5554` o teléfono autorizado. No es un test desatendido:
1) cancelar selector; 2) guardar en destino público nuevo; 3) guardar de nuevo
con el mismo nombre (conflicto Windows / documento distinto Android); 4) esperar tres
segundos y guardar en **otro** nombre después de desaparecer el origen.
El test genera un ZIP STORE genérico de 4 MiB (`prueba.md` sintético), valida
origen inexistente, cancelación, resultado/URI y fallo por pérdida del origen.
En Windows compara SHA-256 desde el destino. En Android extraer el documento
por un lector independiente/ADB del emulador y comparar el hash registrado en
`.tools/222-evidence/android.json`. La carpeta temporal propia se elimina;
el ZIP público de prueba queda disponible para inspección.

Los dobles cubren todos los códigos de error, ausencia de plugin, protocolo
inválido, operación ocupada y resolución solo tras confirmación nativa. No
demuestran espacio agotado, desconexión física, proveedor remoto ni limpieza
denegada en dispositivos reales; registrar por separado la evidencia nativa.

## Resultado del 2026-10-17

La [evidencia estructurada](evidencia-guardado-nativo.json) contiene únicamente
el fixture sintético y resultados, sin rutas personales ni identificadores del
dispositivo. Los logs de trabajo quedan ignorados bajo `.tools/222-*`.

- 33 pruebas correctas: puerto/canal, exportador CSV, copia portable y arquitectura.
- Análisis estático completo final: sin incidencias. Formato y `git diff --check`: correctos.
- Builds de producto Windows release y Android debug correctos, `APP_ENV=test`;
  Android con JDK 17 mediante configuración local aislada, sin cambiar toolchain/lockfile.
- Arranque con development, test, production e invalid-synthetic: correcto.
- Recorridos reales Windows y Android: cancelación, origen inexistente, guardado,
  nombre repetido y origen perdido. Windows devuelve `conflict` sin cambiar el
  SHA-256 anterior. Android API 37 / proveedor Downloads crea otra URI y nombre
  con `(1)`; ambos ZIP conservan sus bytes. El incompleto de la operación fallida
  desaparece y se conserva el anterior en ambas plataformas.
- Lectura independiente: `.NET ZipArchive`, tamaño y SHA-256; en Windows también
  contenido sintético completo. ADB `pull` sin root extrae ambos documentos Android:
  los dos hashes coinciden con el ZIP Windows. El ZIP tiene 4.194.420 bytes y
  `prueba.md` contiene 4.194.304 bytes; hash en el JSON de evidencia.

La prueba Windows inicial activó accesibilidad durante el recorrido y terminó
con un `SemanticsHandle` activo del framework; la repetición visual sin sondear
accesibilidad pasó completa. El emulador Android inicial devolvía `DEAD_OBJECT`;
tras arranque en frío del AVD de solo lectura se completaron ambos recorridos.
Esto no acredita proveedores remotos, almacenamiento físico desconectado ni un
dispositivo Android físico. No es aceptación visual de T06 ni cierre de T08.

`check-quality.ps1` se ejecutó completo hasta el resultado de la batería: 1.983
pruebas correctas y 12 fallidas. Tres fallos de recorridos (`report_drilldown_journey`
Windows y `pending_lifecycle` Windows/Android) ya figuran en el registro previo
MA-TSK-221; no se modifican esas funcionalidades. Otros nueve resultados de
`drive_two_installations` / `local_recovery_journey` incluyeron bloqueos al borrar
archivos temporales (error 32), mientras se verificaban runners nativos. Se
repiten esos dos archivos en serie con build aislado. La batería general no se
presenta como verde. Los cuatro arranques del
script se ejecutaron después por separado y pasaron.

Repetición aislada: **17 pruebas correctas**, incluidos todos los casos de Drive
y recuperación local que habían fallado. No se cambió su código para repetirlas.
Permanecen los tres fallos de recorridos previos citados; no se ha repetido toda
la batería tras aislar los builds ni se ha corregido código ajeno a MA-TSK-222.
