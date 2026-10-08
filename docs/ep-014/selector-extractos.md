# MA-TSK-127 · Selección de extractos Openbank

## Puerto y reutilización

Se consultó el tablero **My autofinance** en `http://localhost:4310/api/data`:
MA-TSK-117 figura entregado y MA-TSK-127 no tiene dependencias obligatorias.
Se reutiliza su canal y sus hosts: hay una sola implementación de selección y
lectura nativa para CSV y extractos, sin paquetes adicionales.

`LocalFileSelector.select()` devuelve `LocalFileSelected(name, bytes)`,
`LocalFileCancelled` o `LocalFileFailed(code)`. El dominio es Dart puro;
`accessDenied`, `unavailable`, `readFailed` y `busy` separan las incidencias.
La instantánea de bytes es inmutable. No devuelve rutas ni resultados parciales,
ni decodifica, normaliza, importa o escribe datos. No modifica fotos patrimoniales.

Los nombres `LocalCsv*` son alias compatibles sobre ese mismo contrato.
`NativeLocalCsvSelector` delega en `NativeLocalFileSelector`; el flujo CSV conserva
su interfaz y llamada anterior. La composición para Openbank es
`lib/app/openbank_selector_factory.dart`: `createOpenbankSelector()` no abre el
selector hasta llamar a `select()`. El consumidor recibe el puerto por constructor
y puede sustituirlo por un doble sin implementar ni invocar un lector bancario.

## Selección y lectura

Se conserva el nombre técnico `autofinance/local_csv` para no romper EP-013.
El método `select` sin argumentos sigue orientando a CSV; con
`{'extension': 'xls'}` orienta a extractos. Otras orientaciones se rechazan.
La respuesta sigue siendo `null` al cancelar o `{name, bytes}` al leer completo.
El host compartido impide dos selecciones simultáneas, también entre los flujos.

- Windows: `IFileOpenDialog`, filtro `*.xls` y alternativa «Todos los archivos»;
  selección única. El mismo lector binario de EP-013 abre solo en lectura,
  lee en un hilo de trabajo y cierra el handle.
- Android: `ACTION_OPEN_DOCUMENT`, `CATEGORY_OPENABLE`, selección única y
  permiso temporal de lectura. El título orienta a Openbank XLS y `*/*` permite
  proveedores que declaran MIME distinto. `ContentResolver` consulta el nombre
  visible y lee el URI directamente en segundo plano. No usa ruta física,
  permiso persistente ni permisos amplios de almacenamiento.

Ambos devuelven los bytes completos para una huella SHA-256, sin copia permanente.
El consumidor debe liberar su referencia al terminar la sesión. La carga requiere
memoria para archivo y transporte, como el selector CSV entregado. Un archivo
vacío, binario desconocido o nombre sin extensión XLS se entrega al lector:
la extensión y el MIME no prueban formato. Esta tarea no inventa una muestra
Openbank ni desbloquea la caracterización o el lector pendientes.

La cuenta de destino y la confirmación corresponden al flujo posterior;
el selector no elige cuenta ni da de alta movimientos. No incorpora pantalla.

Se contrastó la implementación con las fuentes oficiales de
[Android Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files)
y [Windows IFileOpenDialog](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-ifileopendialog).
No cambian SDK, dependencias, lockfile ni manifiesto Android.

## Verificación

Las pruebas del canal Openbank cubren la orientación XLS, nombre sin esa extensión,
bytes originales y SHA-256, instantánea inmutable, archivo vacío, cancelación,
errores distinguibles, host ausente, respuestas corruptas, concurrencia y reintento.
Se comprueba el puerto con un doble independiente del lector. La batería existente
CSV se ejecuta como regresión de los alias y del adaptador compartido.

Las 28 pruebas iniciales de ambos selectores y arquitectura pasan.
Flutter 3.47.0 / Dart 3.13.0 comprobados; resolución con
`flutter pub get --enforce-lockfile` y formato correctos, análisis sin incidencias.
La resolución inicial dentro del sandbox falló por acceso a pub.dev; el script
completo se ejecutó después con acceso autorizado y resolvió el lockfile sin cambios.

- `flutter build windows --release --no-pub --dart-define=APP_ENV=test`: correcto.
- `flutter build apk --debug --no-pub --dart-define=APP_ENV=test`: correcto;
  Gradle usa el JDK 17 fijado mediante `org.gradle.java.home`, sin cambiar la
  configuración global de Flutter.
- `scripts/check-quality.ps1`: correcto; 1.301 pruebas y los cuatro arranques de
  `APP_ENV` (development, test, production e invalid-synthetic).

Logs locales ignorados por Git: `.tools/ma-tsk-127-*.log`.

La apertura interactiva de los diálogos y fallos reales de proveedores (permiso
revocado, documento eliminado o fallo durante lectura) quedan sin verificar en
dispositivos. Los dobles del canal y las compilaciones no prueban esas interacciones.
Los bytes de pruebas son sintéticos y no caracterizan ningún formato Openbank.
