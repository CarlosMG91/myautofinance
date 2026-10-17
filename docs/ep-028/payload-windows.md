# MA-TSK-229 · Payload Windows x64 privado

Implementación T02 de [EP-028](contrato-instalacion.md). Prepara un **candidato
de payload**, no el instalador T05, el manifiesto final `manifestVersion=1` de
T06 ni la aceptación de arranque limpio T08. No implementa el asistente pendiente
de aprobación visual T04. Estado real del ensayo: [verificación](verificacion-payload.md).

## Entradas fijadas y adquisición

- `toolchain.json` y `pubspec.lock` existentes, sin actualizarlos: Flutter
  3.47.0 / Dart 3.13.0. `pubspec.yaml` es la única versión de app/paquete:
  `major.minor.patch+build` ↔ recurso PE `major.minor.patch.build`.
- [payload-toolchain.json](../../packaging/windows/payload-toolchain.json):
  Visual Studio **2022**, MSVC v143 **14.44.35207**, Windows SDK
  **10.0.26100.0**, CRT x64 **14.44.35211.0**. Instalar estos componentes
  específicos mediante Visual Studio Installer, desde los canales oficiales
  de Microsoft; no cambiar Flutter ni sustituirlos por VS Insiders. Una
  actualización de seguridad requiere cambiar el pin explícitamente y repetir
  validación; no se promete que este pin siga siendo la última revisión.
- Runtime: todos los nueve DLL del directorio redistribuible oficial
  `VC\Redist\MSVC\<versión>\x64\Microsoft.VC143.CRT` de esa instalación de
  VS2022. El número del directorio contenedor puede diferir del VERSIONINFO:
  se valida **cada archivo** contra `14.44.35211.0`, firma Microsoft válida y
  lista cerrada. No usar `debug_nonredist`, System32, un repack ni extraer
  archivos de otra aplicación. No ejecutar `vc_redist` en el destino.
- Proporcionar la licencia real de esa edición de Visual Studio desde su
  instalación oficial. Se exige copia válida/licenciada del toolset y respetar
  los términos de redistribución; el aviso del proyecto no los sustituye.
  Se conservan los binarios sin modificarlos. UCRT es componente de Windows
  10/11; los demás imports deben ser del payload o de la lista explícita de
  componentes de Windows en el verificador. Un import desconocido bloquea.
- Inno Setup **6.5.4**, instalador oficial
  [innosetup-6.5.4.exe](https://github.com/jrsoftware/issrc/releases/download/is-6_5_4/innosetup-6.5.4.exe),
  SHA256 `fa73bf47a4da250d185d07561c2bfda387e5e20db77e4570004cf6a133cc10b1`.
  Referencia independiente: [manifiesto Microsoft WinGet de esa versión](https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/j/JRSoftware/InnoSetup/6.5.4/JRSoftware.InnoSetup.installer.yaml).
  Descargar manualmente a una ruta privada; el script comprueba el hash **antes
  de ejecutarlo**, instala solo la herramienta por usuario en `.tools/inno-6.5.4`
  y conserva procedencia/hashes del compilador y sus dependencias. No usar un
  instalador `latest` ni confiar en el nombre de archivo.

La [lista de redistribución de Microsoft](https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution),
la [guía de redistribución app-local](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files)
y la [tabla oficial del runtime 14.44.35211](https://learn.microsoft.com/en-us/lifecycle/faq/visual-c-faq)
son las referencias de procedencia. La distribución app-local delega en
Autofinance la entrega manual de las futuras correcciones del runtime.

## Preparación local

Usar un checkout limpio del commit deseado, con la rama configurada. El script
rechaza cambios tracked/untracked e identifica el commit completo; no guarda,
confirma ni elimina trabajo de otros tickets. No reutiliza builds anteriores.
Lee `flutter config --machine` y exige `build-dir=build` (o su valor por defecto).
El template Windows fijado codifica `PROJECT_BUILD_DIR` y `AOT_LIBRARY` bajo
`build/`: otro valor podría copiar assets antiguos incluso si el comando de
compilación termina correctamente. Si existe **cualquier** `build/`, incluso
de pruebas, usar otro checkout limpio. No elimina directorios ni cambia la
configuración global Flutter automáticamente. Preparar el entorno de entrega
con ese valor antes de usar el script; no ejecutar calidad y empaquetado a la
vez ni sobre árboles de build reutilizados.

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
./scripts/prepare-inno-setup.ps1 -InstallerPath '<descarga-local>/innosetup-6.5.4.exe'
./scripts/prepare-windows-payload.ps1 `
  -RuntimeCrtDirectory '<VS2022>/VC/Redist/MSVC/<version>/x64/Microsoft.VC143.CRT' `
  -VisualStudioLicensePath '<VS2022>/<licencia-real-de-la-edicion>' `
  -InnoDirectory '.tools/inno-6.5.4'
```

Los marcadores `<...>` deben sustituirse por entradas reales; no son rutas
distribuidas. La preparación puede necesitar red para dependencias/tooling.
El paquete resultante no descarga ni instala dependencias en el destino.

El build real es `flutter build windows --release --no-pub
--dart-define=APP_ENV=production`, con **solo** el identificador público
`GOOGLE_WINDOWS_CLIENT_ID` del JSON OAuth existente. No admite defines libres,
secretos ni cambios de versión externos. La variable temporal de proceso
`AUTOFINANCE_PRODUCTION_PAYLOAD=1` hace que CMake seleccione MSVC/SDK fijados y
rechace otro generador; después se inspeccionan cache/compilador efectivos.
No se modifica `toolchain.json`, `pubspec.lock`, CompanyName, ProductName,
InternalName ni el nombre `myautofinance.exe`. El verificador T01 contrasta los
recursos PE y la ruta derivada de RoamingAppData **sin ejecutar la app**.

OAuth se valida con `node scripts/check-google-oauth.mjs --require-configured`,
tipo desktop y scope existente `drive.file`. A fecha de la implementación el
JSON declara `blocked_external` y `windows.clientId=null`: **no existe una
configuración de producción válida que se pueda reutilizar aún**. No se crea
cliente, se amplían scopes ni se acepta un ID de ejemplo. No se presenta como
lista una entrega de producción con Drive sin configurar.

## Inventario y licencias

Se parte de **todos** los archivos de `runner/Release` producidos por la
instalación CMake de Flutter. Se contrasta el árbol entero con
`install_manifest.txt`, incluyendo el runner generado in situ, sin glob de
«solo EXE». Se conservan Flutter DLL, todos plugins/native assets reales,
`sqlite3.dll` (aunque se cargue por FFI), `dartjni.dll` cuando se genera, `data`,
`app.so`, ICU, shaders, manifiestos y las tres fuentes Roboto. Un archivo sobrante
o ausente bloquea; el mínimo obligatorio no sustituye al inventario completo.

Excepción explícita de CMake **solo para payload privado**: excluye
`native_assets.json` de la carpeta de native assets. Es el descriptor del
ejecutor de `flutter test`, con rutas absolutas del host, no un archivo del
runtime de escritorio. Evidencia en el SDK fijado:
`packages/flutter_tools/lib/src/isolated/native_assets/test/native_assets.dart`
(comentario «Only flutter test uses ... native_assets.json») y
`isolated/native_assets/native_assets.dart` (`_targetLocationSingleArchitecture`).
El AOT mantiene el mapeo de DLL del runtime; si existe
`data/flutter_assets/NativeAssetsManifest.json` se conserva y comprueba. Flutter
usa `["absolute", "sqlite3.dll"]` para nombres locales en desktop: se acepta
ese nombre, nunca una ruta `C:\...`, UNC ni `..`. No se reescriben binarios ni
manifiestos del runtime.

El inventario aplica SHA256/tamaño/ruta relativa a cada archivo. Verifica
PE32+/AMD64, AOT ELF64 x86-64 y cierre de imports normales y delay-load de todos EXE/DLL, sin
resolver dependencias desde el PC de desarrollo. Comprueba además los assets
FFI declarados. No demuestra todas las cargas dinámicas: el arranque sin SDK
ni runtime global en Windows limpio sigue siendo necesario.

Se añaden los DLL CRT app-local y `licenses/`: términos reales de Visual Studio,
aviso del runtime, licencia Flutter, licencia completa del engine/terceros desde
`bin/cache/pkg/sky_engine/LICENSE`, licencia Roboto y licencia Inno. Se conserva
`data/flutter_assets/NOTICES.Z`, registro de licencias generado por Flutter para
paquetes. El manifiesto enumera estas licencias con sus hashes; no reemplaza los
textos por enlaces. Rechaza datos SQLite/sidecars, bases, snapshots, fixtures,
logs, SDK/caches, tokens, certificados privados, auxiliares Debug, enlaces y
rutas con colisiones Windows. Antes de distribuir deben comprobarse todos los
avisos contra los componentes efectivos, incluidos nuevos plugins futuros.

## Salida para T05/T06

Solo `dist-private/windows/payload-<version>-<commit12>/`, ignorado por Git:

- `payload/`: árbol instalable completo con CRT y licencias.
- `inventory.json`: rutas/tamaños/SHA256 e imports PE.
- `payload-manifest.json`: **`payloadManifestVersion=1`**, versión/identidad,
  entorno production, commit limpio, UTC, versiones efectivas y hashes de
  entradas/toolchain/lockfile/OAuth público, origen/hashes CRT, licencias,
  firma observada por binario y límites de validación.

No es el `manifest.json` final de T06: faltan instalador, su SHA256 y las pruebas
E2E. Se marca `verification.status=candidate`, `cleanWindowsLaunch=pending` e
`installer=notBuilt`. T06 debe verificar nuevamente el inventario cerrado,
incorporar EXE del instalador y evidencias reales antes de declarar entrega
verificada. No hay publicación, workflow nuevo, release, artefacto público ni
hosting. Los hashes acreditan integridad, **no autoría ni confianza Windows**;
se registra el estado de firma real, sin fabricar certificado/editor.

```powershell
node --test scripts/tests/windows-payload.test.mjs
node scripts/windows-payload.mjs verify '<salida>/payload' '<salida>/payload-manifest.json'
```

No se promete identidad de bytes entre fechas, máquinas o compiladores. No se
abre SQLite, accede a Credential Manager, mueve sesión Drive ni ejecuta la app
personal. El instalador futuro debe conservar los contratos EP-004/006/T01/T03;
este script solo prepara archivos. EP-020 no añade dependencia: patrimonio fue
entregado por EP-009/017 y EP-026 MA-TSK-212 según el contrato de la épica.

## Ensayo obligatorio en Windows limpio (pendiente)

Ejecutar únicamente en VM/perfil desechable, Windows 10 y 11 x64, con datos
sintéticos y cuenta estándar. Registrar versión Windows, commit y hashes,
ausencia de Flutter/Dart/VS/Node y de runtime C++ global. Transferir la carpeta
completa antes de desconectar red, verificar hashes y arrancar desde ruta con
espacios/acentos. Abrir Inicio, leer/escribir/reabrir SQLite sintética, navegar
las pantallas y comprobar fuentes/plugins; confirmar ubicación de soporte
RoamingAppData y carga app-local del CRT. No copiar DLL de System32 ni instalar
runtime para hacer pasar la prueba. Registrar bloqueos/crashes y archivos
faltantes; no sustituir el ensayo por un build `APP_ENV=test` ni una prueba en
el PC del desarrollador. T08 añade instalación, actualización, reparación,
conservación y desinstalación sobre el paquete final de T05/T06/T07.
