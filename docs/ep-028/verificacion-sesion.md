# MA-TSK-230 · Verificación y límites

2026-10-17. Implementación y contrato de integración en
[mantenimiento-sesion.md](mantenimiento-sesion.md).

## Comprobaciones

- Epic Board consultado en `GET http://localhost:4310/api/data`: MA-TSK-230 en
  curso, MA-TSK-228 completado. No se modifica el tablero ni otras épicas.
- Flutter 3.47.0 / Dart 3.13.0 inicializados y `check-toolchain.ps1` correcto.
  `flutter pub get --enforce-lockfile` correcto al habilitar red; primer intento
  restringido falló al consultar pub.dev. SDK y lockfile permanecen intactos.
- `scripts/check-windows-maintenance.ps1`: **28 casos correctos**, con MSVC
  19.51.36260 / SDK 10.0.26100.0 y `/W4 /WX /EHsc /utf-8`. CTest correcto,
  sin warnings. Diez puntos de fallo de E/S y snapshots de todas las escrituras
  del protocolo, incluidos respuesta perdida y terminación de mantenimiento.
  El caso de hash usa BCrypt real sobre rutas literales, sin leer credenciales.
- El ejecutable nativo sin opt-in retorna **77**, antes de acceder a HKCU o
  Credential Manager: barrera de aislamiento comprobada. No equivale a ejecutar
  sus casos de credenciales bajo usuario desechable.
- Windows release `--no-pub --dart-define=APP_ENV=test`: compilado, sin ejecutar
  la app en el perfil personal. `check-windows-installation-contract.ps1` sobre
  el PE comprueba x64, `0.1.0+1` y recursos de identidad/soporte correctos.
  Es compilación de regresión con VS18/MSVC local, no un payload producción
  con la toolchain auditada de T02. No hay EXE/secretos versionados ni publicación.
- `scripts/check-quality.ps1`: formato correcto (505 archivos, 0 cambios),
  análisis sin incidencias y suite **2.009 correctas / 4 fallidas**, 14 min 46 s
  de pruebas. El comando termina con error; detalles a continuación.
- `git diff --cached --check`: correcto. Solo doce archivos propios preparados;
  los cambios concurrentes de README/sincronización y prototipos quedan fuera.
- No hay código Android modificado: integración exclusivamente en el runner
  Windows. No se toma un build Windows como validación Android.

La suite general presenta cuatro casos fallidos en módulos no modificados:

- `pending_lifecycle_test.dart`, Windows y Android: `No element` en el
  recorrido compartido de pendientes, línea 144.
- `local_recovery_journey_test.dart`, dos copias manuales y recuperación:
  timeout de 30 segundos y archivo bloqueado al eliminar el temporal.
- En el mismo archivo, fallo de disco tras instalar: `CouldNotRollBackException`
  al cerrar el canal de isolate.

Son los mismos casos registrados en
[verificacion-contrato.md](verificacion-contrato.md); no se atribuye causalidad
ni se corrigen módulos ajenos en este ticket. El control general no pasa y su
bloque posterior de cuatro variantes `APP_ENV` no se ejecuta al fallar la suite.
Logs completos locales ignorados: `.tools/ma-tsk-230-quality.log`,
`.tools/ma-tsk-230-native.log` y `.tools/ma-tsk-230-windows.log`.

## Pruebas reproducibles

Desde un Developer PowerShell con CMake y Visual Studio C++:

```powershell
./scripts/check-windows-maintenance.ps1
```

Compila librería y ambos ejecutables. CTest ejecuta solamente el almacén en
memoria y el hash nativo sobre rutas literales sintéticas. No lee credenciales,
HKCU ni datos personales. Incluye inspección sin creación, soporte redirigido,
versión/downgrade, exclusión/busy, rutas exactas, consentimiento/nonce, destino
ocupado, update/repair sin limpieza, uninstall propio/idempotente, cancelación,
fallos de E/S, recuperación en cada frontera durable y conflicto de secretos.
Los snapshots de interrupción son estados sintéticos del puerto en memoria;
no equivalen a cortar un proceso ni a probar durabilidad real del registro.

La prueba real `maintenance_native_tests` **no** está registrada en CTest.
Debe ejecutarse en una VM Windows 10/11 x64 con usuario estándar nuevo llamado
`AutofinanceTest_<sufijo>`, sin datos ni credenciales personales. Rechaza ejecución
sin opt-in, bajo otro nombre de usuario, fuera de su raíz de fixtures, con
marcadores previos o con soporte ya existente. No crear esos fixtures en el
perfil personal. Preparar tres copias del EXE validado bajo el perfil desechable:

```text
%LOCALAPPDATA%\AutofinanceMaintenanceTest\Origen á\myautofinance.exe
%LOCALAPPDATA%\AutofinanceMaintenanceTest\Destino\myautofinance.exe
%LOCALAPPDATA%\AutofinanceMaintenanceTest\Independiente\myautofinance.exe
```

Ejecutar desde el mismo perfil, pasando las tres rutas exactas:

```powershell
.tools/ma-tsk-230-native/Release/maintenance_native_tests.exe --isolated-synthetic-credentials <origen-exe> <destino-exe> <independiente-exe>
```

La prueba crea únicamente credenciales sintéticas nuevas y sentinelas de
finanzas en soporte inicialmente ausente. Verifica transferencia a GUID propio,
lectura byte a byte en Credential Manager, limpieza del origen, reparación sin
desconectar, uninstall idempotente sin afectar la instalación independiente y
preservación exacta de archivos de base/WAL/copias/diario/drive-sync. Las
sentinelas no son una base SQLite ni una migración. Descartar el perfil tras el
ensayo; ante fallo quedan identificadores sintéticos para diagnóstico local.
No adjuntar blobs, perfiles ni dumps al repositorio.

## Pendiente para aceptación

No se ha proporcionado un usuario/VM desechable en esta sesión. **No se ejecutó la
prueba real de Credential Manager**, ni el arranque del runner con
`getApplicationSupportDirectory()` antes/después de instalar, ni la exclusión
de procesos/handles en Windows limpio, ni un corte real durante el registro.
La compilación y el modelo de estados no acreditan esos criterios nativos.

T05 debe enlazar el host/adaptador de Inno y mantener su objeto a través de
renombrado/reemplazo; T08 verifica paquete real, cierre/segunda instancia,
instalación desde destino inexistente, actualización N→N+1, reparación,
desinstalación/reinstalación y recuperación tras terminación real del host.
El ensayo de ruta efectiva debe usar el runner y path_provider, diferenciándolo
del contraste nativo por VERSIONINFO/Known Folder. Comprobar la matriz
Windows 10/11; esta sesión no aporta evidencia de cliente Windows limpio.

OAuth productivo sigue siendo la configuración externa existente; no se
solicita consentimiento real ni se afirma renovación Google por una credencial
sintética. Los bloqueos de producción de T02 son independientes del protocolo.
No se puede dar por completa la aceptación de MA-TSK-230 hasta superar las
pruebas nativas aisladas. No se infiere aprobación visual de T04 ni aceptación
de otros tickets a partir de estos resultados.
