# MA-TSK-251 · Recorrido financiero en teléfono Android

Revisión del **2026-10-20**. **T05 bloqueado; no completado ni aceptado.**
No se ha ejecutado el recorrido en teléfono físico ni instalado un APK en esta
sesión. Este registro permite reanudar la verificación con el candidato correcto;
no satisface los criterios pendientes mediante documentación.

## Fuentes e identidad comprobadas

- Consultado `GET http://localhost:4310/api/data`: tablero **My autofinance**,
  workspace coincidente, MA-TSK-251 en curso, requisito MA-TSK-248 completado y
  dependencias narrativas MA-TSK-239/241/242/245 y EP-014. Sin adjuntos en T05.
  No se modifican estados ni se crean tickets en el tablero.
- Fuente inicial: `ae035c98840c5e676697144cbb93a7719eaef2cf`, rama configurada
  `ticket/ma-tsk-193`, seguimiento `origin/ticket/ma-tsk-193`. Versión fuente
  `0.1.0+1`, Flutter **3.47.0**, Dart **3.13.0**; no identifica una instalación.
- ADB enumera únicamente `emulator-5554`, modelo `sdk_gphone64_x86_64`, API **37**,
  ABI anunciadas `x86_64,arm64-v8a`, `ro.kernel.qemu=1`, páginas **4096** bytes.
  Consultas de solo lectura; la ABI secundaria no lo convierte en teléfono.
  El primer intento restringido falla al crear `\\.android`; la consulta
  autorizada fuera del sandbox obtiene los datos anteriores.
- `dist-private/android` solo contiene `ci-fixture` y `signing-check`; no existe
  candidato final en `candidate/<hash>`. No se ha facilitado una ruta externa,
  un teléfono físico accesible ni un perfil/cuenta de ensayo identificado.
- **Modelo/API/ABI del teléfono, paquete instalado, versión instalada, certificado,
  APP_ENV=production, commit y SHA-256 del candidato final: sin acreditar.**
  No se asigna la identidad del código o de una fixture a esa instalación.

Se conservan todos los cambios ajenos presentes al inicio, incluidas fuentes
Drive sin seguimiento que impiden atribuir el overlay a un commit limpio. No se
abre una base ni una sesión financiera personal, no se instala/desinstala, no
se borran datos y no se opera sobre Google. No hay capturas nuevas de la app.

## Evidencia reutilizable de EP-029 y lagunas

Se lee [MA-TSK-245](../ep-029/verificacion-final-245.md) completo y se contrasta
el SHA-256 del APK técnico local:

| Identidad técnica T02, no candidato final | Valor |
|---|---|
| Archivo ignorado | `dist-private/android/signing-check/autofinance-technical-signature-check.apk` |
| SHA-256 del APK, medido de nuevo | `72bd6242ceddf0962ea9f3034b279a699a1a4983cd30bdf8952968f7173a3bc0` |
| Paquete / versión, inspección existente | `com.carlosmg91.myautofinance` / `0.1.0+1` |
| Certificado público SHA-256, inspección existente | `d6e624f1402fcc0df84cda5373a0b2a89321bd62cb2340a8d69a4a3e663b1951` |
| Certificado público SHA-1, inspección existente | `6a1557043d8b3f9fce356a2532aae09f81cd93f3` |
| Procedencia local | `technical-origin.json`: `technical-signature-check-only`, `completeDelivery=false`, fuente no limpia |

El hash coincide exactamente con el inspeccionado por 245: se reutilizan **solo
su inspección técnica de paquete/firma y sus límites**. No se repite aapt2 ni
apksigner y no se lee material de firma privado. El origen declara un build
release production; ese dato declarado no acredita APP_ENV en un APK final ni
ejecución en teléfono. No existe evidencia de recorrido financiero, documentos,
Google o actualización en teléfono para ese hash. No se instala como sustituto.

Los 17 casos Flutter de host de 245 son antecedentes del núcleo financiero;
no están ejecutados dentro de ese APK. Los
[101 controles nativos de 242](../ep-029/verificacion-almacenamiento.md) usan
debug APP_ENV=test en emulador y host Android de instrumentación sin Flutter/SQLite,
con Downloads/proveedor sintético; no prueban el proveedor del teléfono ni su UI.
Los [ensayos 243](../ep-029/evidencia-actualizacion.json) son release APP_ENV=test
en emuladores API 24/4 KB y API 36/16 KB, bloqueados antes de cargar datos.
No se suman estos antecedentes como pruebas T05 ni se atribuyen al mismo APK.

Cuando exista un candidato final, cotejar primero su hash con 245. Reutilizar
únicamente pasos con artefacto, dispositivo, proveedor, acciones y resultados
identificados; añadir las lagunas de la matriz inferior. Un hash diferente
requiere revisar la aplicabilidad con EP-029, sin heredar aceptación por versión.

## Bloqueos y propietarios existentes

| ID | Evidencia actual | Condición para continuar |
|---|---|---|
| A01 Teléfono/aislamiento | Solo emulador accesible; sin perfil de ensayo identificado. | Disponer de teléfono físico y perfil/cuenta de ensayo autorizado, sin finanzas personales, identificando modelo/API/ABI y tamaño de página. |
| A02 Candidato/OAuth | Sin candidato final; `config/google-oauth.public.json` continúa `blocked_external`, proyecto y serverClientId nulos. `android-delivery.mjs --plan` y `check-google-oauth-android.mjs` rechazan la configuración. | EP-029 MA-TSK-239/241/245: configuración Android real y candidato firmado con manifiesto y fuentes confirmadas; reutilizar la [guía de entrega](../ep-029/guia-entrega-privada.md). No depende de completar OAuth Windows para preparar el APK Android. |
| A03 Openbank | `lib/app/navigation/app_router.dart` mantiene `openbank` deshabilitado; `oraculos.json.openbank.fixtures` vacío. [MA-TSK-131](../ep-014/verificacion-reapertura-131.md) no acredita lector/fixtures/recorrido. No hay muestra privada accesible indicada. | EP-014 MA-TSK-124/129/131: caracterización, fixture fiel con hash/oráculo, lector y ruta integrada. No se ha leído ni supuesto un formato bancario. |
| A04 Apertura/actualización nativa | 243 registra `invalidMetadata` al recorrer `/data/user/0 → /data/data`, antes de abrir SQLite. `BackupStorage.safe()` conserva el rechazo de antecesores enlazados. | Propietarios EP-004/006 con integración EP-029 MA-TSK-243/245: resolver y acreditar apertura/preservación nativa. Es un antecedente reproducido por 243, no una regresión reproducida en teléfono por T05. No se relaja aquí la política de rutas. |

A01/A02 impiden todos los pasos de teléfono; A03 impide además Openbank. A04
debe contrastarse con el candidato efectivo. Los estados `done` de 239/245/131
no acreditan sus entregas: sus informes y resultados siguen declarando bloqueos.
Estas derivaciones son documentales a propietarios ya existentes, sin nueva UI,
motor, lector, almacenamiento ni interacción pendiente de aprobación.

## Recorrido de teléfono pendiente

Aplicar solo tras acreditar A01/A02 y conservar una copia recuperable. Usar
[T02 y reposición](datos-sinteticos.md), [oráculos en céntimos EUR](oraculos.json),
[EP-001](../ep-001/casos-referencia.md) y
[EP-026 aprobado](../ep-026/prototipo/aprobacion.md). BASE-T02 y cada variante
se preparan/reponen como allí se indica; no encadenar variantes salvo V04→V05→V06.
La [matriz Windows T04](verificacion-windows.md) aporta el mismo contraste
esperado; no ha acreditado todavía resultados observados en paquete instalado.

**Todos los pasos siguientes están sin ejecutar en teléfono production.**

| Paso | Acción y resultado a registrar | Bloqueo actual |
|---|---|---|
| P00 Identidad e instalación | Identificar modelo/API/ABI/páginas, perfil sintético, APK/manifiesto/commit/hash/APP_ENV, paquete/versión/certificado público y evidencia exacta 245. Contrastar archivo e instalación conforme a la guía EP-029. Conservar versión previa y copias; si firma incompatible, detener sin uninstall/clear-data. | A01/A02; revisar A04. |
| P01 Documentos CSV | En Gestión, abrir proveedor documental Android y cancelar con Back: retorno sin lote/altas. Volver, seleccionar `base.csv` de T02, revisar y resolver cuenta/árbol, cancelar revisión y comprobar sin altas; repetir y confirmar 48 partidas/10 reales. Registrar proveedor, nombre y hash de bytes; historial/originales conservados. Mismos bytes renombrados: cero altas; dos Café con UUID distintos. Leer `content://` por el selector existente, sin ruta física/permisos amplios. | A01/A02. |
| P02 Clasificación y cuenta | Desde BASE importar V01 (+7/−3): 12 reales, enero +1233,75/diferencia +133,75, Sin clasificar +4,00. Cancelar y confirmar asignación individual/en lote desde Gestión y lote; comprobar selección visible, procedencia/UUID, totales y fotos intactos. V02 sin cuenta impide confirmar sin alta parcial. Reponer BASE entre variantes. | A01/A02. |
| P03 Openbank | Fixture caracterizado de 129 con revisión/hash y oráculo: Documentos → revisión/cuenta → cancelación/retorno → confirmación → lote/Sin clasificar → clasificación individual/lote. Contrastar originales/ordinal, repetición cero, idénticos legítimos y solapamientos revisables sin eliminación automática; fotos intactas. | A01/A02/A03. |
| P04 Presupuesto | Registrar/editar/guardar desde mensual y anual, consultar desglose y reabrir; distinguir cero explícito/ausencia. V07 padre Vivienda con Alquiler: rechazo completo, 48 partidas y enero +1100 intactos. | A01/A02. |
| P05 Propuesta anual | V08 desde BASE: 60 asignaciones 2027, enero +3100/−1000/−360/−500/−20, febrero +3020/−1000/−430/−500/0; resto cero editable por raíz. Cancelar deja 2027 vacío. Reabrir, editar solo Ocio enero a −30 antes de guardar: enero +1210/anual +2300; 2026 intacto. Consultar/reabrir y reponer BASE. | A01/A02. |
| P06 Fotos día 1 | BASE enero líquidos 9000/neto 14000. V03 febrero ausente; V04 incompleta con pendientes; V05 ahorro cero → líquidos 6200/neto 11900/2,07 meses. Corregir principal a 6300 → neto 12000, fecha 2026-02-01. Reponer V05: V06 cartera líquida febrero → 16700/5,57; enero conserva 9000/3,00; corregir a media → 6200/2,07. No derivar saldos de movimientos. | A01/A02. |
| P07 Cinco vistas y diagnóstico | Inicio/Estado enero +1229,75/+1100/+129,75; febrero +1099,90/+1100/−0,10. Patrimonio 14000; presupuesto anual +13200; real anual +2329,65; indicador 3,00 meses. Desplegar Alimentación hasta hoja sin doble conteo y Ocio con dos Café/−20. Diagnóstico/recalcular sin reparar ni escribir datos. Abrir registros y volver conservando periodo/filtros según contrato. | A01/A02. |
| P08 Vacíos/cambio de año | V09 marzo/diciembre 2026 real cero/previsto +1100; enero 2027 sin movimientos ni partidas antes de guardar propuesta, patrimonio/indicador sin foto. V10 ingresos incompletos; V11 nulos; V12 líquidos cero → 0,00 meses válido, neto 5000. Reponer BASE entre variantes. | A01/A02. |
| P09 Back/teclado/formularios | Recorrer barra Android/gesto Back desde documentos, revisión, formulario, diálogo, detalle y Más → Gestión. Registrar destino, periodo/filtros/selección, borrador y guardado antes/después según contrato. Con teclado visible, comprobar Back para ocultarlo y después volver; campos, importes, errores y botón Guardar accesibles sin recortes. Si una interacción necesaria no está definida, derivar al propietario antes de inventarla. | A01/A02. |
| P10 Reanudación/persistencia | Pasar a Documentos y volver/cancelar; pasar a Google real con cuenta de ensayo y regresar conservando estado conforme al contrato. Pausar/reanudar y cerrar/reabrir app: contrastar guardados, UUID/revisión, procedencia, fotos/presupuesto y copias. Distinguir reanudación de Activity de muerte del proceso; no considerar una selección inconclusa importación confirmada. No activar Drive fuera de sus acciones explícitas. | A01/A02; Google requiere 239. |
| P11 Táctil/texto ampliado | Registrar pantalla, orientación y escala normal/ampliada (200 % si el dispositivo la permite). Recorrer listas, Más, formularios, tablas/tarjetas, desgloses, diálogos y teclado; comprobar lectura, toque, desplazamiento y controles accesibles frente a EP-026, sin rediseño. Conservar/restaurar ajustes de ensayo. | A01/A02. |

La edición P05 aplica el mismo delta de −10 EUR que T04 sobre la propuesta
sin editar (enero +1220/anual +2310); no cambia el oráculo base ni sus reglas.
El transporte PC↔Android/Drive y la consulta SQLite independiente conservan sus
propietarios T06/T07; T05 registra su estado local sin simular esos recorridos.

Por cada paso ejecutado, guardar fecha, candidato/hash, dispositivo/proveedor,
estado inicial/variante, acciones, esperado/observado, revisión antes/después y
referencia privada sanitizada a captura/log. Identificar el origen como
«paquete production/teléfono físico», «runner», «emulador» o «host» según proceda.
Una prueba fallida debe conservar su resultado y reproducción antes de corregir
una integración; carencias funcionales se derivan al propietario de la
[auditoría T01](auditoria-cobertura.md). No publicar APK, extractos, bases
personales, tokens, cuentas personales ni claves.

## Comprobaciones de esta sesión

| Control | Resultado observado |
|---|---|
| `flutter --version`; `scripts/check-toolchain.ps1` | Flutter 3.47.0 / Dart 3.13.0 correctos; canal informado `[user-branch]`, sin cambiar SDK. |
| `node docs/ep-001/verificar-casos.mjs` | OK: 48 partidas/10 reales, enero +1229,75, anual real +2329,65/presupuesto +13200 EUR y variantes de liquidez. |
| `node docs/ep-030/preparar-datos.mjs` | OK: CSV original/copia portable, dos Café y hashes de las cuatro entradas T02. |
| `node --test scripts/tests/android-apk-contract.test.mjs scripts/tests/android-delivery.test.mjs scripts/tests/android-storage.test.mjs` | **45/45 aprobadas**, cero omitidas. Pruebas de herramientas/fixtures; no instalan ni ejecutan el APK en teléfono. |
| `flutter test --no-pub --concurrency=1 --reporter expanded test/integral_reference_test.dart` | **9/9 aprobadas**, SQLite temporal sintética de host Windows, fuera del sandbox. Incluyen identidad/revisión, copia consistente/lector independiente, persistencia, fotos, propuesta, variantes de importación e indicador. No prueban pantallas ni teléfono. |
| `scripts/check-quality.ps1` | **Fallido** durante `flutter pub get --enforce-lockfile`: SocketException 10057 al consultar `https://pub.dev/api/packages/http/advisories`. No alcanza formato/análisis/suite global ni variantes de arranque. |
| Formato independiente sin resolver paquetes | `dart format --output=none --set-exit-if-changed lib test integration_test`: **508 archivos, cero cambios**. |
| Análisis independiente `flutter analyze --no-pub --fatal-infos --fatal-warnings` | **Sin incidencias**, 115,4 s. |
| Integridad documental | Los 11 enlaces locales del informe existen; revisión de diff y whitespace antes del commit. |

Logs locales ignorados en `.tools/`: `ma-tsk-251-quality.log`,
`ma-tsk-251-node.log`, `ma-tsk-251-reference.log`, `ma-tsk-251-format.log` y
`ma-tsk-251-analyze.log`. La consulta del tablero queda local en
`ma-tsk-251-board.json`, sin incorporarla al repositorio. Las consultas ADB y el
hash se registran en la actividad de esta ejecución. No se afirma calidad
global aprobada por las comprobaciones independientes.

Solo cambia este informe: no se ha reproducido un fallo nuevo de integración
en un teléfono disponible. No se modifica producto ni se recompilan plataformas;
un build debug/test no resolvería A01/A02 ni acreditaría T05. Se solicita al usuario
teléfono/perfil de ensayo y ruta privada del candidato/manifiesto; para Openbank,
fixture caracterizado y evidencia 245 del mismo hash cuando estén disponibles.

El cierre de T05 exige ejecutar los criterios pendientes. El cierre de EP-030
exige además expediente y aprobación humana explícita; este informe no concede
la aceptación visual MA-TSK-217 ni la aceptación final de la épica.
