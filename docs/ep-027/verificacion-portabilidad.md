# MA-TSK-226 · Verificación de exportación y lectura independiente

Ejecución del 2026-10-17, exclusivamente con datos sintéticos. Se ha usado el
ticket íntegro y sus requisitos facilitados por el usuario. No se ha actualizado
el estado de Epic Board ni de otras épicas. El resumen verificable se publica en
[evidencia-portabilidad.json](evidencia-portabilidad.json).

## Recorrido nativo real

`integration_test/export_portability_test.dart` monta `AutofinanceApp`, una
`LocalBackupSession` temporal, SQLite, exportadores y selector nativo reales.
Reutiliza `test/support/recovery_reference.dart` (EP-001), la captura EP-004 y
las copias EP-006. No introduce servicios de producto ni otro snapshot.

En Windows se ha usado el runner Flutter debug y `IFileSaveDialog`, guardando
en archivos nuevos del sistema de archivos. En Android se ha usado un emulador
API 37 y `ACTION_CREATE_DOCUMENT` con el proveedor Downloads: se comprueban
las URI y nombres devueltos realmente por el proveedor, no una ruta privada
inferida. Los documentos públicos se transfirieron a Windows mediante ADB pull,
sin root ni lectura del almacenamiento privado. No acredita dispositivo físico
ni proveedor remoto. El SDK de compilación sigue siendo API 36, según toolchain.

Ambos recorridos terminaron con `All tests passed!`: una cancelación y ocho
guardados por plataforma. Las capturas completas de las doce tablas, identidad,
revisión y resultados nativos quedan en `.tools/226-evidence/{platform}.json`.
Son evidencia local ignorada, con rutas de trabajo y datos sintéticos. Cada
exportación compara todas las filas antes/después y verifica SHA-256 de los
archivos del catálogo/copia privada previamente creada: permanecen intactos.
Solo las modificaciones explícitas de las variantes cambian la revisión.

| Etapa / archivo local | Resultado contrastado por lector independiente |
|---|---|
| `all.zip` | 10 reales / 48 presupuestos; +2329.65 / +13200.00 EUR; dos Café con UUID distintos |
| `january.zip` | 6 reales / 4 presupuestos; +1229.75 / +1100.00; fecha de valor de enero, aunque creación/importación son posteriores; contexto íntegro |
| `empty.zip` | Diciembre 2025: cuatro CSV financieros con cabeceras y cero filas; tres catálogos completos, sin fotos fabricadas |
| `base-copy.zip` | Doce tablas completas, diez movimientos y 48 presupuestos; febrero sin foto; enero líquidos 9000 / neto 14000 EUR |
| `partial.zip` | Febrero: dos valores, estado incomplete, dos fichas pendientes; no presenta suma parcial como patrimonio |
| `zero.zip` | Febrero completo, ahorro 0.00 registrado; líquidos 6200 / neto 11900 EUR |
| `history.zip` | Cartera media hasta febrero exclusivo y líquida desde febrero; enero conserva 9000 líquidos y febrero da 16700; neto febrero 11900 |
| `variant-copy.zip` | Conserva todos los datos anteriores y el texto/importe extremo; misma captura íntegra que el informe nativo |

La variante extrema cambia un real de febrero a `92233720368547758.07` EUR,
con concepto `Árbol; "Café"`, salto LF y `segunda línea 🧪`, y Discrecionalidad
con espacios extremos, `;`, comillas, CRLF y `漢字`. El lector contrasta todas
las columnas persistidas, sin recortar ni pasar importes por float. La lectura
del caso base confirma el signo interno del presupuesto; no lo invierte como
el CSV de entrada histórico. No se mezclan las cifras de la variante con EP-001.

## Lectura independiente y guía T07

`scripts/verify-export-portability.py` usa únicamente Python estándar:
`zipfile`, `csv`, `hashlib`, `sqlite3`, `Decimal` y enteros de precisión arbitraria.
Valida CRC, inventario sin duplicados/rutas, versión, tamaños, SHA-256,
diccionario byte a byte, cabeceras/conteos, filtro, UUID/referencias y cada valor
directo frente a la captura nativa. Abre SQLite con `mode=ro` en carpetas nuevas
de Windows con espacios y tildes, externas a la app. Contrasta integridad,
claves, application_id, user_version, identidad, revisión y todas las filas de
las doce tablas. Comprueba hashes después de cerrar y ausencia de sidecars.

Ejecuta las **13 sentencias SQL** publicadas en los bloques SQL de T07 sobre
las cuatro SQLite. Las dos copias base ejecutan todas sin error. En cada copia
extrema una agregación de la guía produce `integer overflow`: T07 advierte este
límite de sum(INTEGER), incluso si un total final pudiera caber después de un
desbordamiento intermedio. Se registra explícitamente; el total exacto se
obtiene sumando los enteros leídos con Python. No se convierte a REAL ni se
presenta esa sentencia como una consulta pasada con éxito.

Además, `scripts/check-export-recovery-guide.ps1` ejecuta el bloque PowerShell
publicado de T07, cambiando únicamente las dos rutas de ejemplo. Verifica y
extrae las copias base Windows y Android en carpetas nuevas; usa **SQLite CLI
3.54.1 x64** con `-readonly`, contrasta metadatos/conteos y ejecuta literalmente
los bloques SQL de la guía. Python usa SQLite **3.53.1**: son dos lectores
estándar separados de Flutter y del SQLite embebido de la aplicación.
El CLI portátil procede de la [descarga oficial de SQLite](https://sqlite.org/download.html),
con SHA3-256 del ZIP contrastado con el publicado; versión y hash en la evidencia.
Los binarios de herramientas no se versionan.

Las herramientas solo reciben los ZIP públicos, la guía y los informes
sintéticos del driver. La recuperación no consulta una conexión de Autofinance,
no usa SDK Flutter, credenciales o Drive y no instala la SQLite en la aplicación.
Los ZIP originales se conservan. No se reconstruye ni importa ningún CSV.

## Fallos y alcance de la evidencia

| Caso | Evidencia / nivel |
|---|---|
| Cambio concurrente de datos | Pruebas existentes `data_export_test` y `portable_backup_export_test`: SQLite real, escritura después de captura y WAL sin confirmar; no mezclan revisión/filas |
| Cancelación | Selector real en Windows y Android; pruebas de preparación y controlador para cancelación/Back durante trabajo |
| Destino existente | Negativo T07 ejecutado: rechaza antes de extraer, conserva centinela y original. El guardado nativo conserva además la evidencia T04 de conflicto Windows y nombre nuevo Android |
| Acceso / espacio / fallo parcial | Pruebas existentes del puerto/controlador con errores tipados y aviso de posible incompleto; límites/errores de staging reales o inyectados en exportadores; pruebas de copias verifican conservación. No se acredita disco físico lleno ni revocación real de permisos del destino en T08 |
| ZIP dañado | ZIP truncado real: lector independiente y bloque T07 fallan; no informan éxito |
| Manifiesto incorrecto | ZIP con CRC válido y SHA-256 declarado falso: ambos fallan; T07 rechaza también revisión distinta de SQLite y versión no admitida |
| Originales y anteriores | Hash de ZIP original, base extraída en solo lectura, centinela de destino existente, filas activas y copia/catálogo privado conservados |

Se reutilizan [T04](guardado-nativo.md) y sus pruebas, sin duplicar el puerto.
Las pruebas con dobles no se presentan como fallos de hardware reproducidos
en dispositivos. La interrupción física de almacenamiento, un proveedor remoto,
un teléfono físico y una revisión humana con lector de pantalla siguen sin
acreditarse. Estas limitaciones impiden afirmar cobertura nativa de todos los
fallos posibles; no se infiere aceptación visual final ni cierre automático de
la épica.

El primer intento Windows de T08 terminó con errores `accessibility_bridge`
y desaparición del servicio del runner al sondear accesibilidad. La repetición
sin ese sondeo pasó completa; no se cuenta el intento fallido como pasado.
El primer intento Android detectó que el fixture usaba la ruta simbólica de
soporte: se corrigió solo el test mediante `resolveSymbolicLinks`, como T06,
y se repitió completo con éxito. No se modificó persistencia de producto.

## Reproducción

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
./scripts/check-quality.ps1
flutter drive --debug --no-pub -d windows --target=integration_test/export_portability_test.dart --driver=test_driver/export_portability.dart --dart-define=APP_ENV=test --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false
# Repetir con -d <dispositivo-android-autorizado>.
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

El recorrido es interactivo: cancelar el primer selector; guardar los siguientes
con el nombre de etapa de la tabla. El driver conserva los nombres/ubicaciones
reales. Copiar los ocho documentos públicos Android a `.tools/226-public/android`
y los Windows a `.tools/226-public/windows`, nombrándolos por etapa; nunca
obtenerlos desde el almacenamiento privado de una instalación real.

```powershell
python scripts/verify-export-portability.py --root .tools/226-public --evidence .tools/226-evidence --output .tools/226-evidence/independent.json --sqlite-cli <ruta-sqlite3.exe>
./scripts/check-export-recovery-guide.ps1 -Zip .tools/226-public/windows/base-copy.zip -Destination '<carpeta-nueva-inexistente>' -Sqlite '<ruta-sqlite3.exe>'
# Repetir el último comando con base-copy.zip de Android y otra carpeta nueva.
```

El verificador rechaza también original/manifiesto dañados, revisión/versión
incoherentes y destino existente mediante ejecuciones negativas del script T07.
No hay dependencias Python externas. La salida detallada y ZIP/SQLite sintéticos
quedan ignorados en `.tools/226-*` y directorios temporales exclusivos.

Los builds de producto Windows release y Android debug, con `APP_ENV=test`,
son correctos. Se usaron Flutter 3.47.0 / Dart 3.13.0, JDK 17 y los paquetes
Android fijados, sin actualizar lockfile. La configuración y los builds Windows
y de pruebas se aislaron bajo `.tools/226-*` mediante APPDATA; el APK está en
la salida habitual `build/app/outputs/flutter-apk`. El checkout conserva cambios
concurrentes anteriores a este ticket; se excluyen de su commit. Dentro del sandbox fallaron
pub.dev y ADB; las repeticiones autorizadas fuera de él permitieron ejecutarlos.
El estado final de análisis, pruebas pertinentes y batería general se registra
en el JSON de evidencia; no se atribuyen a exportación fallos de otras épicas.

Resultado de pruebas: **59 casos de exportación, guardado, controlador/UI,
navegación y arquitectura correctos**. La selección ampliada dio 66 correctos
y un fallo de recuperación con rechazo/bloqueo de archivo; la repetición
aislada del archivo completo dio **8/8 correctos**, incluidos rollback por fallo
de disco y tres interrupciones reales de procesos. No se modificaron esas
pruebas ni su implementación.

La batería general terminó con **2008 correctos y cinco fallidos**. Dos eran
los casos de recuperación que pasaron al aislarlos; permanecen los tres fallos
ya registrados en T04/T06: `report_drilldown_journey` Windows y
`pending_lifecycle` Windows/Android. No se ha repetido la batería completa tras
aislar recuperación y **no se presenta como verde**. El análisis completo y el
análisis final de los archivos Dart del ticket no tienen incidencias; formato
y sintaxis de los verificadores son correctos. Los cuatro arranques
development/test/production/invalid-synthetic pasaron por separado porque el
script general se detiene cuando fallan las pruebas. La lectura independiente
y T07 se repitieron al terminar estos controles, sin procesos de Flutter,
flutter_tester ni Autofinance en ejecución en Windows; Autofinance también
estaba detenida en Android.
