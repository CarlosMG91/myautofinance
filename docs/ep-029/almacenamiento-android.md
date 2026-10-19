# MA-TSK-242 · Archivos, permisos y almacenamiento Android

Contrato: [MA-TSK-237](contrato-apk-privado.md), EP-029. Auditoría del
2026-10-19, contrastada con `GET http://localhost:4310/api/data`, tablero
**My autofinance**, MA-TSK-242 `in-progress` y requisito MA-TSK-237 `done`.
No se cambia el estado del tablero. Las comprobaciones de este ticket no
acreditan una entrega production ni la preservación N→N+1 de T07/T09.

## Política solicitada al sistema

El manifiesto principal declara `allowBackup=false`,
`fullBackupContent=@xml/backup_rules` y
`dataExtractionRules=@xml/data_extraction_rules`. Las reglas previas a API 31
y las secciones `cloud-backup` y `device-transfer` de API 31+ excluyen `path="."`
en nueve dominios: `root`, `file`, `database`, `sharedpref`, `external`,
`device_root`, `device_file`, `device_database` y `device_sharedpref`.

La exclusión por dominio cubre también el soporte Flutter bajo `getDir`, la
SQLite activa, WAL/SHM, copias, catálogos y diarios de recuperación, y el estado
separado `drive-sync/state.json`; no depende de que SQLite use el directorio
Android `databases`. No se mueven archivos ni se cambian esquemas, versión,
applicationId, SDK, dependencias, scopes o ajustes globales del dispositivo.

El registro `noBackupFilesDir/drive-session-v1` y el alias Android Keystore
`autofinance.drive.session.v1` conservan exactamente su contrato. La app no
guarda tokens en ese registro ni incluye sesión/clave en copias financieras.
Leer un registro ilegible sigue devolviendo `secureStorageFailure`, sin borrarlo
ni generar otra clave en la lectura. El canal de sesión se desregistra al
desconectar el motor Flutter, igual que el selector.

Actualizar con paquete/certificado compatibles conserva el soporte y Keystore;
la prueba efectiva entre versiones corresponde a T07/T09. Desinstalar o borrar
datos pierde soporte privado y sesión; una instalación nueva debe reconectar,
aunque Google Play Services conserve cuentas del sistema. La restauración
financiera manual no adopta la sesión secreta de otro dispositivo.

La política usa las [reglas Android oficiales](https://developer.android.com/identity/data/autobackup),
consultadas el 2026-10-19. Android documenta diferencias entre fabricantes en
transferencia de dispositivos: `allowBackup=false` por sí solo no constituye
garantía universal. Las reglas expresan la exclusión solicitada; este informe
no promete controlar herramientas OEM ni haber ensayado todas ellas. No se
modifica la configuración global de backups para probarlas.

## Selector compartido CSV/XLS y ciclo de vida

Se conserva `autofinance/local_csv`, `ACTION_OPEN_DOCUMENT`,
`CATEGORY_OPENABLE`, un documento y solo concesión temporal de lectura. La
orientación XLS afecta al título; el formato lo valida el lector propietario.
No se toma permiso persistente ni se obtiene una ruta física desde una URI.
Solo se acepta esquema `content`; la lectura se realiza por `ContentResolver`
en un executor, incluidos documentos servidos sin ruta física local.

Cada petición tiene código distinto, también entre instancias de actividad en
el mismo proceso. Un resultado duplicado durante la lectura no vuelve a leer.
La respuesta se vincula al objeto de petición, se completa una sola vez y se
borra antes de llamar al consumidor. Detach cancela consulta/lectura y devuelve
`unavailable`; callbacks pendientes de la instancia anterior se descartan.
Una pausa/reanudación sin detach conserva la petición. Tras muerte del proceso
no se restaura una selección como importación confirmada: se vuelve al arranque
y a la recuperación existente. El ensayo de recreación real del sistema queda
separado de las pruebas que inyectan resultados en el canal.

| Incidencia | Respuesta del canal / dominio Dart |
| --- | --- |
| Cancelar selector | `null` / `LocalFileCancelled` |
| Concesión denegada | `accessDenied` |
| Documento desaparecido, URI inválida o detach | `unavailable` |
| Lectura incompleta o fallo del proveedor | `readFailed`, nunca bytes parciales |
| Otra selección en curso | `busy` |
| Resultado duplicado/tardío | No completa una selección posterior |

El canal devuelve bytes completos, no crea lotes ni interpreta finanzas. Las
pruebas CSV existentes verifican cancelación, sesiones reemplazadas, revalidación
y rollback sin altas parciales; se reutilizan sin añadir un lector en APK.

No se solicita almacenamiento amplio, `MANAGE_EXTERNAL_STORAGE`, root,
permisos de medios o `REQUEST_INSTALL_PACKAGES`. La actualización se realiza
abriendo el APK externamente con el instalador oficial; no se añade instalador.
Los permisos de biometría/huella ya fusionados por dependencias se inventarían,
sin añadir ni eliminar capacidades ajenas al ticket.

## Verificación reproducible

Con las versiones fijadas, resolver `flutter pub get --enforce-lockfile` y
ejecutar `scripts/check-quality.ps1`. El informe de ejecución distingue sus
resultados y los bloqueos del entorno.

```powershell
node --test scripts/tests/android-storage.test.mjs
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
node scripts/check-android-storage.mjs --apk build/app/outputs/flutter-apk/app-debug.apk --sdk $env:ANDROID_HOME
```

El auditor inspecciona con aapt2 el manifiesto **empaquetado**, permisos y
referencias a los recursos, y los tres conjuntos de exclusiones compilados.
Rechaza recursos ausentes, dominios incompletos, includes, rutas parciales y
permisos fuera del inventario. Registra hash APK y siempre
`completeDelivery=false`. Se reutiliza sobre el APK final en T07/T09; no
acredita firma, OAuth, proveedor remoto, actualización, 16 KB ni ensayo OEM.

El runner nativo no requiere bibliotecas nuevas:

```powershell
# Tras el build debug; JAVA_HOME=JDK17 y SDK fijados.
./android/gradlew.bat -p android :app:assembleDebugAndroidTest --no-daemon --no-configuration-cache
```

Instalar ambos APK de prueba únicamente en un emulador **dedicado sin datos
personales**, con identidad/firma de origen comprobadas. Si hay instalación
incompatible o datos sin procedencia sintética acreditada, detener; no usar
uninstall/clear-data. Después ejecutar:

```powershell
adb -s <emulador-dedicado> shell am instrument -w -r -e syntheticOnly true com.carlosmg91.myautofinance.storageaudit/com.carlosmg91.myautofinance.StorageAuditInstrumentation
```

Exigir salida `MA-TSK-242: ... native checks passed` y código de instrumentación
`-1`; `am instrument` puede salir con código shell cero incluso si falla el test.
El runner verifica recursos/permisos reales, `ContentResolver` con el proveedor
local Downloads (API 29+) y un `DocumentsProvider` sintético de la variante debug,
bytes íntegros CSV/XLS, cancelación/denegación/desaparición/fallo parcial,
duplicados/detach/resultados tardíos y reapertura/corrupción del registro cifrado.
La sesión se escribe solo en un subdirectorio sintético de noBackup; no lee ni
borra la sesión habitual. Solo elimina el documento Downloads que acaba de crear.
El proveedor de fallos **solo existe en debug**, protegido por `MANAGE_DOCUMENTS`
como exige Android a todo `DocumentsProvider`; no solicita ese permiso para la
app ni se incluye en release. Solo sirve bytes sintéticos. Compilar app y runner
con la misma configuración local y comparar sus certificados antes de instalar.

El runner combina resultados inyectados con un recorrido del selector oficial:
abre la raíz documental sintética, selecciona `fixture.csv`, comprueba bytes y
pausa/reanudación, vuelve a abrir y cancela con Back. El host de instrumentación
es una Activity solo debug, no exportada, sin Flutter/SQLite; no sustituye la UI
de producto. La auditoría rechaza su presencia en release.
Completar en T07/T09 el recorrido con el proveedor documental de uso (por ejemplo,
Drive), segundo plano, recreación/muerte del proceso y datos intactos, sobre el
APK production exacto y teléfono ARM64. No se ha ensayado un proveedor remoto
ni una recreación real de Activity en este runner.

## Dependencia Openbank

[MA-TSK-131](../ep-014/verificacion-reapertura-131.md) y
[MA-TSK-124](../ep-014/caracterizacion-openbank.md) continúan declarando falta de
muestra verificable y recorrido productivo, aunque figuren `done` en el tablero.
No hay adjuntos/ruta privada de muestra en la solicitud. No se ha leído ni
supuesto un formato XLS. El selector y los bytes sintéticos del proveedor no
acreditan lector/revisión/confirmación Openbank. Ese criterio dependiente queda
bloqueado por EP-014, sin dependencia inversa ni sustitución por un adaptador
simulado. No se cierran MA-TSK-245 o la épica por este trabajo.

Los resultados concretos y límites de esta ejecución se registran en
[verificación de almacenamiento](verificacion-almacenamiento.md).
