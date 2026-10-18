# MA-TSK-232 · Verificación y límites del instalador

Implementación: [instalador-inno.md](instalador-inno.md). **Aceptación nativa
incompleta**: no se dispone de usuario/VM desechable ni del payload de producción
válido de T02. No se ha instalado sobre el perfil personal ni se ha publicado
un EXE. La compilación de fixtures no acredita instalación real.

## Evidencia de requisitos y aislamiento

Epic Board consultado mediante `GET /api/data`: MA-TSK-232 en curso;
MA-TSK-229/230/231 completados. La aprobación visual del usuario de T04 consta
en [prototipo/aprobacion.md](prototipo/aprobacion.md), timestamp
`2026-10-17T19:10:23.188Z`, URL y SHA256 conservados. No se cambia el mockup,
el tablero ni ninguna otra épica.

Se preserva la rama configurada `ticket/ma-tsk-193`. Los cambios concurrentes
de README, sincronización, prototipos y fixtures ajenos quedan fuera del commit.
Los EXE, DLL, manifiestos generados y logs permanecen bajo `.tools/` o
`dist-private/`, ignorados por Git. El ticket no entrega hosting, Releases,
artefactos públicos, certificados ni cambios de confianza de Windows.

## Pruebas específicas

- `scripts/check-windows-installer.ps1`: compila el adaptador Win32 `/MT` y
  librería T03 con MSVC **19.51.36260**, SDK **10.0.26100.0**, generador local
  VS18, y el script con Inno **6.5.4**. Este compilador es una herramienta de
  **prueba**, no el MSVC de producción fijado. El builder de producción exige
  VS2022/MSVC 14.44.35207 y no tiene bypass para VS18.
- CTest de archivos sintéticos: **17 casos**, con handles Windows reales.
  Incluyen rutas con espacios/acentos, comparación numérica, rutas
  prohibidas/reservadas, instalación inicial, DLL bloqueado antes de cambios,
  EXE retenido con share DELETE, cancelación/reposición de archivos, reparación
  de contenido alterado, archivo desconocido conservado, colisión ajena
  rechazada, interrupción y downgrade, reintento, hash erróneo, recibo temporal,
  manifiesto instalado erróneo, varios intentos con archivos retirados y
  directorio de recuperación ajeno. Sin HKCU, Credential Manager ni SQLite.
- CTest ABI: carga el DLL compilado, verifica las diez exportaciones `stdcall`
  sin decoración que consume Inno y el fallo cerrado sin operación inicializada.
  No inicializa una instalación ni consulta el perfil.
- Node: **19 pruebas**, siete de instalador y doce del payload T02. Versiones,
  identidad, commit limpio, hashes/CRT/licencias, imports Win32 normales/delay
  sin CRT global, inventario cerrado, rutas reservadas/inyección, salida privada
  con rechazo de raíz/otra unidad, EXE al final y no sobrescribir una entrega.
- Inno genera un EXE de **fixture** con payload falso que carece de recursos
  VERSIONINFO de aplicación: el adaptador lo rechazaría antes de consultar una
  instalación. Se comprueban sintaxis Pascal, secciones, constantes, recursos,
  idioma, compresión y creación real de EXE/desinstalador. **No se ejecuta**.
  El archivo no es un instalador de producción ni debe distribuirse.
- El DLL real solo importa `advapi32`, `bcrypt`, `kernel32`, `ole32`, `shell32`,
  `user32` y `version`; no carga un runtime x86 externo. Esta inspección no
  sustituye el ensayo en Windows sin SDK/runtime global.
- `scripts/check-windows-maintenance.ps1`: regresión T03 correcta, **28 casos**
  del protocolo/hash. No se ejecuta `maintenance_native_tests`: su contrato
  exige usuario desechable para Credential Manager.
- Parseo PowerShell de los scripts y pruebas de sintaxis Node correctos.
  El builder de producción rechaza correctamente el checkout sucio **antes**
  de compilar o generar archivos, sin guardar ni confirmar cambios ajenos.

## Calidad Flutter y regresión de plataforma

Flutter **3.47.0** / Dart **3.13.0** inicializados; `check-toolchain.ps1`
correcto. La primera ejecución de calidad falló al consultar `pub.dev` por la
restricción de red. Se repitió con acceso autorizado, sin actualizar SDK ni
lockfile. Formato de 505 archivos sin cambios y análisis sin incidencias.

La suite general **no pasa**: registró **1.997 pruebas correctas y 13 fallidas**
y después dejó de avanzar en el recorrido de rediseño 412.0/1.0. Se detuvo
exclusivamente esa ejecución y sus workers, tras comprobar su proceso padre;
el comando termina interrumpido, **no** con resultado global completo. Los
fallos registrados pertenecen a módulos no modificados por T05:

- `report_drilldown_journey_test.dart`: recorrido Windows de tres informes.
- `pending_lifecycle_test.dart`: recorridos Windows y Android de pendientes.
- `local_recovery_journey_test.dart`: cuatro recorridos de recuperación, disco,
  retención e interrupción de worker.
- `local_restore_test.dart`: fases validated/completed del diario.
- `local_restore_candidate_test.dart`: migración interrumpida y motivo tipado.
- `drive_two_installations_test.dart`: edición durante subida y carrera.

Se observaron `No element`, timeouts, conexiones de isolate cerradas, diferencias
de estado y temporales bloqueados. La ejecución presenta saltos prolongados de
tiempo; no se establece su causa ni se atribuyen todos los fallos a los ya
documentados en tickets anteriores. No se modifica ni repite entera esa suite.
Su bloque posterior de cuatro variantes `APP_ENV` no llegó a ejecutarse.

`flutter build windows --release --no-pub --dart-define=APP_ENV=test`: correcto,
37,2 s, sin ejecutar el runner. Configuración Flutter aislada mediante
`APPDATA=.tools/ma-tsk-232-windows-config`, sin cambiar la configuración global.
El verificador T01 sobre `build/windows/x64/runner/Release/myautofinance.exe`
confirma x64, `0.1.0+1`/`0.1.0.1` y recursos de identidad/soporte correctos.
Es una regresión con MSVC local, no producción T02 ni prueba de instalación.
No hay cambios Dart/Android ni motores financieros en este ticket; no se
compila Android para validar este adaptador exclusivo de Windows.

## Bloqueos de producción y aceptación pendiente

Comprobados de nuevo: configuración OAuth pública devuelve «proyecto y clientes
pendientes» con `--require-configured`; VS2022 y el CRT fijado siguen ausentes.
La configuración global Flutter existente usa un `build-dir` personalizado;
el preparador T02 exige un checkout sin `build/` y su configuración compatible,
y no se altera incidentalmente. No se ha generado un paquete de producción
ni el manifiesto final T06, y no se le atribuye un hash de entrega.

No se ha proporcionado un usuario/VM Windows desechable. Quedan sin ejecutar:

- Instalación/actualización/reparación/uninstall real con Inno y su registro,
  accesos, salida silenciosa, código 12 y apertura final opcional.
- Windows 10/11 x64 estándar, offline sin SDK/CRT global, sin UAC, perfil con
  espacios/acentos, teclado, foco, DPI 100/125/150/200 % y alto contraste.
- Runner real abierto/borradores/segunda instancia, archivos mapeados por otros
  procesos, falta de espacio/permisos y cortes reales de Setup/Uninstall.
- Transferencia y conservación de sesión en Credential Manager sintético,
  recuperación de diarios T03, independencia de otra instalación, limpieza
  propia al desinstalar, reinstalación desconectada y conservación financiera
  byte a byte. Las pruebas en memoria/archivos no acreditan OAuth Google real.
- Igualdad efectiva del soporte path_provider antes/después, migración y
  respaldo SQLite por el store, y cifras EP-001 con el paquete final T08.

La matriz reproducible y las siguientes acciones están en
[instalador-inno.md](instalador-inno.md). No se declara completada la aceptación
nativa ni la épica a partir de tests o compilación. EP-027 y EP-025 no se
convierten en dependencias; la equivalencia de patrimonio EP-009/017 y
EP-026/MA-TSK-212 permanece documentada en el contrato T01.

Logs privados de la sesión: `.tools/ma-tsk-232-quality*.log`,
`.tools/ma-tsk-232-installer*.log`, `.tools/ma-tsk-232-maintenance.log`.
