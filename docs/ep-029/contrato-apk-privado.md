# MA-TSK-237 · Contrato del APK privado · v1

Contrato de EP-029 / MA-EPIC-236, contrastado en Epic Board el 2026-10-18.
Fuente operativa: [distribution-contract.json](../../packaging/android/distribution-contract.json).
La [verificación](verificacion-contrato.md) distingue observaciones de requisitos
pendientes. T01 fija el contrato; no entrega la firma T02, el alta Google T03,
el generador T05, las reglas nativas T06 ni la aceptación final T09.

## Identidad, plataforma y versión

| Campo | Contrato |
| --- | --- |
| Producto / paquete invariable | Autofinance / `com.carlosmg91.myautofinance` |
| Distribución | Un APK universal release, `APP_ENV=production`; entrega local privada |
| Versiones | `versionName` = parte anterior a `+` de `pubspec.yaml`; `versionCode` = entero posterior |
| Base actual | `0.1.0+1` → nombre `0.1.0`, código `1`; no es una primera entrega production acreditada |
| Toolchain | Flutter 3.47.0 / Dart 3.13.0 / JDK 17, sin actualización incidental |
| Android | Mínimo API 24 (7.0); compile/target API 36; Build-Tools 36.0.0; NDK 28.2.13676358 |
| ABI | ARM64 `arm64-v8a` y `x86_64` obligatorias; ARMv7 `armeabi-v7a` incluida en el APK debug observado |
| Dependencia de Google | Google Play Services para la autorización nativa actual; finanzas locales utilizables offline |

Gradle ya delega SDK/NDK a Flutter y versiones a `pubspec`; se conserva esa
delegación. Contrastar los valores efectivos en **cada APK** mediante aapt2,
no solo leer Gradle. El NDK no se acredita leyendo el manifiesto APK: registrar
su `source.properties`, configuración efectiva y log de compilación. No subir
minSdk ni cambiar dependencias para ocultar una incompatibilidad. Cualquier
cambio de este contrato requiere revisión explícita y pruebas correspondientes.

Versión con formato `major.minor.patch+build`, componentes numéricos y build
positivo ≤ 2100000000. No usar flags para sustituir la versión de pubspec.
Cada actualización entregada tiene un código **mayor que todos los ya
distribuidos**, aunque cambie major/minor/patch; no reiniciar el contador.
Ejemplo: después de `0.1.0+9`, `0.2.0+10` es admisible, `0.2.0+1` no.
No usar versión SQLite, revisión financiera, fecha ni commit como versionCode.
La comparación Android es por entero, independiente del contrato Windows.

## Instalación y compatibilidad

La persona abre el APK desde una fuente elegida y usa el instalador oficial
del sistema. T08 documentará los requisitos vigentes de país/dispositivo con
fuente y fecha. No prometer instalación universal sin restricciones del sistema,
ni desactivar protecciones. La app no instala paquetes, no requiere
`REQUEST_INSTALL_PACKAGES`, root, ADB para el usuario ni acceso amplio a archivos.
No se incluye Play, AAB, Store, hosting ni autoactualizador.

Antes de proponer actualizar, contrastar paquete, certificado SHA-256 verificado,
versionCode de origen/destino, API y ABI del dispositivo. El nuevo APK debe
tener el mismo paquete y **el mismo certificado estable** y código creciente.
Un nombre de alias o keystore coincidente no acredita el certificado. Conservar
también SHA-1 para el cliente Android Google y SHA-256 **del archivo APK** como
campos distintos. T02 custodia y respalda la firma fuera del repositorio, prueba
su recuperación y prohíbe fallback debug. No se regenera una clave por build.

| Resultado del contraste | Acción |
| --- | --- |
| Mismo paquete/certificado, código mayor, SDK/ABI compatibles | Candidato a actualización manual; exigir preservación T07/T09 |
| Código igual o inferior | Rechazar como actualización; no forzar downgrade |
| Certificado distinto, paquete distinto o identidad no verificable | Detener; conservar instalación y datos; diagnosticar |
| Android inferior a API 24 o sin ABI compatible | Detener; informar incompatibilidad, sin desinstalar |
| Firma inválida, APK parcial o metadatos incoherentes | Rechazar artefacto antes de usarlo |

No usar `uninstall`, `clear-data`, flags de downgrade, cambio silencioso de
paquete ni una rotación de firma como solución automática. El inspector de este
ticket no instala nada. Comparar dos archivos APK solo acredita su relación;
T07/T09 deben acreditar que el origen es el instalado realmente.

## Transición desde debug con datos

Antes de cualquier sustitución incompatible, T07/T08 deben registrar la versión
y certificado del **APK instalado** y si contiene datos. Si no se pueden
comprobar, tratarlo como instalación con datos y detener la sustitución.
Registrar privadamente dispositivo/origen y públicamente solo evidencia saneada.

Una copia en el soporte privado Android no sirve por sí sola para sobrevivir
al borrado de la app. Exigir una copia externa independiente, accesible después,
validada por los servicios EP-004/006/007 y una recuperación probada en una
instalación de prueba nueva con la firma destino. Contrastar datos, esquema,
conteos y resultados tras recuperar, antes de actuar sobre el origen.
La vía Drive solo es viable si el origen y el destino tienen autorización real
y copia verificada; EP-027 puede aportar otra vía solo si está entregada y
probada. No crear una dependencia artificial con exportación o Windows.

No se acredita aquí una migración debug→distribución. Si faltan copia externa,
acceso Google, firma de origen necesaria o recuperación demostrada, registrar
**bloqueo de transición** y conservar la instalación intacta. No extraer datos
mediante root/run-as de release ni asumir recuperable una clave perdida.
Una firma debug tampoco se adopta como firma estable para eludir el problema.

## Preservación y política de backup Android

| Elemento | Actualización compatible N→N+1 | Desinstalar / borrar datos |
| --- | --- | --- |
| Base SQLite, WAL/SHM y diarios propios | Conservar; apertura/migración/recuperación EP-004/006 | Se pierde soporte privado; copia externa previa obligatoria |
| Copias locales, catálogo y restauraciones pendientes | Conservar rutas y semántica existentes | También se pierden; no equivalen a copia externa |
| `drive-sync/state.json` | Conservar identidad/vínculo/versiones/operación pendiente; no declarar limpio por actualizar | Se pierde; nueva instalación debe contrastar explícitamente |
| Registro `noBackupFilesDir/drive-session-v1` y alias Keystore `autofinance.drive.session.v1` | Conservar y demostrar descifrado con la misma clave/alias sin recrearlos | Se pierde sesión/clave privada de la app; reconectar expresamente |
| Copia manual remota ya confirmada | No se modifica por instalar | No se borra de Drive por desinstalar; recuperación posterior exige acceso y validación |

Soporte = `getApplicationSupportDirectory()`, con `sqlite/autofinance.sqlite`,
copias/diarios bajo `sqlite/` y estado Drive separado. No cambiar rutas, esquema,
alias ni borrar/regenerar silenciosamente una sesión ilegible. El registro de
sesión son metadatos cifrados; no incluye access tokens persistidos por la app.
La renovación, caducidad/revocación y reconexión conservan el comportamiento
EP-005/007; actualizar no promete una autorización Google eterna.

**Política fijada para T06 / MA-TSK-242:** excluir datos financieros, copias,
catálogos, diarios, estado de instalación/sync y secretos de backup cloud y
transferencia automática entre dispositivos. Usar `allowBackup=false`, reglas
previas a API 31 (`fullBackupContent`) y `dataExtractionRules` API 31+ con
exclusiones para cloud y device-transfer en los dominios aplicables, incluidos
los dominios de almacenamiento protegido por dispositivo si se usan. Auditar
manifiesto fusionado y reglas empaquetadas; `allowBackup=false` solo no basta.
`noBackupFilesDir` y Keystore mantienen la exclusión del registro/clave; nunca
añadirlos a SQLite, copias manuales o exportación. Restaurar finanzas no restaura
la sesión secreta de otro dispositivo. No añadir otro motor de recuperación.

Android documenta diferencias OEM en device-transfer: las reglas son la política
solicitada y comprobable en los entornos ensayados, **no una garantía de control
sobre todo fabricante**. Un arranque tras traslado no debe adoptar secretos ni
resetear errores silenciosamente. No trasladar la promesa Windows de conservar
soporte tras desinstalar al comportamiento Android.

## Entradas y salidas del futuro generador T05

| Entrada | Validación / propietario |
| --- | --- |
| Contrato v1, commit Git completo y árbol de origen | Identificar código exacto; rechazar o aislar cambios concurrentes ajenos en la entrega final |
| `pubspec.yaml`, `pubspec.lock`, `toolchain.json` | Versión sin overrides, dependencias con `--enforce-lockfile`, SDK/JDK/NDK fijados |
| Firma externa T02 | Ruta/alias y secretos por canal local privado; huella esperada independiente; nunca dart-defines, APK, log o CI público |
| Configuración pública Android T03 | Paquete/certificado real registrados, Drive API/consentimiento/tester y Web `android.serverClientId` del mismo proyecto |
| Configuración de compilación | Universal `release`, `APP_ENV=production`, `GOOGLE_ANDROID_SERVER_CLIENT_ID` público validado; sin `--split-per-abi` |
| Destino privado | Por defecto `dist-private/android/`, ignorado; rechazar destinos que publiquen/comprometan artefactos o claves |
| Evidencias T06/T07/T08/T09 | Reglas/almacenamiento, preservación nativa, guía aprobada y prueba completa; no confundir pruebas técnicas con aceptación final |

La comprobación Android debe ser independiente de Windows OAuth, conservando
el verificador global existente. No basta un ID con formato válido ni un
proveedor simulado. El generador debe rechazar ausencia/configuración Android
inválida para una entrega final y nunca anunciar un APK con Drive deshabilitado
como completo. Puede verificarse su implementación con fixtures `APP_ENV=test`
y claves efímeras aisladas, identificados como tales. T02 puede producir su APK
técnico de firma antes de disponer de Google, sin llamarlo entrega completa.

Salida local: APK único y manifiesto con contrato, commit, hash de configuración
pública, versión, paquete, mínimo/compile/target SDK, ABI reales, certificado
SHA-1/SHA-256, hash/tamaño APK, toolchain, entorno/modo, comandos/resultados,
fecha y evidencias/gates pendientes. No guardar rutas privadas, passwords,
tokens, correo, permissionId, extractos o bases personales en el manifiesto
público. Recompilar y reidentificar si cambia código/configuración después.
No se promete identidad binaria entre máquinas.

T05 comprueba `apksigner`, no debuggable, versión/identidad, APK universal,
recursos/fuentes, SQLite y plugins; alineación ZIP con `zipalign -c -P 16 -v 4`
y ELF de bibliotecas con herramientas NDK según guía oficial. NDK reciente o
build correcto no acreditan por sí solos compatibilidad 16 KB. T07/T09 requieren
ejecución en la matriz 4 KB/16 KB aplicable, API 24/API 36 o entorno actual y
teléfono ARM64 real. No subir dependencias incidentalmente ante un fallo.

## Dependencias y gate de entrega completa

T02/T06 avanzan con este contrato; T03/T05 tras T02; actualización T07 tras
T05/T06. T04 revisa el guion visual de instalación/instrucciones; su aprobación
solo condiciona la guía T08, no el backend ni reemplaza la UI Android EP-026.
T09 exige T03/T07/T08 y **entrega comprobada MA-TSK-131**, seguida del recorrido
Openbank en el APK production exacto instalado. No duplicar lector/adaptador,
fórmulas ni motores para resolver el bloqueo EP-014. Sin dependencia inversa.

Inventario de capacidades y carencias en [verificación](verificacion-contrato.md).
EP-007/019/021/022/023 y patrimonio EP-009/017/026 se reutilizan; EP-020 no es una
implementación independiente. EP-025/027/028 no son gates artificiales. Los
estados done no reemplazan evidencias: ni selector, mockup, goldens, build o
prueba de proveedor falso acreditan Google/Openbank ni teléfono real.

Repo público: no APK/AAB de producción, keystores, claves, secretos o datos
personales en Git, Releases ni artifacts públicos; tampoco cambiar visibilidad
o provisionar hosting. El CI debug/test existente conserva artefactos de prueba,
no se debe reutilizar para publicar producción. `.gitignore` protege APK/AAB,
keystores y `dist-private/`; no es sustituto de revisar lo que se confirma/sube.

## Fuentes y comprobación técnica

- [Versionado Android](https://developer.android.com/studio/publish/versioning): versionCode creciente y compatibilidad mínima.
- [Firma Android](https://developer.android.com/studio/publish/app-signing): identidad de actualización por certificado.
- [Distribución Flutter Android](https://docs.flutter.dev/deployment/android): APK universal y versión desde pubspec.
- [Backup Android](https://developer.android.com/identity/data/autobackup): reglas por API, noBackup y limitación OEM.
- [Páginas de 16 KB](https://developer.android.com/guide/practices/page-sizes): comprobaciones ZIP/ELF y ejecución.

Fuentes oficiales consultadas el 2026-10-18. Para inspeccionar sin instalar:

```powershell
node --test scripts/tests/android-apk-contract.test.mjs
# Variables locales apuntan al SDK/JDK fijados y al APK candidato.
node scripts/check-android-apk-contract.mjs --apk $apk --sdk $sdk --jdk $jdk --expected-certificate $sha256Certificado
# Comprobar también relación con origen y compatibilidad del dispositivo:
node scripts/check-android-apk-contract.mjs --apk $apk --sdk $sdk --jdk $jdk --expected-certificate $sha256Certificado --previous-apk $apkAnterior --device-api 36 --device-abis arm64-v8a,armeabi-v7a
```

`--allow-debug` permite inspección de pruebas explícita. El resultado siempre
declara `purpose=technical-inspection-only` y `completeDelivery=false`; no
acredita APP_ENV, OAuth, custodia, preservación, backup, NDK ni alineación 16 KB.
Esas evidencias pertenecen al generador y a los tickets propietarios. Una firma
inválida, metadato ausente o cambio del hash del APK durante la inspección
aborta, sin leer bases ni modificar el dispositivo.
