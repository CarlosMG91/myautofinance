# MA-TSK-043 · Sesión, cuenta y contrato de acceso a Drive

## Entrega y límites

La entrada pública `lib/features/synchronization/synchronization.dart` exporta
`DriveAccess`, `DriveAccessSession`, `DriveSessionProvider` y sus metadatos.
Son Dart común para Windows y Android, sin Flutter, SQLite, SDK OAuth ni
dependencias nuevas. `DriveAccessSession` recibe el proveedor por constructor;
`app` compondrá el adaptador de cada plataforma cuando esté implementado.
El reloj inyectable permite verificar caducidad sin temporizadores reales.

Este ticket define y verifica el contrato con un proveedor falso. No entrega
almacenamiento seguro nativo ni login real: esas implementaciones deben cumplir
este contrato y verificarse en Windows y Android. El aprovisionamiento real de
MA-TSK-042 continúa en el estado registrado en [OAuth Google](oauth-google.md).
No se conecta el contrato al arranque ni a los marcadores técnicos. El diseño
aprobado está en [entrega Flutter](../ep-002/entrega-flutter.md); no se añaden
pantallas de producto. Epic Board no tiene herramienta disponible en esta
sesión: se utiliza el ticket íntegro facilitado por el usuario, sin modificar
el tablero.

No hay creación/localización de carpeta, archivo vacío, upload, download,
reemplazo de SQLite, fusión, revocación remota ni tareas en segundo plano.
Localizar la copia y devolver `sin_copia` pertenece a las siguientes tareas
de acceso remoto; aquí se define únicamente la referencia local de carpeta.

## Cuenta y metadatos

`DriveAccount.permissionId` es la identidad estable de Drive. El adaptador la
obtendrá al autorizar mediante `about.get` con
`fields=user(permissionId,emailAddress)` y exclusivamente `drive.file`.
`emailAddress` es una etiqueta opcional: su ausencia o cambio no cambia la
identidad. No se usa el correo, el cliente OAuth o el OIDC `sub` como clave de
la cuenta. Referencias oficiales:
[User](https://developers.google.com/workspace/drive/api/reference/rest/v3/User)
y [about.get](https://developers.google.com/workspace/drive/api/reference/rest/v3/about/get).

`DriveSession` transporta cuenta, `validUntil`, conjunto inmutable de permisos
concedidos y carpeta opcional. No contiene tokens, cabeceras, códigos OAuth,
refresh tokens, URLs de callback ni secretos. Los permisos deben ser exactamente
`{https://www.googleapis.com/auth/drive.file}`; la sesión con permiso ausente,
insuficiente o ampliado se rechaza y se limpia localmente. No se amplía el scope
ante errores.

`DriveFolderBinding` contiene `accountId` y `folderId`. Tanto la restauración
como la escritura rechazan una referencia de otra cuenta. Recordar un ID no
acredita que la carpeta sea accesible ni que exista una copia remota: la futura
localización debe comprobarlo con el acceso de la cuenta activa. La carpeta
normal visible **Autofinance** solo podrá crearse por una acción expresa, según
la épica; autorizar o recordar metadatos nunca la crea.

## API y acciones

| Operación | Comportamiento |
|---|---|
| Constructor, `snapshot`, `changes` | Ninguna llamada al proveedor o a la red. Lectura pasiva de estado; flujo de cambios para futuros consumidores |
| `restoreLocalSession()` | Lee solo almacenamiento local seguro; no consulta Drive, no abre autorización ni renueva |
| `requestAccess()` | Acción expresa del futuro flujo Subir/Descargar. Restaura primero la identidad local si es necesario, exige la misma cuenta ya vinculada y solicita solo `drive.file` |
| `changeAccount()` | Acción expresa específica. Borra sesión y carpeta previas antes de abrir el selector. Una cancelación deja la instalación desconectada |
| `renewAccess()` | Petición del flujo manual; sin UI y para la misma cuenta. No se invoca desde abrir, editar o cerrar la app |
| `disconnect()` | Borrado local idempotente, sin red, de credenciales/sesión/carpeta de esta instalación. No borra copias ni afecta a otros dispositivos |
| `rememberFolder(binding)` | Persiste localmente una referencia solo con sesión activa y cuenta coincidente; no consulta ni crea recursos |
| `dispose()` | Cierra observadores; conserva la sesión persistida y no realiza operaciones remotas |

El consumidor comprueba `snapshot.session` inmediatamente antes de usar el
acceso: solo existe para una autorización no caducada. Leer `snapshot` detecta
caducidad aunque no se haya emitido otro evento. No hay eventos por el mero
transcurso del tiempo ni renovación automática. Los adaptadores vuelven a
validar cuenta, permisos y vigencia al realizar una operación remota; una foto
de estado no es una credencial ni garantiza que Google no haya revocado acceso.

Las operaciones son exclusivas: una segunda petición mientras hay otra en
curso arroja `DriveAccessFailure(operationInProgress)` sin cambiar estado ni
abrir otro proveedor. Para cancelar un consentimiento se usa la cancelación
del flujo OAuth de plataforma; la desconexión puede solicitarse cuando termine
la operación. `dispose()` tampoco interrumpe operaciones pendientes.

## Estados y fallos

| Estado Dart | Significado |
|---|---|
| `disconnected` | Sin conectar; ninguna sesión utilizable |
| `connecting` | Autorización o renovación en curso; sin sesión utilizable |
| `authorized` | Cuenta, permiso exacto y vigencia local válidos |
| `permissionDenied` | Google/usuario deniega permiso; requiere otra acción expresa |
| `credentialExpired` | Caducidad, revocación o `invalid_grant`; no se abre consentimiento automáticamente |
| `error` | Fallo controlado; ninguna sesión utilizable |

Una cancelación se indica mediante `issue=cancelled`, sin inventar un séptimo
estado: conserva la sesión anterior y su carpeta, salvo en cambio de cuenta
porque ya se borraron. Si caduca durante el consentimiento cancelado, vuelve
caducada. Denegación es distinta de cancelación. Un fallo conserva únicamente
la identidad informativa cuando procede, sin exponer sesión activa.

`DriveAccessIssue` es un conjunto cerrado; `DriveAccessFailure` solo acepta
esos códigos. El coordinador captura excepciones externas sin imprimirlas,
envolver sus mensajes o propagar respuestas del SDK. `toString()` de cuenta,
sesión y carpeta omite sus campos; el estado y el error imprimen solo enums.
Los adaptadores también deben evitar logs crudos de respuestas, cabeceras y
URLs; no se promete sanear logs de un SDK nativo aún no implementado.

El proveedor verifica `expectedAccountId` antes de persistir. El coordinador
también rechaza un cambio implícito durante autorización, renovación o
restauración y limpia una sesión inválida. `changeAccount()` fuerza selección
y descarta siempre la carpeta antigua, incluso si se vuelve a elegir la misma
cuenta; se deberá localizar de nuevo. No se transportan IDs entre cuentas.

Si falla el borrado seguro, el resultado es `error/secureStorageFailure`, no
se anuncia desconexión. Se descarta el acceso en memoria y se bloquean todas
las operaciones salvo reintentar `disconnect()`. El proveedor puede conservar
datos locales si el sistema no permitió borrarlos; el reintento debe completar
el borrado antes de abrir otra autorización. Nunca se usa la sesión residual.

## Obligaciones de los futuros adaptadores

- Credenciales en almacenamiento protegido por el sistema operativo y
  exclusivo de la instalación. Sesión y referencias de cuenta/carpeta también
  quedan locales; nunca en SQLite compartida, copias remotas, configuración
  pública, assets, dart-defines o repositorio. Excluirlas de copias/restauración
  automática y de mecanismos que puedan trasladarlas a otro dispositivo.
- `readLocalSession()` es estrictamente local. `authorize()` es el único
  método interactivo; comprueba permiso efectivo e identidad antes de guardar
  atómicamente. Fallo o cancelación conserva la sesión anterior. Reautorizar
  la misma cuenta conserva su carpeta. Respetar el flujo OAuth por plataforma
  de MA-TSK-042.
- `renew()` no muestra UI, no cambia cuenta y conserva carpeta. Solo completa
  después de persistir la renovación. `invalid_grant`/revocación invalida de
  forma duradera la credencial local y guarda vigencia caducada, conservando
  identidad/carpeta para una reautorización expresa de esa cuenta.
- `clearLocalSession()` borra credenciales y metadatos juntos, completa solo
  tras borrado verificable y permite reintentos. Desconectar aquí es local;
  revocar el consentimiento Google sería una operación remota distinta.
- `rememberFolder()` valida también la cuenta persistida, escribe
  atómicamente y no cambia las credenciales. No trata el nombre de carpeta o
  un ID conocido como permiso de acceso.

La futura sincronización compondrá este acceso con `LocalBackupSource`. Esta
entrega no importa EP-004, no accede a archivos de base y no modifica su
contrato. La prueba de arquitectura mantiene el grafo de módulos sin ciclos.

## Verificación

`test/synchronization/drive_access_test.dart` usa datos sintéticos y proveedor
falso. Cubre estados, acceso explícito, cancelación con y sin sesión previa,
caducidad/restauración/renovación, revocación, desconexión, selección expresa,
rechazo de cambio implícito, scope exacto, aislamiento de carpeta e instalación,
fallos de escritura/borrado, exclusión de operaciones concurrentes y errores
sin mensajes privados.

Verificación local del 2026-10-01:

- `flutter --version`, `scripts/check-toolchain.ps1` y
  `flutter pub get --enforce-lockfile`: Flutter 3.47.0/Dart 3.13.0 correctos;
  sin cambios de SDK, dependencias o lockfile.
- Pruebas de sesión y arquitectura: **34 correctas** (32 nuevas de sesión y
  dos existentes de arquitectura).
- `scripts/check-quality.ps1` completo: 53 archivos Dart con formato correcto,
  análisis sin incidencias, **109 pruebas Flutter correctas**, además de las
  cuatro variantes de arranque `APP_ENV`.
- La prueba SQLite de MA-TSK-040 sigue emitiendo su advertencia existente de
  instancias múltiples de Drift; no produjo fallos ni se modificó ese código.
- `git diff --check`: correcto. Revisión de los seis archivos propios del
  ticket; datos de prueba sintéticos y ninguna credencial real.

La seguridad nativa, OAuth real, consentimiento, conectividad y acceso a Drive
requieren los adaptadores y pruebas de dispositivo posteriores. No se realizan
builds nativos en MA-TSK-043 porque no se cambian dependencias ni plataformas.
