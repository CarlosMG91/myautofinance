# MA-TSK-117 · Selección y lectura local

`LocalCsvSelector.select()` devuelve `LocalCsvSelected(name, bytes)`,
`LocalCsvCancelled` o `LocalCsvFailed(code)`. Los códigos distinguen acceso
denegado, documento no disponible, fallo de lectura y operación en curso.
El dominio es Dart puro y admite dobles. La composición está en
`lib/app/local_csv_selector_factory.dart`; construir el servicio no abre nada.
No se incorpora pantalla, ruta, importación, persistencia ni servicio de EP-012.

El adaptador de datos usa el canal `autofinance/local_csv`, método `select`
sin argumentos. El host responde `null` al cancelar, o un mapa con `name`
y bytes binarios (`Uint8List` en Dart). Los errores nativos usan `accessDenied`,
`unavailable`, `readFailed` y `busy`, sin rutas ni contenido en el diagnóstico.
Una respuesta incompleta o mal formada se considera fallo de lectura.

## Hosts y conservación del archivo

- Windows: `IFileOpenDialog` con selección única, filtro CSV y alternativa
  «Todos los archivos». `CreateFileW` abre solo para lectura y `ReadFile` lee
  bloques binarios en un hilo de trabajo. La respuesta se entrega en el hilo
  de plataforma por un mensaje de ventana. No se añade el archivo a recientes
  ni se cambia el directorio de trabajo. Se cierra el handle incluso si falla.
- Android: `ACTION_OPEN_DOCUMENT` con `CATEGORY_OPENABLE`, selección única y
  acceso temporal de lectura. `ContentResolver` obtiene el nombre visible y
  abre directamente el URI. Consulta y lectura se ejecutan en un executor;
  la respuesta vuelve al hilo de plataforma. Se usa `*/*` para admitir CSV
  cuyo proveedor declara MIME de texto u otro tipo: el título orienta al CSV,
  pero el lector es quien valida el contenido. No se consulta una ruta física,
  no se toma permiso persistente ni se pide permiso amplio de almacenamiento.

Ambos hosts cierran el recurso de lectura; nunca escriben una copia del CSV.
Los bytes se devuelven completos, sin decodificar, cambiar saltos ni eliminar
BOM. El resultado Dart hace una instantánea binaria inmutable. El flujo futuro
puede pasarla a `ImportFile.fromBytes` y al lector histórico; debe soltar la
referencia al terminar la sesión. Archivo vacío o extensión distinta no se
rechazan aquí. No se expone un resultado parcial ante un error de lectura.
No se limita el tamaño del CSV artificialmente; una carga exige memoria para
el archivo completo y su transporte. Un fallo de asignación nativo se informa
como fallo de lectura, sin prometer recuperación de una terminación del proceso
por el sistema operativo.

## Dependencias y fuentes

No se añade paquete: los SDK nativos y `MethodChannel` de Flutter cubren
selección, lectura binaria y clasificación de errores. Esto evita copias
temporales y permite distinguir los errores del proveedor. No cambian
`pubspec.yaml`, `pubspec.lock`, `toolchain.json` ni permisos del manifiesto.
Se siguen [Storage Access Framework de Android](https://developer.android.com/training/data-storage/shared/documents-files)
y [IFileOpenDialog de Windows](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-ifileopendialog).

El ticket y la épica completos se consultaron en el mensaje del usuario.
Esta sesión no dispone de herramientas Epic Board; no se cambia el tablero.

## Verificación

Pruebas del selector con canal simulado y doble del puerto: bytes originales
con BOM, CRLF, LF, Unicode y byte cero; SHA-256 idéntico; instantánea inmutable;
nombre sin extensión CSV; archivo vacío; cancelación; errores separados;
host ausente; respuesta corrupta; selección simultánea y reintento.
Las 13 pruebas del selector y las dos de arquitectura pasan.

Comprobado el 2026-10-07 con Flutter 3.47.0 y Dart 3.13.0:

- `scripts/check-toolchain.ps1` y `flutter pub get --enforce-lockfile` correctos.
- Formato sin cambios pendientes y análisis sin incidencias.
- `scripts/check-quality.ps1`: 1246 pruebas correctas y un fallo en
  `wealth_photo_screen_test.dart`, caso «Ruta conserva febrero…», que no
  encontró «Foto completa». El log también muestra SQLite ya cerrado.
  Al repetir ese archivo junto al selector y arquitectura pasan las 30 pruebas.
  No se modifica Patrimonio; el control completo no se declara aprobado.
- Arranque con `APP_ENV=development/test/production/invalid-synthetic`:
  las cuatro comprobaciones correctas, ejecutadas tras la batería general.
- `flutter build windows --release --no-pub --dart-define=APP_ENV=test`: correcto.
- `flutter build apk --debug --no-pub --dart-define=APP_ENV=test`: correcto,
  también con el JDK 17 fijado. Se restauró después la configuración local
  anterior de Flutter.
- `git diff --cached --check`: sin errores de espacios.

La resolución de dependencias y las compilaciones se repitieron fuera del
sandbox por restricciones de red y acceso a las cachés nativas. No fue necesario
actualizar dependencias ni SDK. Los logs locales están en
`.tools/ma-tsk-117-*.log` (ignorados por Git).

La apertura interactiva de los selectores y los fallos reales de proveedores
(revocación de permiso, archivo eliminado, fallo a mitad de lectura) requieren
verificación en dispositivos: los dobles prueban el contrato y el adaptador
Dart, no sustituyen esa comprobación nativa. No se conecta aún al flujo visual.
