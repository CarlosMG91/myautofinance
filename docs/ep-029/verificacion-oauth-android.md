# MA-TSK-239 · Verificación y bloqueo externo

Fecha de revisión: 2026-10-18. Consultados por API local Epic Board,
**My autofinance / MA-EPIC-236 / MA-TSK-239**, y dependencia MA-TSK-238 `done`.
El ticket exige Google real: documentar el bloqueo no permite completarlo.
Base Git: `c1b7e4c4cd46a68ad0d7444bba4de38ef2001216`, rama configurada
`ticket/ma-tsk-193`. Se conserva el trabajo concurrente preexistente.

## Resultado comprobado

- Identidad package + SHA-1/SHA-256 registrada en el
  [inventario público](../../packaging/android/oauth-distribution.public.json).
  Coincide con el PEM de T02 y con el APK técnico realmente disponible.
  Se vuelve a ejecutar `apksigner verify --verbose --print-certs` y
  `aapt2 dump badging` mediante el inspector existente. Hash de archivo T02
  y ambas huellas coinciden; no se usa la clave privada para inspeccionar.
- Control Android independiente, sin modificar el comprobador global ni el
  inventario Google pendiente. El caso sintético Android completo/Windows
  ausente pasa Android y mantiene el rechazo global, sin mutar `status`.
- **34 pruebas Node correctas**, sin omitidas al proporcionar el APK técnico
  local: contrato APK (9), contrato OAuth global (14), control Android (11).
  Incluyen certificado incorrecto, evidencia debug/CI inválida, permisos extra,
  proyecto distinto, configuración incompleta y ausencia de filtración del valor
  sintético sensible. Las fixtures OAuth son ficticias y solo viven en tests.
- `check-google-oauth.mjs`: esquema válido, aviso explícito de bloqueo.
  `--require-configured`: salida 1 esperada. Control Android: salida 1 esperada,
  falta acreditar proyecto Google común. No se sustituye ningún ID `null`.

Reproducción de pruebas con el APK técnico existente (variables de proceso,
solo rutas locales; `$sdk` y `$jdk` apuntan a Build-Tools 36.0.0 y JDK 17):

```powershell
$env:AUTOFINANCE_T02_APK = (Resolve-Path dist-private/android/signing-check/autofinance-technical-signature-check.apk).Path
$env:AUTOFINANCE_ANDROID_SDK = $sdk
$env:AUTOFINANCE_JDK17 = $jdk
node --test scripts/tests/google-oauth-config.test.mjs scripts/tests/google-oauth-android.test.mjs scripts/tests/android-apk-contract.test.mjs
```

Sin `AUTOFINANCE_T02_APK`, se omite únicamente la inspección real del APK;
esa ejecución acredita solo las otras 33 comprobaciones.

## Bloqueo externo preciso

El inventario CUA actual devuelve `apps=[]`, `browsers=[]`; el intento de abrir
Google Cloud devuelve `Browser is not available: iab`. `gcloud` no está
disponible en PATH. No hay acceso autenticado a Google Cloud para identificar
el proyecto, habilitar Drive API, verificar consentimiento/tester o crear y
contrastar clientes Android/Web. El conector Drive no administra OAuth de esta
app y no serviría como evidencia de autorización de Autofinance.

`config/google-oauth.public.json` continúa `blocked_external`: ID y número de
proyecto nulos, API/tester falsos, `serverClientId` nulo y clientes vacíos.
La [guía concreta](oauth-android.md) identifica qué debe completar el propietario
y cómo registrar únicamente los datos públicos reales. Se ha solicitado esa
información; no se inventan credenciales ni se aceptan condiciones por él.

ADB solo enumera `emulator-5554`: API 37, ABI `x86_64,arm64-v8a`, Google Play
Services presente y paquete Autofinance ausente. No aparece un teléfono físico.
La primera consulta ADB falla por permisos del sandbox; el reintento autorizado
de solo lectura permite comprobar esos datos. No se instala ni cambia nada.

**No ejecutado:** alta Cloud, selector/consentimiento con cuenta tester real,
scope efectivo de un token real, identidad permissionId/carpeta, renovación
Google, conservación en APK production, actualización o teléfono ARM64.
Las pruebas de proveedor simulado no acreditan ninguno de estos puntos.
No se entrega un APK con Drive por completado; T05/T09 mantienen sus gates.

## Calidad y entrega de código

`flutter --version` y `check-toolchain.ps1` confirman Flutter 3.47.0 y Dart
3.13.0. El primer `check-quality.ps1` se detiene durante la consulta de avisos
de pub.dev por restricción de red (SocketException 10057). El reintento con
red autorizada resuelve `pub get --enforce-lockfile`, sin cambiar el lockfile.

El control completo verifica **505 archivos** con formato correcto y análisis
sin incidencias. Suite Flutter: **2.011 aprobadas y dos fallidas**, en 11 min
29 s. Los dos fallos son `pending_lifecycle_test.dart`, Windows tabla y Android
tarjetas: `Bad state: No element` al localizar el menú desde
`pending_lifecycle_journey.dart:82/144`. Coinciden con los fallos ya registrados
en T01/T02; no se modifican esas pruebas ni su funcionalidad EP-015. No se
declara calidad global correcta. Los tests existentes de los adaptadores
Android/Drive no presentan fallos; siguen usando proveedores simulados.

El script se detiene antes de las variantes de arranque por esos fallos. Se
ejecutan aparte `development`, `test`, `production` e `invalid-synthetic`:
**cuatro pruebas aprobadas**, una por variante. Logs locales ignorados en
`.tools/ma-tsk-239-*`. Parseo Node de ambos archivos nuevos y
`git diff --cached --check` correctos. `toolchain.json`, `pubspec.lock` y
`config/google-oauth.public.json` permanecen sin cambios.

No cambian Dart, adaptadores, Gradle, SDK, lockfile, permisos ni UI; no se
requiere recompilar las plataformas por estos controles Node/documentación.
Solo se inspecciona el APK técnico T02 existente, sin fabricar otro artefacto.
Los cambios previos/concurrentes de sincronización y otros tickets se excluyen
del commit. No se versionan APK, datos personales, sesiones ni material privado.
