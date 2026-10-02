# MA-TSK-049 · Traspaso del acceso a Drive

EP-005 entrega autorización, sesión local segura y metadatos a la futura épica
de subida/descarga. No lee SQLite ni transfiere contenido. EP-004 entrega por
separado la [copia local consistente y reemplazo](../ep-004/transacciones-copias.md).
La sincronización posterior necesitará ambas entregas y el contrato EP-001 §7.1.
El flujo visible procede de [EP-002 y la aprobación MA-TSK-019](../ep-002/entrega-flutter.md);
este ticket no implementa pantallas de producto.

## Composición por instalación

`lib/app/drive_access_factory.dart` ofrece `createWindowsDriveInstallation`
y `createAndroidDriveInstallation`. Ambas devuelven `DriveAccessInstallation`
con `access`, `metadata`, `folders` y `copies` conectados a **un mismo proveedor**.
Windows añade `cancelAuthorization`; Android utiliza el selector nativo.
Se conservan las fábricas anteriores de sesión para sus consumidores.

Construir no lee almacenamiento ni inicia SDK, OAuth o HTTP. El llamante crea
y cierra el cliente HTTP y conserva una sola composición durante el flujo:
el localizador de carpeta retiene la protección en memoria ante un POST incierto.
Antes de cerrar el cliente, terminar operaciones y llamar a `dispose()`.
`dispose()` libera observadores; `access.disconnect()` borra la sesión local.
No se conectan estos objetos al arranque de Autofinance.

```dart
final client = http.Client();
final drive = createWindowsDriveInstallation(
  clientId: publicDesktopClientId,
  client: client,
);
// Android: createAndroidDriveInstallation(serverClientId: publicWebClientId,
//                                        client: client).
```

El cliente Desktop, el cliente Android de la firma efectiva y el cliente Web
Android pertenecen al mismo proyecto OAuth. El inventario público y su control
estricto viven en [OAuth Google](oauth-google.md). No pasar secretos ni tokens
mediante dart-defines. El inventario no es un almacén de sesión ni un asset.

## Secuencia que debe consumir sincronización

1. Una acción manual obtiene `access.requestAccess()`. Continuar únicamente con
   `authorized` y permiso exacto `{driveFileScope}`. Si hace falta renovación,
   invocar `renewAccess()` expresamente; ninguna consulta renueva por su cuenta.
2. Para consultar/descargar usar `folders.findFolder()`, que nunca crea.
   Solo una petición expresa que permita crear usa `folders.requestFolder()`.
   Continuar a copias únicamente tras `found` o `created`. Ante ambigüedad,
   ubicación incorrecta, referencia inaccesible o creación sin confirmar,
   detener el flujo: no conservar una selección anterior como si fuera válida.
3. Consultar `copies.findCopy(knownCopy: optionalBinding)` y comprobar el estado.
   `noCopy` significa **sin_copia**: esperar a una primera subida válida.
   No crear un archivo vacío para reservar ID. `inaccessible` nunca significa
   ausencia; `ambiguous` nunca permite elegir por fecha, nombre o versión.
4. La futura subida/descarga debe revalidar cuenta, carpeta e identidad/versiones
   antes de transferir. Estos metadatos no son una reserva atómica ni evitan
   carreras entre instalaciones. Proteger divergencias y publicación conforme
   a EP-001; no hay fusión ni reintentos en segundo plano.

## Contrato de carpeta, archivo y sesión

| Elemento | Identidad y datos | Persistencia / responsabilidad |
|---|---|---|
| Cuenta | `DriveAccount.permissionId` de Drive; correo solo etiqueta | Nunca usar correo ni OIDC sub como clave |
| Permiso | Únicamente `https://www.googleapis.com/auth/drive.file` | Rechazar permisos ampliados; no añadir scopes para solucionar un fallo |
| Carpeta | Normal, inicialmente `Autofinance`, MIME `application/vnd.google-apps.folder`, padre raíz real de Mi unidad y `appProperties={autofinanceRole: backupFolderV1}` | `DriveFolderBinding(accountId, folderId)` en almacén seguro local, fuera de SQLite/copia; nombre editable sin perder identidad |
| Copia inicial | `driveAutofinanceCopyName` = `autofinance.sqlite`; `appProperties={autofinanceRole: databaseCopyV1}`; archivo binario dentro de la carpeta validada | La futura subida escribe nombre/marca junto con la primera base válida; EP-005 solo consulta |
| Copia conocida | `DriveCopyBinding(accountId, folderId, fileId)` | El consumidor la guarda fuera de la copia SQLite; no se persiste por este localizador |
| Copia presente | ID, nombre actual, `version` decimal como cadena y `modifiedTime` UTC; tamaño/checksum opcionales | No confundir versión de Drive con esquema SQLite ni acreditar integridad por metadatos |
| Sesión | Cuenta, scope, vigencia y carpeta, sin tokens en dominio | Por instalación; no se comparte al transferir la base |
| Estado de sincronización | Versión remota de origen, cambios locales y resultado de operación | Pendiente de la épica posterior; no usar vigencia OAuth como versión de copia |

Android conserva metadatos en Keystore/noBackup y un token verificado **solo en
memoria** del proveedor. Windows obtiene el token existente de Credential
Manager. Los proveedores implementan `DriveMetadataCredentialSource` en datos,
sin exportar tokens por `synchronization.dart`. `readCredential` solo lee
credenciales verificadas locales, ligadas a la cuenta y vigentes: no llama al
SDK, token endpoint ni navegador. El cliente HTTP vuelve a comprobar scope,
cuenta y vigencia antes de cada petición.

Tras reiniciar Android, restaurar metadatos no recupera un token: la consulta
falla con `credentialUnavailable` hasta pedir acceso/renovación expresamente.
Un intento de autorización/renovación Android descarta la credencial en memoria
anterior y solo publica la nueva tras validar scope, identidad y persistencia.
Un fallo conserva el registro local anterior, pero puede requerir repetir la
acción expresa para recuperar credencial utilizable. Revocación invalida la
vigencia conservando cuenta/carpeta; Windows borra además sus tokens. Cambiar
cuenta y desconectar borran el vínculo previo local, sin borrar recursos remotos
ni afectar la sesión de otra instalación.

Las carpetas/copias homónimas sin marca no se adoptan. Los duplicados marcados
se señalan tras completar todas las páginas. Un 404 de una referencia conocida
es inaccesibilidad; no autoriza sustitución ni anuncia sin_copia. Errores de
metadatos conservan su código y `retryAfter`, sin renovar ni esperar solos.
El flujo debe tratar por separado los resultados y los fallos lanzados por
carpeta (`DriveAccessFailure` / `DriveMetadataFailure`); copia conserva el motivo
en `accessIssue` / `metadataFailure` de un resultado `inaccessible`.

Detalles: [sesión](sesion-drive.md), [Android](autorizacion-android.md),
[Windows](oauth-windows.md), [HTTP](metadatos-drive.md),
[carpeta](carpeta-drive.md) y [copia](copia-remota.md).
Las [propiedades privadas](https://developers.google.com/workspace/drive/api/guides/properties)
y el alcance de [drive.file](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
se contrastaron en la documentación oficial. La reutilización real entre
clientes del proyecto sigue necesitando la evidencia de ambos dispositivos.

## Verificación y límite de entrega

`test/synchronization/drive_access_integration_test.dart` ejecuta los adaptadores
Android/Windows, sesión, composición, cliente HTTP y localizadores de producción
con SDK/navegador, almacenamiento y HTTP sintéticos. Prueba el recorrido en
ambos órdenes, reinicio, sesión independiente, consulta sin creación, carpeta
única y sin_copia. Cubre denegación/cancelación/configuración, permisos ampliados,
revocación, red en OAuth y metadatos, 401/403/503, cuenta distinta, almacén
ilegible y duplicados de carpeta/copia en segunda página. Las peticiones se
inspeccionan: el único POST a archivos crea una carpeta, no bytes ni SQLite.

El ejecutor nativo y la evidencia pendiente se describen en
[verificación integrada](verificacion-integrada.md). Las pruebas falsas y el
análisis no acreditan OAuth ni almacenamiento nativo ni carpeta visible real.
