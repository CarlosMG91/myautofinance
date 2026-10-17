# MA-TSK-229 · Verificación del payload

2026-10-17. Implementación y comandos en [payload-windows.md](payload-windows.md).
**Aceptación incompleta:** no hay payload de producción validado ni ensayo de
arranque en Windows limpio. No se entrega un instalador con este ticket.

## Comprobado

- `flutter --version` y `scripts/check-toolchain.ps1`: Flutter 3.47.0,
  Dart 3.13.0. `flutter pub get --enforce-lockfile` correcto, sin modificar
  `toolchain.json` ni `pubspec.lock`.
- `node --test scripts/tests/windows-payload.test.mjs
  scripts/tests/google-oauth-config.test.mjs`: **26/26**, doce casos nuevos del
  payload y catorce del contrato OAuth. Fixtures sintéticos temporales,
  sin datos de la instalación personal. Cubre versión, rutas, cierre del
  inventario oficial CMake, SHA256/cambios/extras, SQLite dinámica, AOT x64,
  imports PE normales/delay, dependencias transitivas, Debug, exclusiones,
  enlaces y mapeo de native assets sin rutas del host.
- Parseo PowerShell de ambos preparadores y `node --check`: correctos.
- `flutter test --no-pub --dart-define=APP_ENV=production
  test/environment_bootstrap_test.dart`: **1/1**, arranque/configuración Dart
  de producción. No equivale al arranque del payload nativo en Windows limpio.
- Descarga real desde el release oficial de Inno **6.5.4**: SHA256 coincide
  con el pin `fa73bf47a4da250d185d07561c2bfda387e5e20db77e4570004cf6a133cc10b1`.
  Preparador ejecutado por usuario en `.tools/inno-6.5.4`: correcto. La prueba
  `compiler-version.iss` contrasta el símbolo real `VER` y compila con `/O-`
  sin crear instalador. Se comprobó que ISCC/ISCmplr no tienen VERSIONINFO útil;
  no se usa `0.0.0.0` como versión del compilador. Recibo de procedencia y
  hashes de dependencias/licencia locales, ignorados por Git.
- CMake rechaza el generador VS2026 para el modo de payload privado. La
  preparación rechaza el checkout sucio antes de compilar/copiar archivos.
- `check-windows-installation-contract.ps1 -ExecutablePath <runner>`:
  `myautofinance.exe`, `0.1.0+1`, tupla `0.1.0.1`, x64 y todos los recursos de
  identidad correctos; soporte derivado `%RoamingAppData%\com.carlosmg91\Autofinance`.
  Inspección sin ejecutar la app ni consultar datos/sesión personales.
- Comandos Windows release con `APP_ENV=production` y `APP_ENV=test` terminan
  correctamente. El último build de regresión test, tras el ajuste CMake,
  tardó 17,4 s. **Estos builds no son evidencia de un payload production
  entregable**: usaron toolchain local no fijada y salida reutilizada con
  `build-dir` personalizado. No se lanza ninguno en el perfil personal.
- `git check-ignore` confirma que `.tools/` y `dist-private/windows/` quedan
  fuera de Git. No se modifica ningún workflow público, SDK, lockfile ni
  archivo de otro ticket. No se compila Android: cambios exclusivos de Windows.

Los logs locales están bajo `.tools/ma-tsk-229*`, sin versionar rutas personales.
La comprobación general `scripts/check-quality.ps1` pasa formato (505 archivos,
0 cambios) y análisis estático. Pruebas Flutter: **2008 pasan y 5 fallan** en
14 min 54 s; por ello el control general termina con error. Fallos:

- `report_drilldown_journey_test.dart`: recorrido de tres informes Windows.
- `pending_lifecycle_test.dart`: recorridos Android y Windows de pendientes.
- `local_recovery_journey_test.dart`: restauración tras reinicios y rollback
  tras fallo de disco.

Estos módulos y pruebas no se modifican en T02. Se observaron `StateError`,
timeout y discrepancia de restauración; no se atribuye causalidad sin un ensayo
aislado. La evidencia anterior de T01 ya registraba cuatro fallos en pendientes
y recuperación, pero no prueba el origen del quinto de esta ejecución.

## Bloqueos y límites

1. `config/google-oauth.public.json`: `status=blocked_external`, cliente
   Windows `null`, proyecto/Drive todavía sin configurar. La validación
   `--require-configured` falla correctamente. No se crea ni sustituye cliente,
   proyecto o scope; preparar un paquete afirmando OAuth productivo sería falso.
2. El entorno disponible tiene VS **18 Insiders**, toolset **14.51.36231**;
   no contiene VS2022/MSVC **14.44.35207** ni CRT redistribuible fijado
   **14.44.35211.0**. No se copia el runtime incompatible ni DLL de System32.
   La rama de éxito con toolchain/runtime fijados sigue sin ensayar.
3. Flutter local usa un `build-dir` personalizado; el template Windows del
   SDK toma assets/AOT de `build/`. Los builds existentes incluyen archivos
   antiguos, como un `dartjni.dll` que importa `jvm.dll`, además del descriptor
   de tests con ruta absoluta. No se adopta ni se «arregla» ese árbol como
   producción, ni se inventa dependencia Java: se exige build nuevo, inventario
   oficial completo y fallo ante dependencias no resueltas. Cualquier DLL JNI
   que reaparezca en un build limpio requiere diagnóstico antes de entregar.
4. No se dispone de evidencia de una VM Windows 10/11 limpia/perfil desechable
   sin SDK/runtime global. Arranque offline estándar, carga real app-local,
   SQLite y fuentes/plugins quedan **pendientes**, con procedimiento en la
   guía. No se equiparan pruebas de inventario o build test a este criterio.
5. Generación del instalador y manifiesto final son T05/T06; instalación,
   actualización/conservación y desinstalación E2E son T08 tras T07. Nada de
   ello se declara aprobado. EP-027 y EP-025 no son bloqueos de este ticket.

La implementación deja controles reproducibles y falla ante condiciones no
demostradas. No puede darse MA-TSK-229 por aceptado hasta generar el payload real
con sus entradas válidas y superar el arranque limpio requerido.
