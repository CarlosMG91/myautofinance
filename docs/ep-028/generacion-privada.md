# Generación privada y validación — MA-TSK-233 / T06

El comando local genera desde fuentes un instalador **production** y cierra una
carpeta de entrega manual privada. No descarga ni instala Autofinance, no publica
archivos y no cambia la visibilidad del repositorio. El workflow separado solo
construye e instala un fixture sintético; sus resultados no certifican el paquete
real ni sustituyen T08.

## Reproducir localmente

Usar un checkout nuevo y limpio del commit que se entregará, sin `build/` y sin
cambios concurrentes. No limpiar ni reutilizar un árbol de compilación compartido.
Preparar el SDK de `toolchain.json`, el lockfile existente, VS2022/MSVC y el CRT
de `packaging/windows/payload-toolchain.json`, y la configuración OAuth pública
aprobada. `flutter config --machine` debe indicar `build-dir=build` (o no fijarlo);
usar una configuración Flutter aislada si la personal difiere. Los scripts no
modifican automáticamente la configuración global. Requisitos y procedencia del
runtime/licencias: [payload-windows.md](payload-windows.md).

Obtener manualmente Inno **6.5.4** desde la URL exacta versionada en
`packaging/windows/payload-toolchain.json`. El SHA256 esperado también está fijado
allí, junto con su fuente de comprobación. Prepararlo por usuario mediante:

```powershell
./scripts/prepare-inno-setup.ps1 -InstallerPath 'C:/ruta/innosetup-6.5.4.exe'
```

El preparador compara SHA256 **antes de ejecutar** el instalador de la herramienta,
comprueba la versión real mediante `VER` de ISCC y deja recibo de procedencia y
hashes de sus archivos en `.tools/inno-6.5.4`. La generación vuelve a comprobarlos;
no acepta `latest`, una instalación Inno global sin recibo ni otro compilador de
producción. La preparación de herramientas es previa; no forma parte de la
instalación offline de Autofinance en el equipo destinatario.

```powershell
./scripts/build-private-windows-delivery.ps1 `
  -RuntimeCrtDirectory 'C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Redist/MSVC/<version>/x64/Microsoft.VC143.CRT' `
  -VisualStudioLicensePath 'C:/Program Files/Microsoft Visual Studio/2022/Community/<licencia oficial>' `
  -InnoDirectory '.tools/inno-6.5.4'
```

Las rutas de CRT/licencia son ejemplos que se deben sustituir por las de la
instalación oficial verificada; nunca tomar DLL de System32. CMake debe estar en
PATH o indicarse con `-CMake`. El comando:

1. Rechaza CI, fuentes sucias, `build/` preexistente, SDK distinto y OAuth pendiente.
2. Exporta exactamente HEAD a `.tools/delivery-quality-*` y ejecuta allí
   `check-quality.ps1`: lockfile, formato, análisis, pruebas y variantes de entorno.
   Así las salidas de pruebas no contaminan el árbol de producción. Conserva esta
   exportación ignorada para diagnóstico, sin borrar trabajo compartido.
3. Ejecuta los contratos Node de payload/instalador/entrega. Reutiliza T02 para
   construir Windows release con `APP_ENV=production`, dependencias fijadas y CRT
   app-local. No convierte el runner `APP_ENV=test` de CI en producción.
4. Reutiliza T05: compila/prueba el adaptador Win32 `/MT`, comprueba su cierre de
   dependencias y compila el instalador Inno. Inspecciona la versión PE del EXE y
   exige `NotSigned` en esta primera entrega. Versiones app/PE/Inno/manifiestos
   deben coincidir con `pubspec.yaml`.
5. Comprueba commit, limpieza, inventarios, tamaños, checksums, licencias y prueba
   de calidad; copia la entrega y escribe **al final** `delivery-manifest.json`.

Un fallo lanza error y bloquea el manifiesto final. Puede dejar archivos parciales
de diagnóstico, que no son una entrega verificada. No existe `-SkipQuality` ni
sustitución automática de versiones. Las salidas no se sobreescriben; para
repetir desde cero, usar otro checkout limpio. Un manifiesto de payload o de build
individual sigue siendo candidato y no sustituye al manifiesto de entrega.

## Salida y transferencia manual

Todo queda bajo `dist-private/windows/`, ignorado por Git. La carpeta transferible
es `installer-<version>-<commit12>/delivery/` e incluye EXE, licencias y avisos,
manifiestos de payload/build/calidad y `delivery-manifest.json`. Este registra
versión, commit, toolchain, origen/hash de Inno, estado de firma y tamaño/SHA256
de **cada archivo** de la carpeta, excluyéndose a sí mismo.

```powershell
node scripts/windows-delivery.mjs verify 'dist-private/windows/installer-<version>-<commit12>/delivery'
Get-FileHash -Algorithm SHA256 -LiteralPath 'dist-private/windows/installer-<version>-<commit12>/delivery/delivery-manifest.json'
```

El verificador detecta archivos cambiados, ausentes o adicionales. Comparar
también el hash del propio manifiesto por un canal privado acordado. SHA256
detecta cambios accidentales: **no acredita autoría, confianza ni reputación
SmartScreen**. El instalador inicial no está firmado; no se añaden certificados,
secretos de firma ni excepciones a las protecciones de Windows.

Transferir la carpeta completa por el medio privado manual acordado, conservando
versión y manifiesto. No subir EXE/manifiestos/licencias generados a Git, GitHub
Releases, Actions artifacts públicos, Pages ni un hosting nuevo. Comprobar
`git check-ignore` y `git status` antes del commit; añadir solo fuentes concretas.
La app no descarga ni ejecuta instaladores al arrancar y no hay proceso residente
de actualización. La actualización sigue siendo manual con el nuevo instalador.

`verification.status=buildVerified` significa que pasaron los controles de
construcción, **no** la aceptación de instalación real. El manifiesto declara
`cleanWindowsE2E=pending T08`. Antes del cierre de épica se debe ejecutar T08 con
el paquete real en Windows 10/11 x64 limpio/usuario estándar desechable: offline,
actualización, conservación de datos/GUID/sesión, desinstalación y recuperación.
No probar la instalación sobre el usuario personal. Ver
[instalador-inno.md](instalador-inno.md) y el contrato T01; el instalador nunca
ejecuta SQL ni copia bases vivas ni baja esquemas.

## CI público con fixture aislado

`.github/workflows/windows-installer.yml` tiene solo `contents: read`. Ejecuta
Node y C++ nativos, obtiene Inno de la URL fijada y verifica su hash antes de
prepararlo. Compila dos PE x64 mínimos, sin Flutter ni motores financieros,
con versiones sintéticas `0.0.0+1` y `0.0.0+2`, enlazados con CRT estático y una
identidad de recursos compatible para recorrer el instalador real sin cambiarlo.
El payload lleva `NOT-A-DELIVERY.txt`. No es el producto ni se distribuye.

`check-windows-installer-ci.ps1` solo admite un runner Windows **github-hosted**
desechable; rechaza ejecución local y self-hosted. Verifica que no exista destino,
soporte, registro de desinstalación ni marcadores Drive antes de escribir. La
aislación es el perfil/VM efímero del job, no redefinir APPDATA: las APIs nativas
de carpetas conocidas, HKCU y Credential Manager no se aíslan con esa variable.

Prueba instalación silenciosa, reparación, actualización, rechazo del downgrade,
inventario instalado completo, acceso en Inicio, desinstalación y conservación de
un texto sintético en soporte. Usa `/NORESTART`, sin apertura final ni traspaso de
Drive. No crea datos financieros, tokens ni credenciales. Si falla, el job falla;
no ejecuta una limpieza indiscriminada. El runner se desecha al finalizar.

Solo se conserva `.tools/installer-ci-report/report.json` por 14 días: estado,
commit y nombres fijos de comprobaciones, sin rutas personales ni logs de Inno,
binarios, perfiles o secretos. Ningún EXE del fixture o de producción se sube.
Los artifacts `APP_ENV=test` del workflow Flutter existente continúan siendo
compilaciones de prueba públicas; no constituyen un canal privado de entrega.

Referencia: [parámetros oficiales de Inno](https://jrsoftware.org/ishelp/topic_setupcmdline.htm).
