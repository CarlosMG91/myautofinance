# MA-TSK-230 · Servicios locales de mantenimiento y sesión

Contrato consumido: [MA-TSK-228](contrato-instalacion.md). No hay interfaz,
instalador, OAuth nuevo ni motor de migración. La aceptación nativa en usuario
desechable y el E2E del paquete siguen pendientes; consultar
[verificación](verificacion-sesion.md).

## Entrada para T05

`windows/maintenance/session_maintenance.h` expone tipos C++17 sin Flutter.
`WindowsSessionStore` implementa `Store` exclusivamente con Known Folders,
HKCU y Credential Manager del usuario del proceso. El target sigue siendo
`Autofinance/Drive/<GUID>` con persistencia `CRED_PERSIST_LOCAL_MACHINE`.
La derivación SHA256 del directorio en UTF-16 y `CharLowerBuffW` coincide con
`WindowsDriveChannel`; este canal y OAuth permanecen intactos.

El target CMake **estático** `autofinance_maintenance` se puede enlazar en el
host nativo privado del instalador. No es una DLL exportada ni un comando del
runner. T05 debe alojar el objeto en su adaptador nativo para Inno y conservarlo
durante toda la operación. Ese adaptador/ABI y su empaquetado pertenecen a T05.
No lanzar `myautofinance.exe` como host de mantenimiento: cuenta como app en uso.
El host se ejecuta sin elevación, como el mismo usuario interactivo; no es un
servicio, servidor IPC ni ejecutor de órdenes de otros usuarios. Las operaciones
son llamadas dentro del proceso: la capacidad opaca nunca se persiste ni se
acepta desde un cliente remoto. No hay transporte de secretos hacia Inno.

Mantener un `WindowsSessionStore` vivo y un `SessionMaintenance(store)` por
operación, en el mismo hilo. `Store` es el puerto para pruebas, no una invitación
a reemplazar Credential Manager por archivos en producción.

| Operación | Uso y resultado |
| --- | --- |
| `inspectInstallation(exe, out)` | EXE único absoluto existente. Devuelve versión numérica, soporte, GUID opcional, presencia de credencial y recuperación pendiente. Solo lectura: no crea GUID, no abre datos, no comprueba Google. |
| `prepareMaintenance(action, destination, incomingVersion, expectedSupport, source, stagedExe)` | Valida rutas/recursos/versión/soporte y retiene exclusión. `source` es opcional y exclusivo de instalación inicial. `stagedExe` valida el candidato y permite que `destination` aún no exista. Retorna `ready`, `busy`, `blocked`, `conflict` o `failed`. |
| `requestClose()` | Comprobación cooperativa bajo la operación vigente: `closed` si no queda proceso, `busy` si lo hay. Nunca envía cierre forzado ni decide sobre borradores. |
| `prepareAdoption(out)` | Revalida origen/destino; entrega una `Confirmation` con el tipo `Consent::transferLocalDriveSession`, nonce de operación y ambos EXE exactos. No modifica credenciales ni marcadores. |
| `confirmAdoption(confirmation)` | Solo tras elección explícita del usuario en T05. Rechaza nonce/rutas/tipo distintos; revalida y devuelve `committed` únicamente al terminar y verificar todo el traspaso. |
| `cleanupOwnSession()` | Solo operación `uninstall`, sin adopción pendiente: borra y verifica credencial propia, después retira y verifica Id propio. `cleared` es idempotente. No crea identidad ausente. |
| `finishMaintenance()` | Comprobar antes el resultado del reemplazo en T05. Solo retira el recibo committed si esta operación confirmó su limpieza; rechaza otros diarios pendientes o uninstall sin limpieza, comprueba ausencia de procesos y libera exclusión. No certifica por sí solo el payload ni la instalación. |
| `abortMaintenance()` / destructor | Libera siempre exclusión. Abort revierte una reserva anterior al commit si es inequívoca. Un commit con limpieza pendiente devuelve `blocked`. Tras empezar cleanup, devuelve `cleared` si desconectó o `blocked` si quedó parcial; no anuncia cancelación sin cambios. El destructor solo libera; deja diario recuperable. |

`incomingVersion` contiene cuatro enteros 0..65535 y build positivo. Update
exige versión mayor, repair igualdad; un downgrade se bloquea antes de modificar
sesiones. Para uninstall se pasa la versión instalada. `expectedSupport` debe
ser el soporte conocido del contrato; el host puede obtenerlo mediante
`SupportDirectory()`, contrastándolo con la inspección del origen/candidato.
T05 sigue siendo dueño de AppId, destino estable registrado, versión del paquete,
inventario, licencias, cancelación del asistente y reemplazo de archivos.

## Coordinación de procesos y archivos

El runner adquiere una concesión compartida **antes** de COM, Flutter, plugins
y `LocalDatabaseStore.open()`. Verifica x64 y VERSIONINFO conservando exactamente
CompanyName/ProductName; deriva soporte mediante `FOLDERID_RoamingAppData`.
Un fallo muestra `INSTALL-001` sin abrir la base ni buscar una alternativa.
Un diario pendiente bloquea el arranque; no se crea una base vacía para eludirlo.

Mantenimiento obtiene concesiones exclusivas por hashes en orden determinista.
Son handles de archivos separados de datos en
`LocalAppData\com.carlosmg91\Autofinance\maintenance\<hash>.lock`, con share modes
incompatibles con los del runner. Operan entre sesiones de login del mismo
usuario y se liberan al morir el proceso; los archivos inertes pueden quedar.
No se borran en uninstall ni contienen credenciales. No se enumeran bases,
marcadores ni credenciales.

También se retienen handles de los EXE existentes sin compartir lectura ni
escritura para impedir arrancar runners antiguos sin la concesión nueva. El
origen tampoco comparte borrado. El destino comparte **solo borrado**: T05 debe
**renombrar el binario anterior antes de colocar el nuevo**, conservando la
concesión hasta finalizar; no sobrescribir directamente el EXE retenido ni
posponerlo para reinicio como si fuese éxito. La inspección bajo concesión usa
metadata del archivo retenido y comprueba su file ID; si destino fue sustituido,
inspecciona el PE nuevo. El reemplazo completo y sus errores son de T05.

Se consulta además la lista de procesos para detectar runners anteriores por
ruta exacta. Un proceso coincidente que no se puede inspeccionar da `busy`.
No basta una ventana y no se mata ningún proceso. Si `prepareMaintenance`
devuelve `busy`, no existe operación autorizada: T05 permite al usuario cerrar
normalmente la app y reintentar preparación, o cancelar. Antes de reemplazar,
T05 vuelve a llamar `requestClose()` y exige `closed`. El cierre manual permite
resolver borradores por los mecanismos existentes; no se finge un cierre
automático del store ni se envía un WM_CLOSE ciego.

Rutas relativas, listas de candidatos, UNC, ADS, segmentos `.`/`..`, puntos o
espacios finales, enlaces duros, junctions, symlinks y alias de ruta se rechazan;
no se normalizan para adoptar otra instalación. Los EXE deben tener menos de
260 caracteres: path_provider_windows 2.3.0 usa un buffer MAX_PATH para obtener
el módulo; se bloquea antes de que su truncamiento/fallback cambie el soporte.
No se pretende aislar secretos
frente a un programa malicioso que ya actúa como el mismo usuario Windows.

## Adopción y recuperación

1. Inspeccionar el **EXE exacto elegido**; origen y destino deben ser distintos
   y derivar el mismo soporte. Sin selección/consentimiento se instala
   desconectado y se conserva íntegramente la sesión anterior.
2. Preparar mantenimiento con ambos EXE y candidato. Origen necesita Id válido
   y credencial local; destino puede no tener Id o tener Id propio sin sesión.
   Una sesión destino existente produce conflicto aunque el contenido coincida.
3. Mostrar en T05 las rutas elegidas y solicitar la transferencia. Solo la
   confirmación tipada de esa preparación permite ejecutar `confirmAdoption`.
4. Guardar `AdoptionV1` en el marcador destino: versión de protocolo, fase,
   hashes de ambos directorios, GUID de origen y GUID propio reservado de destino,
   y si este último existía. Es un único valor binario inicializado, escrito con
   `RegSetValueExW` y durabilizado con `RegFlushKey`. Un enlace inverso
   `AdoptionDestinationV1` en origen bloquea también su nuevo runner durante la
   recuperación. Ninguno contiene tokens, cuentas, blobs ni respuestas OAuth.
5. Leer secreto en memoria, escribir nuevo target local, releer y comparar todos
   los bytes, guardar Id destino y persistir fase committed. **Después** borrar
   y verificar target origen y retirar Id origen. El recibo committed y su enlace
   permanecen hasta `finishMaintenance` para recuperar una respuesta perdida a
   la confirmación; este último vuelve a verificar y los elimina.
   Los buffers de secretos se ponen a cero al destruirse; nada viaja por
   SQL, archivo, variables, argumentos, stdout, stderr o logs.

Un error anterior al commit revierte solo la reserva propia y conserva el
origen. Si no se puede demostrar que el secreto reservado coincide con el
origen, conserva ambos y devuelve conflicto. Esto protege una sesión cambiada
por un runner antiguo después de interrumpirse el host. Un error de flush
relee la fase durable; no supone que la escritura fallida no ocurrió.

Para recuperar, preparar de nuevo **las mismas rutas**, volver a obtener y
confirmar el tipo de transferencia. Un diario prepared se revierte antes de
reintentar; uno committed verifica destino y termina exclusivamente la limpieza
autorizada. Fuente ya borrada es un reintento válido. GUID/secretos distintos
producen conflicto sin borrados. Una recuperación no elige otro origen ni
infiere commit por la mera existencia de credencial en destino.

Update/repair/uninstall se bloquean si tienen una adopción pendiente. T05 no
debe presentar `failed`, `conflict` o `blocked` como éxito ni borrar el diario
manualmente. Si se interrumpió antes del enlace inverso, aún no se había escrito
el secreto destino: el origen sigue intacto. Runners antiguos no conocen el
diario una vez muerto el host; cualquier cambio posterior se contrasta y falla
cerrado al reintentar. No se prometen sesiones permanentes ante revocación o
caducidad externas: se conserva el flujo EP-005 existente.

## Datos, reparación y desinstalación

Las operaciones no reciben un puerto SQLite ni un catálogo de copias. No abren,
copian, desplazan o eliminan soporte, WAL, respaldos, diarios o `drive-sync`.
Su igualdad de ruta se comprueba antes de abrir el store; la migración y sus
respaldos siguen en EP-004/006. El instalador no migra ni baja esquemas.

Update/repair preservan Id/GUID/target: no llaman a cleanup ni al uninstall
anterior. Uninstall requiere `cleanupOwnSession` antes de retirar su host:
sin revocación Google, sin purga financiera y sin eliminar otras claves ni
targets. Tras verificar ausencia de credencial se elimina Id; solo se elimina
la clave si no contiene valores/subclaves. Si falla, conserva identidad para
reintentar. Si los archivos no se pudieron retirar tras limpiar la sesión,
T05 informa desinstalación incompleta y desconexión ya realizada. Reinstalar
genera otra identidad mediante el canal existente y requiere reconectar, aunque
los datos y el historial de sincronización permanezcan.

Referencias de implementación:
[CreateFile y modos de compartición](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew),
[RegFlushKey](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regflushkey),
[Credential Manager](https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credwritew).
