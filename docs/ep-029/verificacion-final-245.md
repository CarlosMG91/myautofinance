# MA-TSK-245 · Verificación final del APK privado

Revisión del 2026-10-20. **Bloqueado; ticket y épica sin aceptación final.**
No se ha generado, instalado ni entregado un APK final con Google Drive real.
Este informe registra comprobaciones y condiciones pendientes, no sustituye
los recorridos exigidos por el ticket.

## Fuentes y punto de partida

Consultados mediante `GET http://localhost:4310/api/data`: **My autofinance**,
workspace de este repositorio, MA-EPIC-236, MA-TSK-245 y sus requisitos
MA-TSK-239/243/244, además de la entrega narrativa MA-TSK-131 de EP-014.
Las listas de adjuntos de MA-TSK-245 y MA-TSK-131 están vacías. No se ha
facilitado una ruta privada de muestra Openbank ni se han leído sus bytes.

Base Git `7cad30ad5d60d2b2ee1a51251e681cdc791fe040`, rama configurada
`ticket/ma-tsk-193`, seguimiento `origin/ticket/ma-tsk-193`.
Hay trabajo concurrente previo en README, sincronización y documentación de
otras épicas. En particular, HEAD importa `drive_upload_factory.dart` y exporta
`domain/drive_upload.dart`, todavía sin seguimiento en Git. No se incorporan
esos archivos ajenos para aparentar una entrega desde commit definitivo.
T09 necesita una base funcional confirmada y regenerar con T05 después de
cualquier cambio de código/configuración pública.

## Contraste de dependencias

Los tres requisitos y MA-TSK-131 figuran `done` en el tablero. Las evidencias
funcionales prevalecen sobre ese estado administrativo:

| Requisito | Evidencia contrastada | Consecuencia para T09 |
|---|---|---|
| MA-TSK-239, OAuth Android | [Verificación T03](verificacion-oauth-android.md) y `config/google-oauth.public.json`: `blocked_external`, proyecto/`serverClientId` nulos, API/tester falsos, clientes vacíos. | No se puede generar ni probar un APK con Google real. El gate T05 rechaza la configuración. |
| MA-TSK-243, actualización | [Verificación T07](verificacion-actualizacion.md) y [resumen nativo](evidencia-actualizacion.json): dos intentos release `APP_ENV=test`, API 24/4 KB y API 36/16 KB, detenidos al abrir almacenamiento en N; no existe pareja N→N+1 acreditada. | Falta demostrar conservación, Keystore y sesión tras actualización; las fixtures no prueban producción. |
| MA-TSK-244, guía | [Guía privada](guia-entrega-privada.md) disponible; declara expresamente ausencia de APK completo y requisitos de T09 pendientes. | Procedimiento disponible; no acredita instalación, recuperación ni Google real. |
| MA-TSK-131, Openbank | [Traspaso EP-014](../ep-014/verificacion-reapertura-131.md), caracterización y lector pendientes; `app_router.dart` mantiene Openbank con `enabled: false`. | No hay recorrido que repetir en el APK final. Selector o contrato sintético EP-012 no satisfacen el criterio. |

El código vigente de `BackupStorage.safe()` continúa rechazando enlaces en
todos los antecesores de la ruta. El diagnóstico T07 observó el alias Android
`/data/user/0 → /data/data` y `invalidMetadata` antes de abrir SQLite. Esta
revisión contrasta el código y la evidencia existente; **no repite el ensayo
nativo ni atribuye a T09 una corrección del módulo propietario**.

## Dispositivos y artefactos observados

ADB de solo lectura enumera únicamente `emulator-5554`, modelo
`sdk_gphone64_x86_64`: API **37**, ABI anunciadas `x86_64,arm64-v8a`,
`ro.kernel.qemu=1`, páginas medidas con `getconf PAGESIZE`: **4096** bytes.
La ABI secundaria no acredita teléfono físico ARM64. No se instala ni modifica
la app del emulador; no se accede a ninguna sesión personal.
El primer intento ADB en sandbox falla por acceso a `\\.android`; la consulta
fuera del sandbox, autorizada y de solo lectura, devuelve los datos anteriores.

El APK técnico T02 existente se vuelve a inspeccionar con `aapt2` y
`apksigner`, SDK/Build-Tools 36.0.0 y JDK 17, sin leer la clave privada:

| Dato observado | Valor |
|---|---|
| Archivo local ignorado | `dist-private/android/signing-check/autofinance-technical-signature-check.apk` |
| SHA-256 del APK | `72bd6242ceddf0962ea9f3034b279a699a1a4983cd30bdf8952968f7173a3bc0` |
| Paquete y versión | `com.carlosmg91.myautofinance`, `0.1.0+1` |
| Depurable / certificado debug / split | No / No / No |
| SDK mínimo / compile / target | 24 / 36 / 36 |
| ABI | `arm64-v8a`, `armeabi-v7a`, `x86_64` |
| SHA-256 del certificado T02 | `d6e624f1402fcc0df84cda5373a0b2a89321bd62cb2340a8d69a4a3e663b1951` |
| SHA-1 del certificado T02 | `6a1557043d8b3f9fce356a2532aae09f81cd93f3` |
| Inspector T01 | `problems=[]`, `completeDelivery=false` |

Coincide con el inventario público independiente T02. Su procedencia y límites
están en [verificación de firma](verificacion-firma.md): incluye fuentes del
checkout compartido, carece de OAuth real y **no es el candidato final T05**.
La inspección no prueba `APP_ENV`, alineación 16 KB ni ejecución en teléfono.
No se instala ese APK como sustituto de la entrega requerida.

## Comprobaciones de esta revisión

- `flutter --version` y `scripts/check-toolchain.ps1`: Flutter **3.47.0**,
  Dart **3.13.0** correctos; canal informado `[user-branch]`, sin cambiar SDK.
  Platform 36, Build-Tools 36.0.0 y NDK 28.2.13676358 contrastados en sus
  `source.properties`; inspector ejecutado con JDK 17 existente.
- `node docs/ep-001/verificar-casos.mjs`: correcto, 48 presupuestos y 10 reales;
  enero +1.229,75 €, anual real +2.329,65 €, anual presupuesto +13.200,00 €,
  liquidez histórica enero 3,00 y febrero 5,57 meses. Es un comprobador de datos,
  no evidencia de las cinco vistas en el APK.
- Contrato APK, T05, T06 y T07: **50 pruebas Node aprobadas**.
- OAuth Android: **11 pruebas Node aprobadas**, incluida la inspección opt-in
  del APK técnico T02 real. Primera ejecución conjunta: 60 aprobadas y esa
  prueba omitida; repetida la suite OAuth con las rutas locales reales:
  11 aprobadas, ninguna omitida. No se suman las repeticiones como casos nuevos.
- `node scripts/android-delivery.mjs --plan` y
  `node scripts/check-google-oauth-android.mjs`: salida **1**, bloqueo de
  proyecto Google común. Es el rechazo esperado de la configuración pendiente,
  no un build de producción ni una autorización Google.
- `scripts/check-quality.ps1`: **fallido** durante
  `flutter pub get --enforce-lockfile`, al consultar
  `https://pub.dev/api/packages/http/advisories` (SocketException 10057,
  restricción de red). No alcanza análisis ni suite completa; no se declara
  calidad global correcta ni se atribuye el fallo a la aplicación.
- Comprobados aparte, sin resolver paquetes: `dart format --output=none
  --set-exit-if-changed lib test integration_test`, **506 archivos, cero cambios**;
  `flutter analyze --no-pub --fatal-infos --fatal-warnings`, **sin incidencias**.
- Regresión dirigida de host: primera ejecución en sandbox, **10 aprobadas y
  siete fallidas** en 19 s. Pasan los ocho casos de flujo CSV con SQLite y los
  dos de aceptación del indicador. Fallan `bank_import_wealth_test.dart` y los
  dos casos de Patrimonio con `DatabaseFailureCode.restoring`; los dos de
  Estado y los dos de Real anual fallan al comprobar `local.open == true`.
  No se modifica código ni pruebas para resolverlos.
- Repetición **solo de los siete fallidos fuera del sandbox**, con
  `--no-pub --concurrency=1`: **siete aprobadas en 6 min 31 s**. Incluye
  protección de fotos del contrato sintético EP-012, Estado, Real anual y
  Patrimonio, con las variantes Windows/Android de host. Resultado combinado:
  los **17 casos únicos seleccionados** pasan entre ambas ejecuciones. La
  diferencia de entorno se registra sin atribuir una causa interna no aislada.
  No acredita suite completa, lector Openbank ni APK de producción.

Evidencia local ignorada: `.tools/ma-tsk-245-quality.log` (hasta la resolución;
el error de red se recibe en stderr de la ejecución),
`.tools/ma-tsk-245-format.log`, `.tools/ma-tsk-245-analyze.log`,
`.tools/ma-tsk-245-directed-tests.log`, `.tools/ma-tsk-245-directed-retry.log`,
`.tools/ma-tsk-245-oauth-tests.log` y
`.tools/ma-tsk-245-technical-inspection.json`. No se publican APK, claves,
sesiones, bases personales ni extractos. No se recompilan plataformas por
este cambio documental: el build final está bloqueado antes de compilar.

Reproducción de la regresión dirigida (sin instalar nada):

```powershell
flutter test --no-pub --concurrency=1 --reporter expanded `
  test/importing/csv_import_flow_test.dart `
  test/importing/bank_import_wealth_test.dart `
  test/indicators/indicator_acceptance_test.dart `
  test/monthly_status/monthly_status_journey_test.dart `
  test/actual_spending/annual_actual_lifecycle_test.dart `
  test/wealth/wealth_lifecycle_test.dart
```

El reintento fuera del sandbox usa solo los cuatro archivos fallidos:
`bank_import_wealth_test.dart`, `monthly_status_journey_test.dart`,
`annual_actual_lifecycle_test.dart` y `wealth_lifecycle_test.dart`.
Son casos de host Windows con distintas configuraciones de plataforma/UI,
no ejecuciones nativas en los dos sistemas.

## Criterios finales todavía no acreditados

| Criterio | Estado y evidencia necesaria para reanudar |
|---|---|
| APK production definitivo | Bloqueado por T03 y fuentes sin confirmar de otros tickets. Generar con T05 desde commit y publicconfig definitivos; identificar manifiesto/hash y contrastar paquete, firma, versiones, SDK y ABIs del archivo e instalación efectivos. |
| Inicio, cinco vistas, captura, presupuesto y fotos | Sin ejecutar en ese APK. Importar el CSV sintético EP-001 desde Documentos con revisión y cuenta, confirmar 48 partidas/10 reales y recorrer las vistas: enero real +1.229,75 / previsto +1.100,00 / diferencia +129,75; anual real +2.329,65 / previsto +13.200,00; neto 14.000 / líquidos 9.000 / colchón 3,00. Repetir ausencias, cero y liquidez histórica en copias independientes. |
| CSV y Openbank | CSV sin recorrer en APK final; Openbank bloqueado por MA-TSK-131. Solicitar muestra privada anonimizada verificable y completar su lector/adaptador/fixtures/integración en EP-014. T09 repetirá selección → revisión/cuenta → confirmación → lote/Sin clasificar → categorización, mismos bytes renombrados cero altas, idénticos legítimos y fotos intactas. Identificar hashes de fixtures y versión de lector sin publicar la muestra. |
| Google real | Bloqueado por T03 y falta de cuenta de pruebas disponible. Autorizar explícitamente solo `drive.file`; comprobar cuenta/carpeta, subida y descarga manual, divergencia, error, cancelación y renovación. Con Windows OAuth pendiente, usar dos instalaciones Android de prueba; no afirmar Windows OAuth. Evidencia privada sanitizada, sin tokens ni datos personales en logs/Git. |
| Actualización production N→N+1 | Bloqueada por T07 y ausencia de teléfono. Misma firma/paquete y código creciente; contrastar datos/revisión, procedencia/lotes, partidas/fotos/liquidez, copias/diarios, estado sync y descifrado del mismo registro con la misma clave Keystore. Comprobar también sesión Google real posterior. Sin desinstalar ni borrar datos. |
| Teléfono ARM64 y 16 KB | No hay teléfono acreditado. Identificar modelo/API/ABI/páginas reales y pruebas ejecutadas. T07 identifica ensayos API 24/4 KB y API 36/16 KB bloqueados; API 36/4 KB sigue pendiente. No declarar soporte 16 KB por build, alineación binaria ni arranque inicial aislado. |
| Transición desde debug distinto | No autorizada sobre instalación personal ni acreditada una recuperación viable. Si existe ese origen, detener transición hasta tener copia independiente accesible y recuperación probada con destino T02. Conservar la instalación original. |

Se ha solicitado al usuario dispositivo de pruebas, configuración pública OAuth
real y ruta privada de la muestra. No cambiar estados ajenos ni cerrar este
ticket o EP-029 por este informe. Tras resolver los bloqueos, ejecutar los
recorridos sobre el hash exacto final y registrar dispositivo, versiones,
acciones/resultados y evidencias privadas sanitizadas; repetir tras cualquier
cambio del APK. Confirmar/subir únicamente cambios propios, sin force-push.
