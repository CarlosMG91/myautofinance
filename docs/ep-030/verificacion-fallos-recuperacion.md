# MA-TSK-253 · Fallos y recuperación conservando ambas versiones

Revisión del **2026-10-20**. **T07 no completado: ensayo sobre los dos
paquetes finales y Google real bloqueado.** Las regresiones automatizadas y el
runner nativo se identifican por separado; no sustituyen la entrega privada ni
la aprobación humana de EP-030.

## Alcance contrastado

Consultado `GET http://localhost:4310/api/data`: tablero **My autofinance**,
workspace coincidente, MA-EPIC-246, descripción y aceptación completas de
MA-TSK-253 `in-progress`, sin adjuntos. Los requisitos 248/249 figuran `done`.
La entrega efectiva se contrasta con [T02](datos-sinteticos.md),
[OAuth Windows](oauth-windows.md), configuración y recursos actuales. No se
actualiza el tablero ni se infiere conformidad del estado `done`.

Fuentes: EP-001 §7.1 y casos A/D/G/I, contratos EP-006/007/012 y
[auditoría vigente](auditoria-cobertura.md). Se conserva EP-026, incluida su
aceptación humana independiente. No cambian UI, motores, esquema, SDK,
lockfile, importador ni credenciales. No se añaden controles de fallos al
producto. No se interviene sobre instalaciones personales.

Fuente inicial `f550e73392cd8c81dad23ee1b5bdb0dc73ede213`, rama configurada
`ticket/ma-tsk-193`, seguimiento `origin/ticket/ma-tsk-193`, versión fuente
`0.1.0+1`. El checkout contiene modificaciones concurrentes de EP-007/064 y
otras tareas. Las pruebas consumen ese árbol; no certifican un paquete
reproducible desde HEAD limpio. Esos cambios quedan fuera del commit T07.

## Regresión integrada añadida

Se amplía `test/synchronization/safe_drive_download_application_test.dart`
con **seis casos T07** que reutilizan el proveedor controlado, el coordinador
de descarga/restauración y la inyección existentes. `seedIntegralReference`
importa el CSV exacto T02 mediante preview/confirmación reales y crea las fotos
manuales mediante repositorios. Cada prueba recibe SQLite y directorio nuevos.

Se preservan dos copias manuales validadas: BASE y LOCAL. LOCAL añade un real
de −123,45 EUR en enero; BASE es la imagen que ofrece el proveedor remoto.
No son bases de Windows y Android físicos: son estados sintéticos en el host.

| Estado | Reales | Enero real EUR | Presupuesto anual EUR | Foto enero / líquidos | Febrero |
|---|---:|---:|---:|---|---|
| BASE T02 | 10 | +1229,75 | +13200,00 | Completa / 9000,00 EUR | Sin foto |
| LOCAL T07 | 11 | +1106,30 | +13200,00 | Completa / 9000,00 EUR | Sin foto |

Los dos Café idénticos mantienen UUID distintos. Se compara el contenido de
**todas las tablas**, incluida identidad/revisión y trazabilidad, usando un
lector SQLite independiente sobre copia consistente. Se ejecutan
`integrity_check` y `foreign_key_check`, y se comprueban las cifras mediante
repositorios. Reabrir crea un store nuevo; no cuenta como reinicio de proceso
del paquete final.

Se contrastan también las entradas y metadatos durables del catálogo, incluidos
hashes, epoch y contraste. Un respaldo que falla después de reservar su ordinal
incrementa `nextCreationOrder` en uno sin publicar entrada: es el comportamiento
existente de EP-006. Se permite esa reserva y el avance de generación/fecha de
escritura, conservando exactamente el resto del catálogo y las dos manuales.

| Caso añadido | Proveedor / fallo | Comprobación |
|---|---|---|
| Cancelar revisión con cambios locales | HTTP controlado; decisión rechazada | Cero descargas, sin éxito, tablas/revisión/catálogo intactos antes y después de reabrir |
| Sin red | `SocketException` en HTTP simulado | Local utilizable; remoto y catálogo conservados; sin peticiones al reabrir |
| Descarga truncada | Respuesta HTTP controlada de 512 bytes | No instala contenido incompleto ni acredita versión |
| Esquema futuro | Archivo SQLite temporal real con `user_version=99`, entregado por HTTP simulado | Rechaza imagen incompatible sin modificar local ni las copias manuales |
| Respaldo previo fallido | Excepción inyectada en `createConsistentBackup` | No sustituye local; no pierde ninguna copia ni anuncia descarga completada |
| Descargar → restaurar local anterior → reabrir → restaurar imagen descargada | HTTP simulado; SQLite, copias y diario reales del host | Disponibilidad explícita de ambas versiones; tablas exactas; fotos invariantes; contraste pendiente; sesión sintética conservada y cero peticiones automáticas |

Tras recuperar LOCAL se conserva la versión remota conocida `7` como
antecedente, con contraste requerido; no debe borrarse ni marcarse sincronizada
la restauración. La última restauración prueba que la imagen BASE descargada
sigue recuperable desde el respaldo automático creado al volver a LOCAL.

## Matriz del resto de criterios y procedencia

Las suites siguientes se reutilizan sin crear otro motor o importador.
Sus fixtures históricos no se equiparan a BASE-T02; cada una compara su propio
estado inicial. Una pasada en host no completa la columna de paquetes reales.

| Criterio | Regresión existente | Procedencia y límite |
|---|---|---|
| CSV inválido, cuenta pendiente, cancelación, repetición renombrada, doble confirmación, rollback sin altas parciales, duplicados legítimos | `test/importing/csv_import_flow_test.dart`, `sqlite_import_confirmation_test.dart`, `sqlite_import_preview_test.dart`, `test/integral_reference_test.dart` | CSV sintético, controladores y SQLite temporal del host; selector/paquetes finales pendientes |
| Red, streaming cortado, cancelación de subida/descarga y parcial eliminado | `drive_transfer_client_test.dart`, `validated_drive_downloader_test.dart`, `drive_two_installations_test.dart` | HTTP/proveedor controlados; no se corta la conexión del equipo ni se acredita fallo de Google |
| Subida incierta y reconsulta antes de otro intento | `validated_drive_uploader_test.dart`, `installation_sync_state_test.dart`, `drive_reconciliation_test.dart`, `drive_two_installations_test.dart` | Acuses y versiones simulados; pendiente durable, sin segunda publicación oculta. La fuente de subida es concurrente de EP-007/064 |
| Revocación y reconexión | `windows_drive_session_provider_test.dart`, `android_drive_session_provider_test.dart`, `drive_access_test.dart` | Proveedores OAuth/HTTP y almacenes controlados; invalid_grant no acredita revocación real de la concesión Google |
| Corrupción, esquema incompatible, respaldo, espacio/escritura, sustitución y reapertura fallidos | `local_restore_candidate_test.dart`, `local_restore_test.dart`, `safe_drive_download_application_test.dart`, `local_recovery_journey_test.dart` | Ficheros SQLite reales temporales; I/O inyectado. **No** demuestra volumen lleno, avería, corte eléctrico o falta real de espacio |
| Restaurar, corregir estado, diario interrumpido, contraste al reabrir | `local_recovery_journey_test.dart`, `local_restore_test.dart`, `safe_drive_download_application_test.dart` | Diario/archivos del host; worker separado con `exit(73)` en tres fases, sin ejecutar finally. No es cierre forzado de Android ni del paquete production |
| Dos versiones y divergencia observable | `drive_two_installations_test.dart`, `drive_reconciliation_test.dart` | Dos instalaciones lógicas con servidor simulado; sin fusión. Se respeta la carrera aceptada de última escritura, sin exigir CAS ni retención indefinida Google |
| Openbank caracterizado | [EP-014/131](../ep-014/verificacion-reapertura-131.md) | Bloqueado: no muestra/lector/fixture caracterizado; no sustituir por el adaptador bancario sintético EP-012 |

## Ejecución reproducible

El runner existente `integration_test/local_backup_creation_test.dart` falló
antes de probar I/O: esperaba esquema **6**, pero la base vigente publica **8**
(EP-012/110). Se corrige únicamente esa expectativa para exigir el esquema de
la base activa. La compatibilidad/migración histórica permanece en sus suites;
no se cambia ni relaja el validador. Este fallo reproducido pertenece a la
integración del ensayo, no demuestra pérdida de datos en producto.

Usar las versiones fijadas, en un checkout sin operaciones de build concurrentes:

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
node docs/ep-001/verificar-casos.mjs
node docs/ep-030/preparar-datos.mjs
flutter test --no-pub --reporter=expanded test/synchronization/safe_drive_download_application_test.dart
flutter test --no-pub --reporter=expanded test/synchronization/local_recovery_journey_test.dart
./scripts/check-quality.ps1
flutter test integration_test/local_backup_creation_test.dart -d windows --no-pub --dart-define=APP_ENV=test --reporter=expanded
```

En este entorno, la ejecución restringida bloquea la comprobación de
antecesores de las rutas temporales Windows antes de abrir SQLite. El
reintento autorizado usa solo directorios sintéticos desechables, sin relajar
las validaciones de producción. Logs locales ignorados `.tools/ma-tsk-253-*`.
No versionar bases, binarios ni logs de OAuth.

- Flutter 3.47.0 / Dart 3.13.0 y `check-toolchain.ps1`: correctos; resolución
  `pub get --enforce-lockfile` correcta, sin cambios en lockfile.
- Verificadores EP-001 y preparación T02: correctos.
- Formato y análisis general: correctos. Análisis dirigido de los dos archivos
  Dart modificados: sin incidencias.
- Runner Windows existente, `APP_ENV=test`, compilación **debug** del checkout:
  primera ejecución falla por expectativa de esquema desactualizada (6/8);
  tras corregirla, **1 prueba aprobada**. Comprueba ficheros/SQLite y bloqueo
  nativo en un subdirectorio sintético privado, reapertura del store y fallo de
  `flushFile` **inyectado**. No abre base/sesión personal ni acredita disco lleno
  real, cierre de proceso, paquete production o aceptación visual.
- `check-quality.ps1`: **2027 aprobadas, 2 fallidas**, en 17 min 11 s de
  pruebas. Formato de 508 archivos y análisis correctos. Falla
  `local_recovery_journey_test.dart`: «dos manuales, restauración y recuperación
  de la anterior» agota 30 s, con error de borrado por archivo en uso; aparecen
  después `operationInProgress` y conexión Drift cerrada en «fallo de disco tras
  instalar». Son resultados actuales de la incidencia I02 de T01: no se declara
  calidad global correcta ni se modifica motor/timeout para ocultarlos.
- Comprobación dirigida con `--concurrency=1`: **31 aprobadas**, 23 de descarga
  (incluidas las seis T07) y ocho de recuperación, en 2 min 59 s. Pasan los dos
  casos anteriores y las tres terminaciones reales del worker en fases
  002/003/004, recuperación y segundo reinicio. No se reproduce el fallo al
  ejecutar aislado; no se ha establecido su causa definitiva. Mantener I02 en
  EP-006/059 con coordinación T07; esta pasada no convierte en correcta la
  ejecución general fallida. No se aumentan timeouts.
- Las cuatro variantes de arranque `development`, `test`, `production` e
  `invalid-synthetic` pasan ejecutadas aparte: el script de calidad se detuvo
  antes de ellas. Formato final de los dos archivos modificados correcto.
- No se compilan entregas production ni APK desde este overlay: solo cambian
  pruebas/documentación. El runner Windows ya se compiló y ejecutó; no implica
  verificación Android ni paquete final.

Un intento dirigido adicional coincidió con runners usando la DLL SQLite del
directorio de build compartido y no pudo cargarla. Es un fallo de preparación,
sin casos ejecutados; se repite al terminar los runners, sin cambiar la
configuración global de build. No se presenta como fallo de recuperación.

## Bloqueos actuales y ensayo pendiente

- Los verificadores específicos Windows/Android rechazan la configuración
  pública: `blocked_external`, proyecto y clientes nulos, API/tester pendientes.
  SHA-256 de `config/google-oauth.public.json`:
  `5edd7ab08658e4a9fe5e9e53db5fb0b648ae3db6d4df6e8d09e691e1855aaccf`.
  No se dispone de una sesión/cuenta/carpeta Google de ensayo acreditada. Esto
  no demuestra que no exista un proyecto en Google Cloud. Propietarios:
  **MA-TSK-249**, EP-029 **239**, reutilizando EP-005/007.
- `flutter devices` autorizado enumera Windows y **emulator-5554**, Android 17
  API 37 x86_64; no teléfono físico. La consulta restringida falla al crear
  `\\.android`, por lo que no se usa como prueba de ausencia de dispositivos.
- El inventario nativo no ofrece ventana Autofinance; CUA navegador devuelve
  `apps=[]`, `browsers=[]`. No se accede a cuentas ni sesiones personales.
- Las rutas `dist-private/windows` y `dist-private/android` contienen fixtures
  sintéticos/compiler-probe/ci-fixture/signing-check, sin candidatos finales
  identificados. Faltan manifiestos, hashes y versiones efectivas de los dos
  paquetes y perfiles de ensayo aislados. Propietarios EP-028 **233/235** y
  EP-029 **241/245**. El runner no es el instalador/EXE final ni el APK privado.
- La incidencia histórica Android de rutas enlazadas sigue documentada en
  T01 (B05), EP-004/006 y EP-029 **242/243**. No se da por corregida por pasar
  pruebas del host. La auditoría I02 exige contrastar los fallos históricos de
  recuperación con el resultado aislado actual, sin alterar timeouts sin causa.

Una vez disponibles los recursos, ejecutar sobre clones independientes de BASE
con [T02](datos-sinteticos.md) y el recorrido T06/MA-TSK-252. Se ha consultado
`docs/ep-030/verificacion-drive-real.md`, archivo concurrente sin seguimiento
que no se incorpora a este commit; su publicación corresponde a T06.
Antes de cada caso conservar exportación portable y copias locales validadas
de ambos estados. Registrar plataforma/OS, modelo, aislamiento, fecha UTC,
commit limpio, SHA-256 del paquete/manifiesto/configuración y `APP_ENV=production`.
Usar alias de cuenta/carpeta/archivo; no correos, IDs externos, tokens,
cabeceras, códigos, callbacks ni capturas del consentimiento.

| Ensayo pendiente sobre **ambos paquetes** | Evidencia exigida |
|---|---|
| Cancelar CSV/revisión y confirmación doble; CSV inválido y cuenta pendiente | Antes/después de tablas, lotes, UUID/revisión, Café y fotos; reabrir proceso |
| Revocar solo concesión de la cuenta de ensayo; reconectar manualmente | Fallo o petición de autorización según flujo vigente, sin éxito falso; conservar datos y volver a operar con drive.file. No borrar sesión para simular una revocación |
| Red ausente/corte durante subida y descarga, cancelación; acuse incierto si se reproduce | Registrar punto efectivo y origen del fallo; conservar remoto anterior hasta publicación completa y local hasta instalación válida; reconsulta explícita antes del reintento, sin publicación doble automática |
| Cancelar descarga con cambios; candidata corrupta/incompatible | Local y catálogo recuperables, mensaje honesto, versión remota anotada. Aislar archivos de ensayo; no modificar la única copia remota válida |
| Respaldo/escritura fallidos y recuperación del diario | Reutilizar inyección exclusiva de runner cuando sea preciso, separada del paquete final. No llenar disco del usuario ni añadir interruptores de fallo production. Un mock no satisface fallo nativo real |
| Descargar con éxito; recuperar el estado local previo; corregir y restaurar; reabrir proceso | Dos versiones utilizables, exportaciones/tablas/identidad/revisión exactas, fotos sin recalcular, sesión conservada y contraste Drive pendiente |

Si falta el medio seguro para provocar un fallo nativo, mantener ese criterio
pendiente y explicar la procedencia disponible. Las carencias de interacción
se devuelven a su propietario con aprobación del usuario, sin ampliar EP-026
desde T07. **Documentar estos bloqueos no completa MA-TSK-253 ni EP-030.**
