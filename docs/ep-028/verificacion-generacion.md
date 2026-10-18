# Verificación MA-TSK-233 — generación privada y CI

Fecha: 2026-10-18. Alcance: T06 de EP-028, sobre T05 entregado. Se usa el ticket
y sus criterios facilitados en la sesión. No se modifican otras épicas ni la
lógica financiera, Drive, SQL o migraciones. La guía operativa está en
[generacion-privada.md](generacion-privada.md).

## Comprobaciones locales

- Flutter 3.47.0 / Dart 3.13.0: inicialización y `check-toolchain.ps1` correctos.
  Lockfile sin cambios.
- `node --test scripts/tests/windows-delivery.test.mjs scripts/tests/windows-installer.test.mjs scripts/tests/windows-payload.test.mjs`:
  **23/23**. Incluye cierre completo de una entrega sintética, calidad fallida,
  versiones/commit/entorno divergentes, hash/bytes/firmas alterados, licencias,
  dependencias, inventario, rechazo de extras y salida preexistente. Un EXE
  alterado no produce manifiesto de entrega. Los archivos sintéticos se retienen
  exclusivamente bajo la salida ignorada.
- C++ nativo: `installer_files` y `bridge_abi`, **2/2** correctos. Compilación
  local de ambos fixtures x64 estáticos e instaladores Inno 6.5.4 correcta.
  La sonda `verify_fixture` comprueba en modo solo lectura las mismas consultas
  de recursos que el instalador: CompanyName, ProductName, InternalName y
  OriginalFilename; ejecución local correcta. También se ejecuta en CI antes
  de empaquetar cada fixture.
  Se usa VS2026 Insiders/MSVC local únicamente para estas pruebas; no se presenta
  como toolchain de producción. No se ejecuta ninguno de esos EXE localmente.
- `actionlint` del workflow nuevo, parser PowerShell y `git diff --check`:
  correctos. El script de CI rechaza el entorno local antes de instalar; el
  generador de producción rechaza el checkout sucio antes de compilar.
- `git check-ignore`: tanto `dist-private/windows/...` como
  `.tools/installer-ci-report/report.json` están ignorados. Ningún EXE,
  manifiesto generado, licencia extraída, token o dato personal se versiona.

MSBuild necesitó ejecución fuera del sandbox tras un acceso denegado de
FileTracker. La primera calidad Flutter no pudo consultar pub.dev dentro del
sandbox; se repitió con acceso de red autorizado. No se modificó la configuración
global de Git ni de Flutter para eludir esos errores.

`check-quality.ps1`: resolución con lockfile correcta, **505 archivos de formato
sin cambios**, análisis **sin incidencias** (106,2 s). La suite general termina
en **2009 correctas / 4 fallidas**, 13 min 28 s. Fallan los dos recorridos de
`test/movements/pending_lifecycle_test.dart` (Windows/Android, `StateError: No
element` en `pending_lifecycle_journey.dart:144`) y dos escenarios de
`test/synchronization/local_recovery_journey_test.dart` (dos manuales/restauración
y fallo de disco/rollback). No se atribuye su origen sin una comparación de
baseline; no hay cambios de este ticket en esos módulos ni se modifican para
obtener un verde artificial. El script aborta ante el fallo; su bloque posterior
de cuatro variantes APP_ENV no llega a ejecutarse. Por ello no se declara calidad
global aprobada y el comando de producción tampoco emitiría una entrega
verificada con este resultado.

No se compila APK ni el runner Flutter como validación de esta automatización:
no hay cambios Dart/Android ni de la app nativa, y las compilaciones pertinentes
de este ticket son los adaptadores/PE sintéticos y el script Inno. El build
production real conserva los bloqueos indicados más abajo.

## CI y límites de aceptación

El primer job hospedado de `2cb4215` compiló Inno y los fixtures, pero falló al
ejecutar la instalación. No publicó informe ni binarios. Se añadió diagnóstico
de código de salida y líneas de error con rutas eliminadas; los logs completos
siguen sin ser artifacts.

La repetición diagnosticó `INSTALL-5` en `InitializeWizard`, antes de sustituir
archivos. El job pasó al asignar al fixture TEMP/TMP canónicos en `.tools` en
lugar del temporal del perfil hospedado; esto apunta a su alias 8.3, rechazado por
la identidad nativa. No se relaja esa validación ni se comparte identidad entre
rutas. El aislamiento del perfil sigue siendo la VM efímera, no esas variables.

Ejecución hospedada comprobada:
[39096515907 / commit 61b03bd](https://github.com/CarlosMG91/myautofinance/actions/runs/39096515907),
**correcta**. Instalación inicial, reparación, actualización, downgrade rechazado,
inventario completo, acceso de Inicio, desinstalación y sentinela conservado.
La API de artifacts devuelve **un único archivo comprimido de 407 bytes**,
`installer-fixture-report-61b03bd...`; descargado e inspeccionado: contiene solo
`report.json` (435 bytes), con commit, nombres de checks, `result=passed`,
`productionInstaller=not-built` y `realWindowsE2E=pending T08`. No contiene rutas,
logs, EXE, credenciales ni datos financieros.

La última versión funcional, incluida la sonda de recursos antes del
empaquetado, también pasa en
[39096760539 / commit af29ecf](https://github.com/CarlosMG91/myautofinance/actions/runs/39096760539).
Los 23 contratos Node se repiten tras los últimos cambios: **23/23**; parser
PowerShell y `actionlint` correctos. El cierre documental posterior no altera
scripts ni workflows.

El paquete **real de producción no se ha generado**: OAuth público sigue
`blocked_external`, faltan VS2022/MSVC 14.44.35207 y el CRT fijado; además este
checkout contiene cambios concurrentes y `build/` previo. Las barreras no se
desactivan para fabricar una entrega. No se asigna SHA256 de producción ni se
declara aceptación visual, offline, credenciales o conservación del paquete real.
Esa aceptación corresponde a T08 sobre Windows 10/11 estándar desechable.

Los cambios ajenos presentes al inicio en README, sincronización y documentación
de otras épicas permanecen fuera de los commits propios. La rama configurada
es `ticket/ma-tsk-193`, remoto `origin`; se usa sin force ni cambio de visibilidad.
