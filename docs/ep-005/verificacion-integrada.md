# MA-TSK-049 · Verificación integrada y bloqueo externo

Fecha de revisión: 2026-10-02. Se usa el ticket y la épica completos facilitados
por el usuario. No hay herramienta Epic Board disponible en esta sesión; no
se ha consultado ni cambiado su estado actual. Se revisaron las dependencias
MA-TSK-044/045/048 y los contratos de sesión, carpeta y HTTP. El checkout empezó
limpio en `main`, siguiendo `origin/main`.

## Estado real: bloqueado, sin evidencia extremo a extremo

El inventario `config/google-oauth.public.json` sigue `blocked_external`:
proyecto/clientes reales ausentes, Drive API y tester sin acreditar. El control
`--require-configured` falla como corresponde. No hay gcloud/adb en PATH ni
navegadores o pestañas conectados en el inventario de control UI.

`flutter devices` encuentra Windows y Chrome, sin Android. `flutter doctor -v`
confirma ausencia de Android SDK y Visual Studio C++. Por tanto no se puede
ejecutar aquí el recorrido nativo en Windows ni Android, aunque haya escritorio
Windows. El SDK local conserva Flutter 3.47.0/Dart 3.13.0; doctor avisa de su
canal local `user-branch`. No se cambia SDK ni canal para este ticket.

No se ha autorizado una cuenta Google real con Autofinance, creado o visto una
carpeta real, acreditado reutilización entre dispositivos ni transferido datos.
No existe evidencia para afirmar cumplidos todos los criterios o cerrar la
validación real de la épica. No se usa un conector Drive del asistente para
simular autorización de los clientes OAuth de Autofinance.

## Recorrido nativo preparado

`integration_test/drive_metadata_access_test.dart` es una prueba técnica opt-in,
fuera de las pantallas de producto. Se ejecuta **solo en instalaciones dedicadas
de prueba**: desconecta al empezar y al terminar, borrando la sesión local de
esa instalación. La carpeta remota creada se conserva para el segundo equipo.

Preparar un único proyecto de prueba según [OAuth Google](oauth-google.md),
comprobar el certificado del APK que instala realmente el runner, registrar
cliente Android y Web, cliente Desktop y la misma cuenta tester. Ejecutar:

```powershell
node scripts/check-google-oauth.mjs --require-configured
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter devices
```

El primer comando debe pasar **antes** de OAuth. Registrar las versiones de
Windows/Android/Play Services y hash/firma públicos del APK efectivo. Un
inventario sintético no sustituye el alta ni el certificado real.

1. Primer dispositivo, por ejemplo Windows. Este comando es la petición
   expresa para crear **solo la carpeta**, si no existe:

```powershell
flutter test integration_test/drive_metadata_access_test.dart -d windows --no-pub --dart-define=APP_ENV=test --dart-define=MANUAL_DRIVE_TEST=true --dart-define=DRIVE_FOLDER_ACTION=create --dart-define=GOOGLE_WINDOWS_CLIENT_ID=<ID_DESKTOP_PUBLICO>
```

2. Autorizar con la cuenta tester; verificar el consentimiento limitado a
   drive.file. La prueba consulta primero sin crear, después crea/reutiliza,
   obtiene sin_copia, restaura metadatos y renueva expresamente sin otra UI.
   En Mi unidad abrir Autofinance y comprobar que es una carpeta normal visible
   y que no hay archivo SQLite vacío. Anotar la huella SHA-256 de carpeta que
   imprime el recorrido. La huella es un pseudónimo **privado**, no un secreto
   OAuth; no guardar logs ni esa huella en Git. La prueba no imprime ID real,
   correos, permissionId, tokens ni respuestas OAuth.
3. Segundo dispositivo, Android, misma cuenta y proyecto; pasar esa huella para
   comprobar identidad exacta sin imprimir IDs. Este comando solo consulta:

```powershell
flutter test integration_test/drive_metadata_access_test.dart -d <ANDROID_ID> --no-pub --dart-define=APP_ENV=test --dart-define=MANUAL_DRIVE_TEST=true --dart-define=DRIVE_FOLDER_ACTION=reuse --dart-define=GOOGLE_ANDROID_SERVER_CLIENT_ID=<ID_WEB_PUBLICO> --dart-define=DRIVE_EXPECTED_FOLDER_SHA256=<HUELLA_PRIVADA_DEL_PRIMER_RESULTADO>
```

4. Debe encontrar la misma carpeta, obtener sin_copia y registrar cero POST de
   carpeta. Comprobarla también en Mi unidad desde Android. Repetir Windows en
   modo `reuse` con la huella, y opcionalmente el recorrido en orden inverso.
   La carpeta se reutiliza; no se borra para forzar un caso nuevo.

El cliente de auditoría del ejecutor bloquea antes de enviar cualquier petición
fuera de OAuth, about y GET de metadatos. Solo `create` permite un único POST,
con cuerpo exacto de carpeta normal/marca; `reuse` impide POST de carpeta.
No se permiten upload, alt=media, PATCH/DELETE ni creación de otro archivo.
`binding.reportData` registra plataforma, acción, huella privada, resultado,
número de creaciones y cero transferencias. No ejecuta la aplicación financiera,
no abre SQLite y no escribe bases locales/remotas. Un test omitido por falta de
opt-in/plataforma no es validación.

La API valida MIME, padre real y marca, pero **no demuestra visibilidad de la
interfaz de Mi unidad**: esa evidencia exige la inspección anterior. Conservar
capturas privadas y publicar únicamente evidencia saneada sin correo, otras
carpetas, IDs reales ni detalles de cuenta. Usar alias `carpeta F1` para afirmar
la comparación de identidad en el informe público.

## Fallos reales y evidencia necesaria para cierre

Los fallos se cubren automáticamente con falsos. Para acreditar comportamiento
nativo usar además los escenarios de [Android](autorizacion-android.md) y
[Windows](oauth-windows.md): denegar consentimiento, cancelar selector/navegador,
revocar el acceso de Autofinance desde Google y renovar, desconectar sin red y
cerrar/reabrir/reinstalar la instalación dedicada. La revocación desde Google
afecta ambas instalaciones y debe realizarse al terminar el caso positivo.

Duplicados y paginación se verifican con HTTP sintético. No crear manualmente
carpetas homónimas en Mi unidad como supuesto duplicado marcado: no llevan la
marca privada de Autofinance. No añadir comandos de escritura remota para
forzar duplicados ni ampliar scopes para facilitar la comprobación.

| Evidencia requerida | Estado en esta sesión |
|---|---|
| Proyecto común, clientes efectivos y tester | Bloqueado; inventario sin configurar |
| Autorización real Windows y Android | No ejecutada |
| Carpeta visible en Mi unidad de ambos equipos y misma identidad F1 | No observada |
| Sin_copia real, sin archivo vacío ni transferencia | Ejecutor preparado; no ejecutado |
| Keystore/Credential Manager, reinicio y renovación nativos | No ejecutados |
| Adaptadores, auth/red/duplicados con falsos | Automatizados; resultados locales abajo |

Al desbloquear, añadir fecha, commit probado, versiones/dispositivos, hash/firma
públicos de artefactos, resultado por paso, comparación F1 y capturas saneadas.
Si falla un paso, registrar su código cerrado y conservar estado bloqueado,
sin convertir resultados de pruebas falsas en evidencia remota.

## Comprobaciones locales

- `flutter --version`, `scripts/check-toolchain.ps1` y
  `flutter pub get --enforce-lockfile`: correctos, sin cambios de SDK,
  dependencias ni lockfile. La resolución inicial dentro del sandbox falló al
  consultar pub.dev; se completó mediante la revisión de permisos de ejecución.
- `scripts/check-quality.ps1` completo: **78 archivos Dart** con formato
  correcto, análisis sin incidencias y **448 pruebas Flutter aprobadas**,
  incluidas **30 nuevas** del recorrido integrado. Pasan también las cuatro
  variantes adicionales de arranque `APP_ENV`.
- Persiste la advertencia previa de Drift sobre instancias múltiples de
  `LocalDatabase` en la prueba SQLite integrada. No produce fallos y no se
  modifican fuentes ni contratos de ese módulo.
- `node --test scripts/tests/google-oauth-config.test.mjs`: **14 pruebas
  aprobadas**. El control normal valida el contrato y avisa del bloqueo; el
  control `--require-configured` devuelve **1**, rechazo esperado. No acredita
  proyecto/consentimiento reales.
- `flutter build windows --release --no-pub --dart-define=APP_ENV=test`:
  salida **1**, falta Visual Studio C++. No se compiló un ejecutable.
- `flutter build apk --debug --no-pub --dart-define=APP_ENV=test`: salida **1**,
  falta Android SDK. No se compiló un APK ni se acreditó su firma.
- El nuevo ejecutor manual se incluye en formato y análisis, pero **no se
  ejecutó en dispositivos**. No se afirma OAuth, cifrado nativo ni acceso
  remoto real por esa comprobación estática.
- Revisión de archivos propios y `git diff --check`: correctos. Solo se
  añaden composición/puente de credenciales, pruebas sintéticas/ejecutor
  técnico y documentación. Sin pantallas, cambios de SQLite ni material privado.

La implementación y la cobertura local están entregadas; la evidencia real
requerida sigue bloqueada. La publicación del commit se comunica tras comprobar
el push, sin equipararla a validación extremo a extremo.
