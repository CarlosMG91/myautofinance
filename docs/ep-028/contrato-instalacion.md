# Contrato de instalación Windows · v1

MA-TSK-228 / MA-EPIC-227 · 2026-10-17. Fuente operativa de identidad:
[installation-contract.json](../../packaging/windows/installation-contract.json).
Contrato para T02–T08; este ticket no entrega instalador, asistente ni servicios
nativos implementados. La aprobación visual de T04 es independiente de este
contrato y se exige antes de implementar T05.

## Identidad y destino inmutables

| Campo | Valor fijado |
| --- | --- |
| Producto / plataforma | Autofinance; Windows 10/11 x64, usuario estándar |
| Formato / alcance | EXE Inno Setup por usuario (`PrivilegesRequired=lowest`), offline |
| AppId lógico | `{82D31B27-9717-4DB7-AB32-D098BF3C2859}` |
| Expresión en `.iss` | `AppId={{82D31B27-9717-4DB7-AB32-D098BF3C2859}` (escape de la llave inicial) |
| Destino | `%LOCALAPPDATA%\Programs\Autofinance`; Inno `{localappdata}\Programs\Autofinance` |
| Ejecutable / CMake | `myautofinance.exe` / `BINARY_NAME=myautofinance` |
| Recursos VERSIONINFO | `CompanyName=com.carlosmg91`, `ProductName=Autofinance`, `InternalName=myautofinance`, `OriginalFilename=myautofinance.exe` |
| Otros recursos existentes | FileDescription Autofinance, icono `windows/runner/resources/app_icon.ico`; identidad visual EP-026 |

El AppId es una identidad de paquete nueva y fija, **no** el GUID de sesión
Drive, el `application_id` SQLite, el `datasetId` ni el cliente OAuth. No contiene
versión, arquitectura variable, commit ni perfil. Inno usa el mismo AppId para
continuar el registro de desinstalación; no se ejecuta un desinstalador antiguo
como paso de actualización. Solo HKCU, accesos propios y raíz binaria propia;
sin HKLM, instalación global, servicios, autoarranque ni tareas programadas.

No ofrecer directorios por versión ni selector de otro destino. N→N+1 y
reparación mantienen exactamente la ruta registrada. Si el registro previo
contradice el destino/identidad esperados, detenerse y diagnosticar; no crear
automáticamente una segunda instalación ni adoptar una carpeta arbitraria.
No se trasladan datos al EXE. El runtime C++ se distribuye app-local desde
redistribuibles oficiales autorizados (T02); el destino no necesita SDK,
Visual Studio, Node, instalación global del runtime, administrador ni red.
T02 fija versión/procedencia verificable de Inno y del runtime sin alterar la
toolchain/lockfile existentes. No se añaden certificados ni se cambian las
protecciones de Windows.
Quedan fuera Store/MSIX, ARM64, x86, autoactualizador, purga financiera,
configuración global y adquisición de certificados.

## Versiones, reparación y trazabilidad

`pubspec.yaml` es la única fuente de versión de aplicación: actualmente
`0.1.0+1`. Se admite `major.minor.patch+build`, sin prerelease ni sufijos; los
cuatro componentes son enteros 0..65535 y build es positivo. Las herramientas
de paquete deben rechazar entradas distintas, sin truncar ni sustituir valores.
No sobrescribir versión mediante flags de build ajenos al manifiesto.

| Uso | Ejemplo actual |
| --- | --- |
| Versión app / AppVersion / recursos string | `0.1.0+1` |
| FILEVERSION / PRODUCTVERSION / comparación | `0.1.0.1` |
| Commit | SHA Git completo de 40 hex del origen compilado |

Comparar numéricamente la tupla `(major, minor, patch, build)` con la instalación
registrada y el PE existente; nunca comparar cadenas ni usar el número de
esquema SQLite. Ejemplos: `0.1.0+2` actualiza `0.1.0+1`; `0.2.0+1` actualiza
`0.1.0+9`; igualdad repara; `0.1.0+1` frente a `0.1.0+2` se rechaza **antes de
escribir**. Falta de versión verificable o discordancia registro/PE bloquea la
operación hasta diagnóstico. Igualdad significa reparación incluso si cambian
bytes/commit; una entrega nueva debe incrementar versión/build.

La actualización es manual ejecutando el nuevo instalador. No hay actualizador
residente, consulta periódica de red ni descarga/ejecución de EXE al abrir la app.
Instalar y reparar reemplazan solo payload y metadatos propios; conservan GUID,
credencial, datos y estado de sincronización. Nunca llaman a limpieza de sesión.

## Ruta de soporte y propiedad de los datos

Se ha inspeccionado **path_provider_windows 2.3.0**, fijado en `pubspec.lock`:
`getApplicationSupportPath()` llama a
`_createApplicationSubdirectory(WindowsKnownFolder.RoamingAppData)` y deriva la
subcarpeta del VERSIONINFO **del ejecutable en ejecución**, con
`CompanyName\ProductName`. Consulta `SHGetKnownFolderPath`; si falta compañía
la omite y si falta producto usa el nombre del EXE. Estos fallbacks no son una
migración aceptable: T02/T03 deben detectar metadata ausente o alterada.

Con los recursos actuales, soporte efectivo `S` =
`SHGetKnownFolderPath(RoamingAppData)\com.carlosmg91\Autofinance`, normalmente
`%APPDATA%\com.carlosmg91\Autofinance`. **No es LocalAppData**. Respetar Known
Folder, incluso con perfiles redirigidos, espacios o acentos; no codificar
`C:\Users`, el nombre del usuario ni asumir que `%APPDATA%` no está redirigido.
Conservar metadata mantiene S aunque cambie el directorio del EXE.

| Artefacto existente | Ubicación / propietario | Política de instalador y uninstall |
| --- | --- | --- |
| Base activa y sidecars | `S\sqlite\autofinance.sqlite`, `-wal`, `-shm`, `-journal`; EP-004 | Conservar; no abrir, copiar, mover ni borrar |
| Fotos consistentes internas | `S\sqlite\copies\snapshot-*\autofinance.sqlite`; store EP-004 | Conservar |
| Respaldo previo de migración | `S\sqlite\autofinance.sqlite.pre-v<schema>-<uuid>.sqlite`; EP-004 | Conservar |
| Copias locales y metadatos | `S\sqlite\local-backups\{backups,staging,tombstones}`, `catalog-a.json`, `catalog-b.json`; EP-006 | Conservar completos, incluidos incompletos/protegidos |
| Restauraciones y diarios | `S\sqlite\local-backups\restore\<operationId>`, `diagnostics`, bloqueos/archivos auxiliares; EP-006 | Conservar; recuperación solo por servicios existentes |
| Estado Drive sin tokens | `S\drive-sync\state.json`, temporales/bloqueo del servicio; synchronization | Conservar baseline, operaciones pendientes y contraste, sin reinterpretarlos |
| Credencial segura | Credential Manager del usuario/máquina, `CRED_TYPE_GENERIC`, `CRED_PERSIST_LOCAL_MACHINE`, target `Autofinance/Drive/<GUID>` | Update/repair conservan; uninstall solo target propio |
| Marcador de sesión | `HKCU\Software\CarlosMG91\Autofinance\Installations\<hash>`, valor `Id` REG_SZ GUID | Update/repair conservan; uninstall solo marcador propio |
| Binarios / desinstalador / accesos | Destino estable, registro Inno HKCU, Inicio y escritorio opcional | Administrados por T05, sin comodines fuera de su inventario |

Inventario obtenido de código/contratos, sin enumerar AppData, registro ni
CredManager personales. El dato financiero y los tokens no forman parte del
payload ni del manifiesto de entrega. No usar el catálogo de copias para
almacenar credenciales. El instalador no limpia temporales, diarios, archivos
desconocidos ni el soporte completo al cancelar/desinstalar.

T03 debe comprobar con el runner la igualdad de S antes/después en perfil
desechable **antes de abrir el store**. Si difiere, bloquear y explicar el fallo
de identidad; no buscar otra base por heurísticas ni abrir una base vacía en la
nueva ruta. La comprobación estática/PE de este ticket se describe en
[verificacion-contrato.md](verificacion-contrato.md), diferenciada de ese E2E.

## Identidad de Drive y adopción explícita inicial (T03)

`WindowsDriveChannel::InstallationKey()` toma el directorio devuelto por
`GetModuleFileNameW`, quita el nombre de archivo, aplica `CharLowerBuffW` y
calcula SHA-256 sobre sus bytes UTF-16 sin terminador, en hexadecimal minúscula.
`EnsureTarget()` serializa creación mediante
`Local\AutofinanceDrive-<hash>` y obtiene/crea el GUID del marcador para derivar
el target. No cambiar esa derivación incidentalmente ni sustituirla por un
target global. No asumir equivalencia de alias, junctions o rutas distintas.
El mutex actual protege la creación de identidad, **no** todo el mantenimiento
ni el acceso SQLite.

N→N+1 conserva carpeta, hash, marcador, GUID y target; una sesión todavía válida
no requiere consentimiento nuevo por instalar un paquete. Caducidad/revocación
externa usa el flujo EP-005; no se promete sesión eterna. Mover/copiar solo
el EXE a otro directorio sigue sin copiar sesión.

Primera adopción desde un build/directorio anterior: selección explícita de un
único EXE/ruta de origen validado, mismo usuario Windows y máquina, más
confirmación tipada de transferencia local vinculada a origen y destino
exactos. No escanear credenciales globales, elegir al azar entre candidatos,
inventar origen, compartir un GUID entre directorios ni sobrescribir una sesión
destino diferente. Sin autorización se puede instalar desconectado conservando
el origen; no presentar la sesión como transferida.

T03 es dueño de la transacción de adopción: preparar sin cambiar origen,
reservar destino, leer/escribir secretos solo en memoria y Credential Manager,
verificar destino y confirmar el traspaso antes de retirar exclusivamente la
sesión de origen autorizada. El destino mantiene identidad propia; no se copia
el marcador GUID para que dos directorios compartan target. Fallo antes de
confirmar conserva origen y estado previo de destino; interrupción requiere
reconciliación idempotente y fallo cerrado ante conflicto, sin retirar origen
por mera existencia de destino. Si se interrumpe después de confirmar, un
reintento termina la limpieza autorizada sin nueva transferencia a otro origen.
No generar ni modificar un GUID al inspeccionar una instalación ausente.

Los detalles de durabilidad/protocolo nativo los implementa T03 según estos
invariantes. Cualquier diario de adopción contiene solo identificadores/fase,
nunca tokens, blobs, cuentas ni respuestas OAuth. No transportar secretos por
archivo, SQLite, argumentos, variables de entorno, stdout, stderr o logs.

## Puertos y secuencia de coordinación

Contrato semántico v1 para T03/T05, no comandos ya disponibles. T03 entrega
adaptadores nativos/servicios sin UI; T05 los invoca y presenta el asistente
aprobado. Los nombres siguientes identifican operaciones, no autorizan ejecutar
flags inexistentes ni fuerzan el mecanismo IPC. El canal debe autenticar usuario
y operación local, validar rutas/identidades, y no exponer secretos.

| Puerto | Entrada / salida permitida | Garantía requerida |
| --- | --- | --- |
| `inspectInstallation` | Ruta EXE exacta; versión, soporte, presencia/validez de identidad, estado sin cuentas/tokens | Solo lectura; no `EnsureTarget()` creador, no apertura de base ni red |
| `prepareMaintenance` | `install/update/repair/uninstall`, versión destino y rutas; permiso opaco de operación o `appInUse/cancelled/blocked` | Exclusión de mantenimiento; validar identidad/versión/soporte; ninguna limpieza ni migración |
| `requestClose` | Operación vigente; `closed/refused/cancelled/busy` | Cierre cooperativo, resolver borradores por decisión de usuario; esperar fin de operaciones, `LocalDatabaseStore.close()` y salida efectiva |
| `prepareAdoption` / `confirmAdoption` | Origen exacto, destino exacto, confirmación tipada vinculada a ambos y operación vigente; `ready/committed/conflict/cancelled/failed` | Revalidación bajo exclusión; transacción local descrita arriba, sin exponer credencial |
| `cleanupOwnSession` | Solo uninstall explícito + operación vigente + identidad destino; `cleared/failed` | Borrar/verificar target propio y después marcador propio; idempotencia; sin revocación remota ni finanzas |
| `finishMaintenance` / `abortMaintenance` | Operación vigente; resultado verificable | Liberar exclusión aun al cancelar; no anunciar éxito si falta fase/queda limpieza pendiente |
| Apertura/migración | Arranque normal posterior; `LocalDatabaseStore.open()` | Store existente EP-004/006; no puerto SQL del instalador |

La exclusión cubre todas las instancias de la carpeta destino y, para adopción,
también origen, con orden de bloqueo determinista. Mantenerla desde preparación
hasta reemplazo/limpieza final; una nueva instancia durante ese intervalo no
abre base ni usa binarios que se reemplazan. Revalidar procesos/archivos en uso
justo antes de reemplazar. Si no se puede garantizar exclusión, detenerse.
No usar `taskkill`, cierre forzado ni confiar solo en detectar una ventana.
Inno `CloseApplications=force` queda prohibido; evitar su cierre automático en
modo silencioso (`CloseApplications=no` y coordinación explícita T03/T05).
No relanzar automáticamente app (`RestartApplications=no`); arranque final solo
por elección, sin Drive automático. Modo silencioso no elude ninguna barrera.

Cancelar antes del reemplazo no modifica payload/sesiones/datos. Cierre rechazado
o app ocupada permite cerrar/reintentar/cancelar. Fallo de espacio, permisos o
archivo bloqueado no se anuncia como instalado; mantener estados financieros y
credenciales, liberar exclusión y ofrecer reintento/reparación. Interrupción
durante reemplazo puede dejar payload parcial: no se promete atomicidad ante
apagado; reparar con misma versión o superior tras volver a validar. Si queda
reinicio pendiente, distinguirlo de éxito operativo y no iniciar app aún.

Al arrancar, EP-006 resuelve diarios antes de abrir y EP-004 valida formato y
esquema. `LocalDatabaseStore.open()` respalda con snapshot consistente cuando
migra y rechaza esquema futuro/incompatible; nunca resetea una base por fallo.
Solo el store migra; instalador no ejecuta SQL, no copia una base viva ni sus
WAL, no baja esquema, ni restaura un binario antiguo como rollback. Recuperación
financiera usa [EP-004](../ep-004/persistencia-local.md) y
[EP-006](../ep-006/restauracion-segura.md). Una reparación de archivos no revierte
esquema ni sustituye datos.

## Desinstalación y reinstalación

Uninstall exige cierre/exclusión y llama a `cleanupOwnSession` antes de retirar
el componente que lo implementa. Comprobar identidad sin crear marcador si no
existía; no reutilizar a ciegas el `clear` actual (elimina credencial, pero no
marcador). Con credencial borrada/verificada, retirar solo el marcador de esa
carpeta y verificar ausencia. Si falla una fase, conservar lo necesario para
reintentar y comunicar limpieza pendiente; no borrar otro target ni reportar
desconexión completada. Tras completar uninstall, reinstalar crea identidad
nueva y exige reconexión intencional, conservando S y toda la información
financiera/estado histórico. Este último no acredita sesión válida por sí solo.

No llamar a revocación Google ni tocar otras instalaciones/cuentas/perfiles.
No borrar `drive-sync`, SQLite, copias, diarios ni ofrecer purga financiera.
Update/repair no llama a este puerto ni ejecuta uninstall previo. Cancelar
uninstall antes de confirmar limpieza conserva sesión; después de limpiar,
un fallo en eliminación de archivos se comunica como desconexión ya realizada
con desinstalación incompleta, sin restaurar secretos desde un archivo.

## Salida privada y manifiesto de entrega (T02/T06)

El repositorio `CarlosMG91/myautofinance` es público según la evidencia de la
épica. Generar producción solo localmente en `dist-private/windows/` (ignorado
por Git), para transferencia manual privada. No Releases, artefactos públicos,
Pages, hosting nuevo ni cambios de visibilidad. CI puede comprobar empaquetado
con fixtures sintéticos/perfil desechable e informes sanitizados; nunca publicar
el instalador/payload de producción. No confundir artefactos de builds de prueba
de EP-003 con autorización para publicar esta entrega.

El manifiesto JSON UTF-8 `manifest.json`, contrato `manifestVersion=1`, acompaña
el EXE y las licencias; no se incrusta un hash del propio manifiesto ni del EXE
en sí mismo. Campos obligatorios:

| Campo | Contenido |
| --- | --- |
| `manifestVersion`, `installationContractVersion`, `appId` | `1`, `1`, AppId fijo |
| `applicationVersion`, `windowsVersion`, `architecture`, `appEnvironment` | pubspec con build, tupla PE, `x64`, `production` |
| `sourceCommit`, `sourceDirty`, `builtAtUtc` | SHA completo, `false` para entrega verificada, instante UTC ISO-8601 |
| `toolchain` | Versiones efectivas Flutter/Dart/Windows SDK/MSVC/Inno; hash SHA256 de `toolchain.json` y `pubspec.lock` |
| `installer` | Nombre relativo, tamaño en bytes, SHA256 de 64 hex del EXE final |
| `payload` | Lista cerrada de rutas relativas/tamaños/SHA256 de todos los archivos instalables, incluyendo data, DLL, plugins/native assets y SQLite |
| `runtime` | Versión, origen oficial y hashes/procedencia de redistribuibles C++ app-local autorizados |
| `licenses` | Rutas relativas/tamaños/SHA256 y componente correspondiente; avisos Flutter/terceros/runtime conforme a distribución |
| `signing` | Estado observado del instalador y binarios; primera entrega prevista `unsigned`, sin inventar editor ni certificado |
| `verification` | Comprobaciones realizadas y límites pendientes, origen del payload, versión Windows del ensayo; sin rutas/perfiles personales |

Rutas relativas dentro del paquete, sin `..` ni absolutos; hashes calculados
después de generar el archivo final. La lista no incluye bases/fixtures, SDK,
caches, logs personales, tokens ni certificados privados. T02 cierra inventario
y licencias; T06 implementa generación/validación y rechaza incoherencias,
checkout sucio o checks fallidos antes de etiquetar una entrega como verificada.
Este manifiesto describe trazabilidad/integridad; no exige identidad binaria
reproducible entre compiladores, fechas o máquinas.

Sin firma pagada en primera entrega. Registrar el estado real y SHA256 para
detectar cambios accidentales; **el hash no acredita autoría ni confianza de
Windows/SmartScreen**. No prometer editor verificado, instalar certificados de
confianza, desactivar SmartScreen/antivirus ni eludir advertencias.

## Cruces y comprobaciones de aceptación

EP-007/019/021/022/023 constan entregados en la épica. EP-020 no existe como
dependencia independiente: su función de patrimonio corresponde a EP-009/017 y
EP-026 MA-TSK-212; no inventar ticket bloqueante. EP-027 es opcional y EP-025
bloqueada no impide instalar. No modificar esas épicas ni sus motores.

T01/T02/T04 son independientes. T03/T07 consumen este contrato; T05 necesita
T02/T03 y aprobación explícita T04; T06 sigue a T05; T08 prueba paquete final
tras T06/T07. Son cruces narrativos, no ejecución automática de Epic Board.

T08 debe verificar en Windows limpio/perfil desechable y datos sintéticos:
offline sin SDK/admin/runtime global; ruta con espacios/acentos; N→N+1 y misma
versión conservan S, GUID, sesión válida, datos/copias/diarios/estado; downgrade
no escribe; cierre rechazado/nueva instancia/cancelación/reintento; adopción
consentida/origen ambiguo/destino ocupado/interrupciones; migración fallida y
recuperación EP-004/006; uninstall solo limpia identidad propia y reinstalación
reconecta conservando datos. Nunca instalar ni ensayar credenciales sobre el
perfil personal. No inferir estos resultados desde tests estáticos o el mockup.

Referencias oficiales consultadas 2026-10-17:
[AppId](https://jrsoftware.org/ishelp/topic_setup_appid.htm),
[AppVersion](https://jrsoftware.org/ishelp/topic_setup_appversion.htm),
[CloseApplications](https://jrsoftware.org/ishelp/topic_setup_closeapplications.htm).
Código de referencia path_provider: paquete 2.3.0 resuelto localmente,
`lib/src/path_provider_windows_real.dart`, métodos citados arriba.
