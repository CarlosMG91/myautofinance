# MA-TSK-232 · Instalador privado Inno Setup

Implementación T05 de [EP-028](contrato-instalacion.md), con el payload T02 y
los servicios T03. Consume la [aprobación explícita T04](prototipo/aprobacion.md).
Estado de pruebas y límites: [verificación](verificacion-instalador.md).
T06 sigue siendo dueño del manifiesto final y T08 de la aceptación del paquete
real en Windows limpio. No se ha publicado ningún binario.

## Generación local

Después de resolver los bloqueos de producción descritos en
[verificacion-payload.md](verificacion-payload.md), preparar el payload T02 y
el adaptador desde **el mismo commit limpio**. No incluir los cambios de otros
tickets para conseguir un checkout limpio; usar otro checkout si hace falta.
No actualizar toolchain, lockfile, OAuth ni CRT incidentalmente.

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
./scripts/build-windows-installer.ps1 `
  -PayloadDirectory '<salida-T02>/payload' `
  -PayloadManifestPath '<salida-T02>/payload-manifest.json' `
  -InnoDirectory '.tools/inno-6.5.4'
```

El script comprueba inventario completo, SHA256, versión de pubspec, AppId,
production/x64, commit, licencias, CRT y versiones/hashes de entradas. Verifica
la procedencia de Inno 6.5.4 preparada por T02, compila el adaptador con
VS2022/MSVC 14.44.35207/SDK 10.0.26100.0, ejecuta sus pruebas y compila el `.iss`.
No ejecuta instaladores, runner, OAuth ni comandos de administración.

Salida exclusiva `dist-private/windows/installer-<version>-<commit12>/`,
ignorada por Git. No sobrescribe una salida existente. Contiene el EXE,
`installer-build.json`, `installer-inputs.json`, inventario de propiedad e
include de compilación; estos dos últimos son entradas técnicas locales, no
instrucciones para la persona usuaria. `installer-build.json` registra tamaño,
SHA256 y estado Authenticode observado. Es un **candidato**, no el
`manifestVersion=1` final de T06 ni una entrega verificada por T08. La primera
entrega se genera sin firma; un hash permite detectar cambios y no acredita
autoría, editor o confianza de Windows. No cambiar protecciones del sistema.

Para T06, `installer-inputs.json.payload` contiene el payload T02 y el
adaptador instalado; `installationMetadata` añade tamaño/hash del inventario
`.autofinance-files` que también se instala. Se registra aparte para evitar
un hash autorreferente. El manifiesto final debe incorporar ambos conjuntos.
Los archivos de uninstall que genera Inno durante la instalación pertenecen
a su registro de desinstalación; no se inventan hashes de archivos aún no creados.

## Identidad y asistente

`packaging/windows/autofinance.iss` fija el AppId
`{82D31B27-9717-4DB7-AB32-D098BF3C2859}`, privilegios `lowest`, HKCU y destino
`%LOCALAPPDATA%\Programs\Autofinance`. No permite otro `/DIR`, directorios por
versión, ARM64, x86, HKLM, descargas, servicios, autoarranque ni ejecución del
desinstalador anterior. Windows 10/11 x64 es el destino de aceptación.

La interfaz en español conserva controles nativos, Segoe UI, colores y recurso
de icono existentes. Incluye bienvenida, accesos (escritorio sin premarcar),
selección opcional de origen exacto, revisión y consentimiento sin premarcar,
resumen con versiones/rutas/conservación, progreso y resultado. Menú Inicio
siempre por usuario. Apertura final desmarcada y omitida en silencioso; abrir
la app no ejecuta una subida/descarga Drive.

Se compara numéricamente la tupla completa contra registro y PE x64. Igualdad
repara; mayor actualiza; inferior bloquea antes del reemplazo. Registro,
directorio, PE o manifiesto incompatibles fallan cerrados. Una carpeta ajena
no registrada no se adopta como instalación. La versión máxima de una operación
interrumpida también impide downgrade. Una reparación repone archivos propios;
no revierte datos, copias o esquemas.

## Adaptador y exclusión

Inno **6.5.4 ejecuta un host Win32**. El adaptador privado
`installer/autofinance_setup_bridge.dll` se compila Win32 con `/MT` y solo
imports del sistema: no necesita un CRT x86 global. No cambia la arquitectura
x64 de Autofinance ni distribuye una app x86. Se enlaza la librería estática de
`windows/maintenance`; el runner no se usa como host. La ABI `stdcall` recibe
rutas/versiones y devuelve estados, nunca tokens, cuentas o secretos. No hay
IPC ni procesos con elevación. Setup carga el adaptador extraído en su temporal;
uninstall copia su adaptador propio a su temporal antes de cargarlo.

`prepareMaintenance` retiene el bloqueo T03 de destino y, cuando corresponde,
origen. Una app abierta permite cierre manual, reintento o cancelación. No se
manda WM_CLOSE ni taskkill. Una nueva instancia queda bloqueada por la concesión
del runner; el pin del EXE también deniega lectura/ejecución a runners antiguos.
`CloseApplications=no` y `RestartApplications=no` evitan cierre o relanzamiento
implícitos, también en silencioso.
Se rechazan `/CLOSEAPPLICATIONS`, `/FORCECLOSEAPPLICATIONS`,
`/RESTARTAPPLICATIONS`, `/NOCANCEL` y `/ALLUSERS`, porque algunos parámetros
Inno pueden sustituir directivas. El modo silencioso exige `/NORESTART`,
también al desinstalar; así una situación de reinicio pendiente no provoca un
reinicio automático. La matriz T08 debe ejercer estos parámetros reales.

En `ssInstall`, se revalidan registro, PE y `requestClose()` inmediatamente antes
de reemplazar. Se abre además cada archivo propio existente con permisos de
borrado y sin compartir lectura/escritura; un DLL retenido por otro proceso
bloquea antes de renombrar archivos. Solo después se renombran los archivos
anteriores al área propia `.autofinance-previous`, incluido el EXE fijado por
T03 (comparte DELETE). Inno escribe cada archivo explícito del inventario, sin
`restartreplace`, glob ni recursión. El EXE nuevo se copia **al final**, cuando
ya están disponibles sus dependencias; hasta entonces falta la ruta de arranque.
No se sobrescribe el EXE retenido en sitio.
Los bloqueos duran hasta finalizar o abortar. No se programa reemplazo al
reiniciar ni se pide reiniciar automáticamente.

Después de copiar se contrastan manifiesto instalado, tamaño y SHA256 de
**cada** archivo antes de transferir sesión o anunciar éxito. La actualización
no invoca cleanup de sesión ni el desinstalador previo. Los datos nunca entran
en la lista de propiedad: no hay SQL, acceso al store, copia de base/WAL,
restauración ni migraciones en el instalador. Se mantienen los recursos
CompanyName/ProductName y el soporte Known Folder RoamingAppData T03.

## Adopción local inicial

No se enumeran instalaciones o credenciales. La persona elige un único
`myautofinance.exe` existente; la inspección T03 muestra versión, identificador
local, ruta origen y destino. No muestra cuentas ni secretos. Una casilla
expresa autoriza el traspaso entre esas rutas; volver atrás revoca la selección.
Sin casilla se conserva el origen y no hay transferencia. Una sesión destino
distinta, origen no verificable o conflicto bloquean la transferencia; se puede
volver y continuar sin seleccionarla si no hay recuperación pendiente.

Bajo la concesión se obtiene la `Confirmation` tipada de T03, ligada a nonce y
rutas exactas. Solo después de verificar el reemplazo se llama
`confirmAdoption`. T03 crea identidad propia de destino y verifica el commit
antes de limpiar exclusivamente el origen autorizado. Un diario pendiente no
se borra manualmente: repetir la instalación con las **mismas rutas** y
consentimiento permite la recuperación T03. No intentar otro origen para
eludir un conflicto. La conservación o el traspaso local no garantiza validez
permanente frente a caducidad o revocación externas.

## Fallos, cancelación y reparación

Antes de reemplazar, cancelar solo libera las concesiones. No modifica sesión
ni datos. Espacio insuficiente, permisos y archivos bloqueados impiden éxito;
liberar espacio/permisos en la raíz binaria propia, cerrar normalmente los
procesos y reintentar el mismo instalador o uno superior.

El recibo `.autofinance-pending` contiene solo versión e inventario binario
cerrado; se escribe con flush y rename antes del primer reemplazo. Incluye
las rutas retiradas de intentos anteriores para poder terminar su limpieza.
No contiene credenciales ni información financiera. Un recibo temporal
`.autofinance-pending-new` íntegro es recuperable si hubo interrupción antes
del rename. No se sustituyen recibos truncándolos en sitio.

Si Inno aborta antes de registrar la instalación, su rollback se combina con
la reposición de los archivos renombrados durante **esa misma operación**, bajo
exclusión. Si falla esa reposición o se interrumpe el proceso, se conservan
recibo y archivos recuperables. Una vez alcanzado `ssPostInstall`, ya cambió el
registro: un error posterior se presenta como **operación incompleta**, conserva
el recibo, impide apertura final y retorna código adicional **12**. No intenta
restaurar un binario anterior después de ese límite.

Después de interrupción/apagado, no abrir el payload parcial. Ejecutar el mismo
instalador o uno más reciente. El recibo permite reponer los archivos incluso
si falta el EXE o registro y PE discrepan por ese reemplazo. No permite bajar
de la versión que inició la operación. Si hay adopción pendiente, elegir
exactamente el mismo origen y autorizar su reanudación. No borrar recibos,
marcadores ni el área de recuperación para saltarse una barrera. Un manifiesto
inválido o identidad desconocida requieren diagnóstico antes de continuar.

No hay promesa de atomicidad total ante apagado. Tampoco rollback de esquema:
la app resuelve sus diarios EP-006 y migra mediante el store EP-004 al arrancar,
con las copias consistentes existentes. Una base de esquema futuro nunca se
fuerza, resetea ni restaura desde el instalador.

## Desinstalación

El desinstalador valida raíz/versiones/propiedad y adquiere exclusión **antes**
de retirar nada. Solo tras la confirmación normal de Inno, `usUninstall`
revalida cierre, guarda un recibo recuperable y llama a `cleanupOwnSession`.
Exige `cleared`: T03 borra/verifica credencial propia y después marcador propio,
sin revocación Google ni acceso a otro directorio. Solo entonces Inno retira
sus archivos registrados y accesos. No hay `[UninstallDelete]`, purga de
AppData ni limpieza recursiva; los archivos desconocidos se conservan.

Si la limpieza falla, se detiene antes de retirar archivos; puede haber
desconexión parcial y se indica que hay que verificarla. Si la retirada de
archivos falla después, se informa «desconexión local realizada; desinstalación
incompleta». El recibo se conserva para reparar con el mismo instalador o uno
superior y repetir la desinstalación. Esto también repone el host si Inno ya
retiró parte de sus archivos. Uninstall completo retira el recibo propio y solo
intenta eliminar directorios vacíos; conserva soporte, SQLite, sidecars,
copias, diarios y `drive-sync` completos. Reinstalar recupera los datos y exige
reconexión intencional con una identidad nueva.

## Verificación reproducible

```powershell
./scripts/check-windows-installer.ps1
./scripts/check-windows-maintenance.ps1
./scripts/check-quality.ps1
```

El primero prueba contratos Node, operaciones sobre archivos sintéticos con
handles reales y compila un EXE Inno con un falso payload deliberadamente no
ejecutable. Se conserva en `.tools/ma-tsk-232-inno-fixture-*`, nunca se ejecuta
ni distribuye. Puede usar `-Generator`/`-CMake` para **pruebas**, sin confundir
un compilador local diferente con producción fijada. El generador de producción
no admite sustituir el pin.

T08 debe probar, en usuarios/VM desechables Windows 10 y 11 x64: instalación
offline sin SDK/runtime global/UAC, actualización entre dos versiones PE reales,
misma versión, downgrade sin cambios, app abierta/borradores/nueva instancia,
DLL bloqueado, disco/permisos/cancelación, corte del proceso y reparación,
transferencia/recuperación con Credential Manager sintético y sesión
independiente, uninstall/reinstall con sentinelas financieras, y asistente
teclado/DPI/contraste/rutas con espacios y acentos. No instalar sobre el perfil
personal. Los tests de archivos y la compilación no sustituyen esa matriz.

Referencias primarias:
[DLL y flags de carga Inno](https://jrsoftware.org/ishelp/topic_scriptdll.htm),
[eventos de Setup/Uninstall](https://jrsoftware.org/ishelp/topic_scriptevents.htm)
y [arquitecturas admitidas](https://jrsoftware.org/ishelp/topic_setup_architecturesallowed.htm).
