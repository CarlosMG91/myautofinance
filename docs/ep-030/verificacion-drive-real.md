# MA-TSK-252 · Recorrido conjunto PC ↔ Android con Drive real

Revisión del **2026-10-20**. **T06 bloqueado, sin completar ni aceptar.**
No se han ejecutado transferencias contra Google ni instalado paquetes en esta
sesión. Este registro distingue comprobaciones actuales y guion pendiente;
documentar los bloqueos no satisface los criterios del ticket.

## Identidad y disponibilidad comprobadas

- Consultado `GET http://localhost:4310/api/data`: tablero **My autofinance**,
  workspace coincidente, EP-030 y criterios íntegros de MA-TSK-252, en curso.
  Los requisitos 248/249 figuran `done`; el [informe 249](oauth-windows.md)
  declara explícitamente OAuth real bloqueado. No se modifica el tablero.
- Borrador T06 retomado sobre la fuente actual
  `ed5809f16553ac4314c36e49c397ed971efd2cb7`, versión fuente
  `0.1.0+1`, rama `ticket/ma-tsk-193`, seguimiento `origin/ticket/ma-tsk-193`.
  Son identidades de fuentes, **no de paquetes instalados**.
  La referencia anterior del borrador era `f550e73392cd8c81dad23ee1b5bdb0dc73ede213`;
  no se reutilizan sus verificaciones como resultados de la ejecución actual.
- `config/google-oauth.public.json` sigue `blocked_external`: proyecto y clientes
  Windows/Android nulos, API y tester sin acreditar. SHA-256
  `5edd7ab08658e4a9fe5e9e53db5fb0b648ae3db6d4df6e8d09e691e1855aaccf`.
  Los controles específicos Windows y Android rechazan la configuración con
  salida 1. Esto no demuestra inexistencia del proyecto en Google Cloud.
- ADB solo enumera `emulator-5554`, modelo `sdk_gphone64_x86_64`. El primer
  intento restringido no pudo crear `\\.android`; la consulta con permisos de
  ejecución ampliados sí enumera el emulador. **Sin teléfono físico accesible**.
- La consulta nativa `@oai/sky.list_apps` no muestra Autofinance. El inventario
  de navegador CUA devuelve `apps=[]`, `browsers=[]`; el inventario nativo sí
  ve Chrome con Epic Board. No se ha accedido a Google Cloud ni a una sesión
  de Autofinance. No se confunden ambos inventarios.
- En `dist-private/windows` solo hay fixtures `synthetic-*` y `compiler-probe`;
  en `dist-private/android`, `ci-fixture` y `signing-check`. No hay candidatos
  finales identificados. No se ha facilitado ruta privada alternativa, perfil
  Windows aislado, teléfono o identidad/carpeta Google de ensayo utilizable.
- **Hashes/versiones de los paquetes finales, APP_ENV embebido, identidad de
  ambas instalaciones y estado inicial Google: pendientes.** No se atribuye
  la versión fuente a un EXE/APK ni se reutiliza el APK técnico como final.

Se preservan instalaciones, bases, credenciales y copias existentes. No se
abren bases personales, no se autoriza una cuenta ni se modifica Drive. El
checkout contiene fuentes Drive ajenas modificadas/sin seguimiento; las pruebas
usan ese árbol y no certifican una entrega construible desde HEAD limpio.

## Bloqueos y continuación por propietarios

| ID | Evidencia / entrega que falta | Propietario existente |
|---|---|---|
| D01 | Proyecto compatible, clientes reales, misma cuenta tester y carpeta de ensayo accesible con solo `drive.file`; autorización efectiva en ambos paquetes | EP-030 **249**, EP-029 **239**; reutilizar EP-005, sin clientes/sincronización nuevos |
| D02 | Instalador/EXE y APK finales con manifiestos, hashes, commit limpio y configuración; instalación aislada y teléfono físico | EP-028 **233/235**, EP-029 **241/245**; [Windows T04](verificacion-windows.md), [Android T05](verificacion-android.md) |
| D03 | Fuentes de subida consumidas localmente aún sin publicar; no incorporarlas al commit de T06 | EP-007 **064**, antes de empaquetar el candidato definitivo |
| D04 | Openbank sin fixture caracterizado disponible; `oraculos.json.openbank.fixtures` vacío | EP-014 **124/129/131**, sin otro importador en EP-030 |

D01/D02 bloquean todo el recorrido remoto siguiente. D04 bloquea el tramo
Openbank, pero no es requisito para empezar el tramo CSV cuando D01/D02 estén
resueltos. El antecedente Android de rutas enlazadas de MA-TSK-243 debe
contrastarse con el candidato efectivo por EP-004/006/029. No se reproduce ni
se corrige desde T06 sin paquete/dispositivo. No se crean tickets, interacciones
ni cambios en otros propietarios desde este registro.

T06 no exige cerrar previamente T04/T05: los enlaces a esos informes reutilizan
su evidencia, pero los bloqueos son la falta efectiva de OAuth, paquetes y
dispositivo. Los estados `done` de T02/T03 no suplen esas entregas externas.

## Guion pendiente sobre los dos paquetes finales

Usar [T02](datos-sinteticos.md), sus [oráculos](oraculos.json), EP-001 §7.1 y
[caso I](../ep-001/casos-referencia.md#caso-i--drive-y-fallos), con la UI EP-026.
Reutilizar Gestión → Copia en Drive, Copias locales, exportación y navegación
existentes. Ningún paso siguiente se ha ejecutado con Google real.

Antes de empezar, verificar ambos manifiestos mediante los generadores EP-028/029
existentes y registrar SHA-256 de manifiesto/Setup/EXE/APK, commit, versión,
APP_ENV=production y certificado público Android. Registrar Windows, modelo/SO/API/
ABI/páginas del teléfono, aislamiento y fecha UTC. Usar un perfil Windows dedicado
(APPDATA no aísla Credential Manager) y una instalación Android de ensayo sin
datos personales. Conservar versiones anteriores y copias recuperables.

Contrastar localmente la misma identidad Google y proyecto compatible; en el
informe usar alias `CUENTA-T06`, `CARPETA-T06`, `ARCHIVO-T06`. No publicar correo,
permissionId, IDs externos, consentimientos, cabeceras, callbacks o tokens. La
carpeta normal visible debe estar dedicada al ensayo, sin finanzas personales.
Si ya contiene una copia, conservarla y resolver su estado con el flujo existente;
no borrarla, elegir entre duplicados ni forzar una subida para empezar de cero.

| Paso | Acción expresa y resultado que hay que registrar | Estado |
|---|---|---|
| S00 | Documentar estado inicial independiente de cada instalación: dataset/revisión, copia local recuperable, vínculo/versión conocida/observada, pendientes y último resultado. Android empieza con datos sintéticos propios distinguibles, no otra importación supuestamente equivalente. Abrir/reabrir y visitar Drive no consulta Google ni cambia las bases. | Bloqueado D01/D02 |
| S01 | Windows importa `base.csv` exacto, resuelve cuenta/categorías y guarda foto día 1 según T02. Contrastar BASE: 48 partidas, 10 reales, dos Café con UUID distintos, enero +1229,75/+1100,00/+129,75, anual +2329,65/+13200,00, líquidos 9000,00/neto 14000,00/3,00 meses; febrero sin foto. Consultar propuesta 2027 y cancelarla sin guardar. Preservar BASE-T02. | Bloqueado D02 |
| S02 | Windows importa V01 `categoria-pendiente.csv`, revisa los dos pendientes, cancela una asignación y luego categoriza ambos como **Ocio**, uno individual y otro por selección/lote. Conservar +7/−3, orígenes, filas originales y Discrecionalidad vacía. Editar solo presupuesto **Vivienda / Alquiler, enero 2026**, de −1000,00 a **−1010,00**. Preservar imagen **B1**, dataset/revisión y exportación completa. | Bloqueado D02 |
| S03 | Windows pulsa **Subir copia**. Confirmar copia íntegra, fecha/versión reales **V1**, un único ID activo y estado local limpio vinculado a B1. Inspeccionar versión activa e historial nativo de ese archivo de ensayo. No asumir que V1 sea literalmente `1`. | Bloqueado D01/D02 |
| S04 | Android abre Drive: solo metadatos locales conocidos, sin descarga. Pulsa **Descargar última copia**; antes de sustituir, contrastar cuenta/fecha/V1 con Windows y aviso por base local desconocida o modificada. Cancelar: conservar íntegra su base inicial y no anunciar descarga. Repetir el botón, confirmar, validar respaldo previo y comprobar B1 completa, dataset/revisión idénticos a la imagen subida. Reabrir y repetir consultas sin red. | Bloqueado D01/D02 |
| S05 | Android cambia **la misma partida** de −1010,00 a **−1020,00**: imagen **B2**, misma identidad financiera, revisión nueva observada, cambios locales pendientes sobre V1. Navegar, cerrar/reabrir y reconectar no modifica el remoto. Pulsar **Subir copia** publica V2 en el mismo ID; contrastar fecha, revisión capturada, estado y persistencia. Windows conserva B1 hasta una acción manual. | Bloqueado D01/D02 |
| S06 | En Windows aún obsoleto, cambiar la misma partida a **−1030,00** y preservar esa imagen local **L-obsoleta**. Pulsar **Subir copia**: debe detectar V2 distinta de V1, bloquear sin publicar y conservar L-obsoleta y B2 remota. Registrar aviso/versión, sin fusión ni falso éxito; conservar datos locales y reabrir no sube nada. | Bloqueado D01/D02 |
| S07 | Windows pulsa **Descargar última copia**: aviso por cambios locales, fecha/V2 y confirmación. Cancelar conserva L-obsoleta. Repetir y confirmar instala B2 con respaldo recuperable de L-obsoleta. Cerrar/reabrir y comparar todas las tablas/dataset/revisión con Android B2; ambas instalaciones conocen V2 y no tienen cambios locales. Comprobar el contenido del respaldo en una extracción separada sin restaurarlo sobre la base sincronizada. | Bloqueado D01/D02 |
| S08 | Windows, ya basado en V2, vuelve a editar esa partida a **−1030,00**: imagen **B3**, revisión nueva (no presuponer la misma de L-obsoleta). Subir explícitamente V3; Android conserva B2 hasta pulsar Descargar. Descargar B3 en Android y contrastar ambos sentidos, tablas, identidad/revisión, metadatos y persistencia tras reabrir. | Bloqueado D01/D02 |
| S09 | Registrar V1/V2/V3, versión activa, revisiones nativas disponibles y checksums/fechas saneados del **mismo archivo**. Una revisión purgada no se presume recuperable. No crear un sistema paralelo ni activar retención indefinida. Exportar ambas instalaciones y conservar respaldos. | Bloqueado D01/D02 |
| S10 | Tramo Openbank: consumir fixture/hash/oráculo caracterizado por EP-014, revisar/importar/categorizar en Windows y trasladar manualmente por el mismo flujo. Comparar lotes/originales y fotos intactas. No sustituirlo por CSV/fixture inventado. | Bloqueado D01/D02/D04 |

Las imágenes de S02–S08 son variantes de ensayo, no cambios al oráculo BASE.
No encadenar las otras variantes T02 en esta secuencia. Si un paso falla,
preservar ambas imágenes, registrar el estado y detener sus pasos dependientes.

| Consulta, EUR salvo conteos | BASE | B1 | B2 | B3 |
|---|---:|---:|---:|---:|
| Reales / partidas 2026 | 10 / 48 | 12 / 48 | 12 / 48 | 12 / 48 |
| Real enero | +1229,75 | +1233,75 | +1233,75 | +1233,75 |
| Presupuesto enero | +1100,00 | +1090,00 | +1080,00 | +1070,00 |
| Diferencia enero | +129,75 | +143,75 | +153,75 | +163,75 |
| Real anual | +2329,65 | +2333,65 | +2333,65 | +2333,65 |
| Presupuesto anual | +13200,00 | +13190,00 | +13180,00 | +13170,00 |
| Ocio real enero | −20,00 | −16,00 | −16,00 | −16,00 |

En todas: febrero +1099,90/+1100,00/−0,10; líquidos enero 9000,00,
neto 14000,00 e indicador 3,00 meses, ingresos anuales previstos 36000,00;
febrero sin foto ni indicador. Los cambios presupuestarios no cambian fotos.
Inicio y las cinco vistas Estado/Presupuesto/Real anual/Patrimonio/Indicadores
deben concordar con la columna correspondiente y sus desgloses. Verificar también
diagnóstico sin escrituras, hojas sin doble conteo, dos Café/Discrecionalidad,
Sin clasificar vacío tras S02 y propuesta cancelada sin partidas 2027.

## Integridad, pasividad, fallos e historial

Después de cada descarga comparar **todas las filas de las doce tablas** del
manifiesto EP-027: cuentas, árbol, movimientos, orígenes/lotes/originales,
Discrecionalidad, presupuestos, fotos/valores, liquidez histórica y database_state.
Ordenar por claves primarias y comprobar integridad/foráneas sobre extracciones
nuevas según [recuperación SQLite](../ep-027/recuperacion-sqlite.md). UUID y revisión
de la imagen transferida deben coincidir; iguales sumas no acreditan equivalencia.
No copiar SQLite activa/WAL/SHM. El verificador EP-027 existente tiene su propio
dataset/contrato de captura: no ejecutar su oráculo original como si fuera B1–B3.

Sesión OAuth, Keystore/Credential Manager, rutas, catálogo de copias, exportId/
createdAt y estado Drive son **propios de cada instalación**; no se transportan
ni se exige que coincidan. Registrar versión conocida y observada por separado:
una instalación puede estar limpia respecto de V1 y no conocer aún V2. La
pantalla pasiva no promete metadatos remotos actualizados sin pulsar un botón.

Para cada espera de pasividad registrar intervalo UTC, local antes/después y
remoto antes/después observado mediante la inspección independiente de ensayo.
Esa inspección debe distinguirse de las peticiones de la app. Cerrar/reabrir,
visitar, editar y reconectar sin botones no debe provocar peticiones OAuth/Drive,
transferencias ni aplicación local. No convertir inspecciones en un servicio de
sincronización ni introducir botones o telemetría en el producto.

S06 cubre divergencia **ya observable**, sin exigir comparación condicional.
En una carrera simultánea sobre la misma versión se admite última escritura
activa e historial nativo sujeto a purga; no exigir conservar todas las subidas.
Ante acuse incierto no mostrar éxito: conservar imagen/operación pendiente y
contrastar solo al siguiente botón. Los cortes, descarga inválida, fallo de
respaldo y recuperación completos se coordinan con MA-TSK-253; reutilizar las
suites EP-007 y registrar aparte los resultados de Google real. No introducir
errores artificiales en un paquete final ni aplicar el probe técnico de varios
archivos como sustituto del archivo único de la app.

Por paso guardar fecha, dispositivo/candidato/proveedor, acción, esperado,
observado, dataset/revisión, versión remota conocida/observada, resultado UI y
referencias a copias/capturas saneadas con hash. Hasta ejecutarlo, los campos
observados permanecen pendientes: no rellenarlos con el oráculo. Capturas HTML,
goldens, host, runner, emulador, production y físico se identifican por su origen.

## Verificación de esta sesión

Comprobaciones nuevas de esta ejecución, sobre el árbol de trabajo descrito:

| Comprobación | Resultado observado |
|---|---|
| `flutter --version`, `scripts/check-toolchain.ps1` | Flutter 3.47.0, Dart 3.13.0; control de versiones correcto. El SDK informa canal `[user-branch]`; no se modifica el SDK ni se certifica un candidato production con este control. |
| `node docs/ep-001/verificar-casos.mjs` | Correcto. |
| `node docs/ep-030/preparar-datos.mjs` | Correcto: CSV base, dos Café, copia portable y hashes de los cuatro archivos. No abre SQLite ni Drive. |
| `node scripts/check-google-oauth-windows.mjs` y `check-google-oauth-android.mjs` | Ambos salida 1: falta acreditar proyecto Google común. No se trata como prueba de acceso real. |
| `scripts/check-quality.ps1` | Resolución con lockfile, formato de 508 archivos sin cambios y análisis sin incidencias correctos. Suite general: **2026 correctos / 3 fallidos**, en 15 min 53 s; calidad global **no aprobada**. |
| Suite dirigida secuencial, comando siguiente | **61/61 correctas**, en 1 min 45 s. |
| Arranque con `development`, `test`, `production`, `invalid-synthetic` | **4/4 correctos**, ejecutados aparte porque calidad se detuvo antes de ese tramo. |
| Enlaces locales del informe | Todos los destinos existen. |

El primer intento de calidad restringido falló al consultar pub.dev
(`SocketException`, errno 10057). La repetición autorizada sí resuelve las
dependencias fijadas. Logs privados ignorados en `.tools/ma-tsk-252-current/`;
no se incorporan snapshots del tablero ni inventarios de otras aplicaciones.

Los tres fallos generales coinciden con los archivos/casos ya señalados por
[T08](verificacion-portabilidad.md):

- `local_recovery_journey_test.dart`: restauración EP-001 tras reinicios
  (timeout de 30 s, temporal ocupado errno 32 y contraste de filas) y rollback
  por fallo de disco (conexión Drift cerrada). Propietario EP-006, coordinación
  MA-TSK-253/I02 de T01. No se establece una causa definitiva ni se cambian
  timeouts, validaciones o motores para ocultar estos resultados.
- `wealth_photo_screen_test.dart:317`: no encuentra el texto **«Foto completa»**
  tras guardar. Es el mismo caso de T08, pero allí fallaba la aserción anterior
  de pendientes en la línea 295; no se identifica como idéntico punto de fallo.
  Propietario EP-017, coordinación EP-026/030. Esta aserción de interfaz no
  acredita por sí sola pérdida de datos.

SHA-256 de `quality-authorized.log`:
`c343ac22fa02772caf72b38fb68256c4437cafb7236ad0764eb41eacadfaff5b`.

```powershell
flutter test --no-pub --concurrency=1 --reporter expanded test/synchronization/drive_two_installations_test.dart test/synchronization/drive_reconciliation_test.dart test/synchronization/drive_screen_test.dart test/integral_reference_test.dart
# Una vez por cada APP_ENV de la tabla:
flutter test --no-pub --dart-define=APP_ENV=<entorno> test/environment_bootstrap_test.dart
```

La suite dirigida usa SQLite temporal real del **host Windows**, proveedor
OAuth/HTTP/Drive **simulado** y widgets con tamaños Windows/Android. Comprueba
transferencia en ambos sentidos, filas/identidad/revisión tras reapertura,
divergencia observable, cancelación, respaldo recuperable, acuses inciertos,
edición durante subida, carrera aceptada y pasividad de la pantalla. T02 se
comprueba por separado con su CSV exacto: el fixture de recuperación de Drive
no se presenta como BASE-T02. No es runner nativo, emulador, paquete production,
teléfono físico ni historial de Google real. Las variantes de APP_ENV tampoco
identifican la configuración de un EXE/APK final.

SHA-256 de `targeted.log`:
`219cc91f4e55858340be51ebf7e631a48d01e25bca6dbd870282dddfbba4414e`.
Estas pasadas dirigidas no anulan los tres fallos de la batería general.

No hay cambios de producto, tests, configuración, esquema, lockfile, toolchain ni UI.
No se recompilan plataformas por este documento: un runner no resolvería los
bloqueos del paquete final/Google/teléfono. Solo este archivo pertenece a T06.

**Pendiente de aceptación:** todos los pasos S00–S10 con paquetes/dispositivos y
Google reales. T06 y EP-030 no se completan con las pruebas simuladas ni con este
registro; se mantienen las aprobaciones humanas independientes de 217/256.
