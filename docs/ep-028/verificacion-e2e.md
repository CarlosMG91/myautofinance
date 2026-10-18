# MA-TSK-235 · Evidencia y bloqueos de aceptación

Fecha: 2026-10-18. **T08 no completado; EP-028 no aceptada.** No se ha ejecutado
el instalador de producción ni se le asigna SHA256. El trabajo de esta sesión
prepara el ensayo mediante [plan-e2e-windows.md](plan-e2e-windows.md) y el control
de coherencia de las dos entregas; no sustituye la aceptación del paquete real.

## Requisitos comprobados

Se consultó Epic Board `GET http://localhost:4310/api/data`: tablero **My
autofinance**, workspace coincidente, MA-TSK-235 en curso, dependencias
MA-TSK-233/234 completadas. Sus informes conservan limitaciones de producción
y pruebas nativas pendientes aunque el tablero marque entregado su desarrollo.
Se leyó el contrato T01, generación T06, guía T07 y evidencia previa T02/T03/T05.
No se modifica el tablero ni otras épicas.

Bloqueos constatados de nuevo:

1. `node scripts/check-google-oauth.mjs --require-configured` termina con código
   **1**, «proyecto y clientes OAuth pendientes». La configuración pública sigue
   `blocked_external`, con cliente Windows nulo y Drive sin habilitar. No se
   sustituyen esos valores por credenciales ficticias para producir una entrega.
2. VS2022/MSVC **14.44.35207** y CRT **14.44.35211.0** fijados no están disponibles
   en las ubicaciones de producción documentadas. La instalación localizada es
   **VS18 Insiders**; `vswhere -version [17,18)` no aporta VS2022. VS18 sirve para
   regresión sintética, no se presenta como toolchain de producción.
3. En `dist-private/` solo se localizaron manifiestos de fixtures sintéticos de
   pruebas. No hay dos entregas reales T06 N/N+1. La versión fuente sigue
   `0.1.0+1`; no se alteran versiones, manifiestos ni flags para simularlas.
4. No se ha proporcionado una VM/perfil desechable utilizable. Windows Sandbox
   no está presente en System32; no se localizaron comandos Hyper-V `Get-VM`,
   VirtualBox o VMware. `vmcompute` activo por sí solo no proporciona un cliente
   limpio ni autorización para usar una VM personal. El host tiene SDK/VS y no
   acredita ausencia de CRT global. Se leyó build **26300.9711**, x64; la etiqueta
   de registro «Windows 10 Home» no se utiliza para afirmar cobertura Windows 10.
   CIM del sistema operativo denegó acceso en el sandbox. No se inspeccionaron
   credenciales, marcadores Drive ni soporte financiero del usuario.
5. El checkout contiene cambios concurrentes en README y sincronización, además
   de `build/` previo. T06 exige fuentes limpias y salida nueva. Se necesita un
   checkout independiente para generar; no se limpian ni confirman cambios ajenos.

No se ejecuta Setup/Uninstall sobre el perfil personal ni se desinstala el runtime
global del host para fabricar un entorno limpio. No se atribuye al CI Server
de T06 una prueba de cliente Windows. EP-025 bloqueada y EP-027 pendiente no se
usan como dependencias de este ticket.

## Comprobaciones realizadas en esta sesión

- Flutter **3.47.0** / Dart **3.13.0** inicializados; `check-toolchain.ps1`
  correcto. `toolchain.json` y `pubspec.lock` sin cambios propios.
- `node --test scripts/tests/windows-e2e-inputs.test.mjs scripts/tests/windows-delivery.test.mjs scripts/tests/windows-installer.test.mjs scripts/tests/windows-payload.test.mjs`:
  **27/27** correctas. Cuatro pruebas nuevas cubren el par numérico N/N+1,
  igualdad/downgrade, commit repetido, incoherencias de manifiestos aun con
  inventario externo recalculado, bytes alterados, extras y entrada ausente.
  Los bytes sintéticos deliberadamente no ejecutables demuestran que el resultado
  del control es solo `inputsConsistent` con `e2e=notExecuted`.
- `node docs/ep-001/verificar-casos.mjs`: **OK**, 48 presupuestos/10 reales,
  enero +1.229,75, anual real +2.329,65 y previsto +13.200,00 EUR. Es aritmética
  del CSV, no evidencia de las pantallas instaladas ni de conservación SQLite.
- `check-windows-maintenance.ps1` con CMake local y generador VS18:
  compilación y CTest **1/1** correctos (`maintenance_state_machine`, almacén
  en memoria/hash). No se ejecuta `maintenance_native_tests` con opt-in ni se
  accede a Credential Manager.
- `check-windows-installer.ps1`, mismo generador: CTest **2/2** correctos
  (`installer_files`, `bridge_abi`), contratos Node y compilación Inno **6.5.4**
  correctos. Se genera únicamente un fixture ignorado que **no se ejecuta**.
  Las pruebas de archivos usan handles Windows; no equivalen a Setup/Uninstall
  real ni al aislamiento de procesos del runner.

El primer intento nativo falló por `E_ACCESSDENIED` de MSBuild FileTracker;
se repitió correctamente fuera del sandbox mediante la revisión de permisos.
El primer `check-quality.ps1` se detuvo en `flutter pub get --enforce-lockfile`
por restricción de red al consultar advisories de pub.dev. La repetición con
acceso autorizado resuelve el lockfile, pasa formato (**505 archivos, 0 cambios**)
y análisis (**sin incidencias**, 33,5 s). La suite termina en **2.007 correctas /
6 fallidas**, 16 min 2 s; el comando sale con error. Fallan:

- `budget/budget_lifecycle_test.dart`: recorrido Android, timeout de 45 segundos.
- `drilldowns/report_drilldown_journey_test.dart`: recorrido Windows, `No element`.
- `movements/pending_lifecycle_test.dart`: Windows y Android, `No element`.
- `synchronization/local_recovery_journey_test.dart`: dos copias manuales y
  recuperación, timeout de 30 segundos; fallo de disco/rollback, resultado
  `recoveryRequired` donde se esperaba `restored`.

No se establece causalidad sin comparación de baseline. Estos módulos no se
modifican en T08; no se corrigen otras épicas ni se repite la suite para obtener
un verde. Las cuatro variantes `APP_ENV` posteriores del script no llegan a
ejecutarse por el fallo. **Calidad global no aprobada**: también bloquea el cierre
de una entrega T06 con estas fuentes/resultados.

Se usa configuración Flutter de proceso aislada bajo
`.tools/ma-tsk-235-flutter-config`, sin cambiar configuración global. Esto no
aísla un usuario Windows ni Credential Manager y no se usa como entorno E2E.

Logs de diagnóstico locales ignorados: `.tools/ma-tsk-235-maintenance.log`,
`.tools/ma-tsk-235-installer.log` y `.tools/ma-tsk-235-quality*.log`.
Sintaxis Node, enlaces documentales locales y `git diff --cached --check`
correctos. El CLI rechaza entradas ausentes con código 1 antes de ejecutar nada.
`git check-ignore` confirma la exclusión de entregas, fixtures y evidencias.
No se modifica Dart ni la app nativa: las compilaciones de esta preparación son
las de los adaptadores/fixture. No se compila APK como prueba de instalación
Windows; el build production pertinente permanece bloqueado.

## Matriz de aceptación real

| Criterio | Windows 10 x64 limpio | Windows 11 x64 limpio |
| --- | --- | --- |
| Offline, usuario estándar, sin SDK/VS/CRT global | No ejecutado | No ejecutado |
| Dos versiones reales, AppId/ruta/accesos sin duplicados | No ejecutado | No ejecutado |
| Pantallas EP-001 y ausencia/parcial/cero | No ejecutado | No ejecutado |
| Conservación IDs/revisión/SQLite/copias/diarios/estado Drive | No ejecutado | No ejecutado |
| Credential Manager sintético y refresco con proveedor controlado | No ejecutado | No ejecutado |
| Adopción explícita, destino ocupado y cancelación | No ejecutado | No ejecutado |
| App abierta/segunda instancia y exclusión | No ejecutado | No ejecutado |
| Disco/permisos/interrupción real y recuperación | No ejecutado | No ejecutado |
| Uninstall propio, datos conservados y reinstall desconectado | No ejecutado | No ejecutado |
| Downgrade/esquema futuro sin reset y respaldo de migración | No ejecutado | No ejecutado |
| Firma efectiva y SHA256 de producción | Sin paquete | Sin paquete |

Tampoco se realiza OAuth Google real. Las pruebas en memoria, sentinelas,
compilaciones y el job CI anterior no se registran como éxitos de esta matriz.
La sonda nativa de refresco con proveedor controlado sigue sin integrarse ni
ejecutarse con el EXE final; T03 solo aporta su prueba aislada de almacenamiento.

Para continuar se necesitan las dos entregas production T06 verificadas, los
dos clientes limpios desechables y la sonda/proveedor de refresco. Ejecutar
E01–E12 del protocolo, conservar evidencia privada por entorno y actualizar esta
matriz con resultados observados. El estado actual no permite cerrar el ticket
ni la épica, ni afirmar publicación o entrega del EXE.

La rama configurada es `ticket/ma-tsk-193`, remoto `origin`; se conservan. Solo
se preparan los cuatro archivos nuevos propios de T08. Los cambios concurrentes
de README, sincronización, prototipos y fixtures ajenos quedan fuera. No se
versionan EXE, manifiestos generados, datos, credenciales o certificados.
