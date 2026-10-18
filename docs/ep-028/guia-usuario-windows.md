# Autofinance para Windows: instalación y recuperación

Esta guía corresponde al instalador privado de Autofinance para Windows 10/11 x64. El EXE se instala para el usuario actual, funciona offline y no requiere SDK, Visual Studio, runtime C++ global ni permisos de administrador. La primera entrega no está firmada: el estado efectivo debe consultarse en el manifiesto de cada entrega. La aceptación del paquete de producción en Windows limpio (T08) sigue pendiente; consulta [verificación del instalador](verificacion-instalador.md) antes de tratar una entrega como validada.

## Obtener y comprobar una entrega

Obtén el instalador y su `manifest.json` únicamente por el canal privado autorizado por quien te entrega Autofinance. El repositorio público, sus Releases y los artefactos CI de prueba no son canales de distribución del instalador real. Mantén juntos el EXE, el manifiesto y los avisos/licencias incluidos.

En el manifiesto revisa `applicationVersion`, `architecture` (`x64`), `appEnvironment` (`production`), `installer.fileName`, tamaño y SHA256, además de `signing` y `verification`. Calcula el SHA256 localmente y compáralo con `installer.sha256` del manifiesto recibido por el mismo canal. En PowerShell:

```powershell
Get-FileHash -LiteralPath '.\Autofinance-Setup.exe' -Algorithm SHA256
```

El hash detecta cambios accidentales respecto del manifiesto; por sí solo no prueba quién creó el archivo ni que Windows confíe en él. La primera entrega prevista no tiene firma pagada, así que puede aparecer una advertencia de editor desconocido/SmartScreen. No desactives SmartScreen, antivirus ni otras protecciones para instalar. Si la firma indicada en el manifiesto no coincide con el estado que muestra Windows, o el hash/tamaño difiere, no ejecutes el archivo y solicita una copia correcta al canal autorizado.

No se necesita conexión a Internet para instalar. Drive solo se comunica cuando usas en la aplicación «Subir copia» o «Descargar última copia».

## Instalar por primera vez

1. Cierra Autofinance si está abierta. Ejecuta el EXE de la entrega verificada como el usuario de Windows que utilizará la aplicación; no elijas «Ejecutar como administrador».
2. Sigue el asistente en español. La instalación queda en `%LOCALAPPDATA%\Programs\Autofinance` y crea accesos por usuario. No admite elegir otra carpeta.
3. Si vienes de ejecutar un build o una instalación anterior desde otro directorio, decide si quieres transferir su sesión local de Drive. Para hacerlo, selecciona **el EXE exacto** de ese origen, revisa las rutas/identidad que presenta el asistente y marca la confirmación explícita de transferencia. El origen y destino deben pertenecer al mismo usuario y máquina y derivar la misma carpeta de soporte. La operación no escanea ni elige credenciales por ti.
4. Si no reconoces inequívocamente el origen, existe una sesión diferente en el destino o el asistente informa conflicto, vuelve atrás y no transfieras. Puedes instalar sin elegir origen: la sesión antigua queda en su sitio y Autofinance puede requerir que conectes Drive de nuevo. No copies archivos de Credential Manager, blobs secretos ni valores del Registro a mano. No elijas otro origen para sortear una recuperación pendiente.
5. Termina el asistente. La aplicación no sube ni descarga copias al abrirse; esas acciones son manuales.

La adopción es un traspaso local explícito y solo para las rutas elegidas. No comparte automáticamente una sesión entre directorios independientes ni garantiza que Google mantenga válida una credencial caducada o revocada.

## Actualizar o reparar

Para actualizar, obtén y comprueba una entrega nueva por el mismo canal, cierra Autofinance normalmente y ejecuta su EXE. Resuelve cualquier trabajo pendiente en la aplicación antes de cerrarla. Si Setup indica que la app sigue abierta, ciérrala tú y reintenta o cancela; no fuerces su cierre.

La versión se compara numéricamente (mayor, menor, parche y build), no por el número de esquema de la base. Una versión superior actualiza; la misma versión registrada repara archivos propios; una inferior se bloquea antes de escribir. No instales un binario antiguo para volver atrás: podría encontrarse con un esquema de base de datos más nuevo. Una reparación repone binarios, no revierte datos ni esquemas.

Actualizar o reparar conserva la carpeta de datos, las copias locales, diarios, estado de sincronización y la identidad/credencial Drive existente; no ejecuta la limpieza de desinstalación. Una sesión preservada puede necesitar reconexión si dejó de ser válida externamente. El instalador no migra la base: las migraciones y sus respaldos pertenecen a EP-004, y la recuperación de copias/diarios a EP-006.

Si una operación se interrumpe, no abras un payload parcial ni borres marcadores/archivos de recuperación. Ejecuta el mismo instalador o uno más reciente con las mismas rutas; si había una adopción en curso, selecciona de nuevo exactamente el mismo origen y autoriza la reanudación. Atiende el diagnóstico si la identidad o el manifiesto no se pueden verificar.

## Ubicaciones y conservación

Los binarios y accesos están separados de los datos:

| Contenido | Ubicación o dueño |
| --- | --- |
| Aplicación y desinstalador | `%LOCALAPPDATA%\Programs\Autofinance` |
| Soporte/datos de la app | Known Folder `RoamingAppData` + `com.carlosmg91\Autofinance`; normalmente `%APPDATA%\com.carlosmg91\Autofinance` |
| Base activa y posibles `-wal`, `-shm`, `-journal` | `…\sqlite\autofinance.sqlite` y sus sidecars; EP-004 |
| Fotos consistentes, respaldo anterior a migración | `…\sqlite\copies\snapshot-*\` y `…\sqlite\autofinance.sqlite.pre-v…`; EP-004 |
| Copias y recuperación local | `…\sqlite\local-backups\` (incluidos staging, tombstones, restore y diagnostics); EP-006 |
| Estado de sincronización Drive | `…\drive-sync\state.json` y auxiliares del servicio |
| Credencial Drive | Credential Manager de Windows, bajo la identidad local de instalación |

`%APPDATA%` puede estar redirigido por el perfil. La ruta real se deriva de la Known Folder de Windows y del nombre de compañía/producto del ejecutable; no asumas que empieza por `C:\Users` ni cambies la identidad para encontrar datos. El número de esquema SQLite es independiente de la versión visible de la aplicación. El instalador no abre, mueve, copia ni borra la base, WAL, copias, diarios o estado Drive.

## Fallo de arranque, migración o recuperación de datos

No borres ni renombres la base para que la app cree otra vacía, y no copies la base activa mientras Autofinance está abierta. Tampoco copies SQLite junto con `-wal`/`-shm` como método de downgrade: esos archivos pueden formar una unidad activa y no revierten un esquema futuro.

Ante un fallo, conserva los archivos y el mensaje de diagnóstico. La aplicación puede bloquearse si detecta identidad de soporte incorrecta o recuperación pendiente; no busques una base con rutas alternativas ni fuerces su apertura. Para una migración interrumpida o dañada, sigue el flujo y los respaldos consistentes existentes de EP-004; para una copia/restauración local interrumpida, sigue el procedimiento de EP-006. Usa sus mecanismos de recuperación desde la aplicación/servicio propietario. Si no puedes abrir la app o el flujo no reconoce un respaldo, conserva intactos el perfil y los diarios y solicita soporte con el texto del error; no envíes una base financiera por canales públicos.

La exportación EP-027 puede servir como opción adicional cuando se entregue y la aplicación la ofrezca. No es requisito de instalación/actualización ni sustituye los respaldos y recuperación de EP-004/006.

## Desinstalar y volver a instalar

Desinstala desde Configuración de Windows o el acceso de desinstalación de Autofinance, como el mismo usuario. Confirma la acción en el desinstalador. Se elimina localmente la credencial Drive propia y su marcador de identidad; esto desconecta Autofinance en ese perfil. **No revoca la autorización en Google.** La desinstalación conserva deliberadamente el soporte, base, copias, diarios y estado Drive. No es una purga financiera ni borra automáticamente tus datos.

Al reinstalar, se mantienen los datos locales y podrás continuar con ellos si la identidad de soporte coincide. La identidad nueva no hereda la sesión eliminada: conecta Drive de nuevo de forma intencional. Las sesiones de otras instalaciones/directorios no se modifican. Si el desinstalador informa que la desconexión ocurrió pero la retirada de archivos quedó incompleta, considérate desconectado localmente y consulta soporte antes de reintentar.

## Límites de esta guía

La matriz T08 debe comprobar el paquete real en Windows 10/11 x64 con perfiles desechables, incluida una ruta con espacios y acentos, y nunca con una cuenta/credencial personal. La compilación de fixtures o CI no demuestra por sí sola esa aceptación. No se ofrece autoactualizador, Store/MSIX, ARM64, x86 ni purga de datos. Para comandos de generación local, que no son pasos para una persona usuaria final, consulta [generación privada](generacion-privada.md).
