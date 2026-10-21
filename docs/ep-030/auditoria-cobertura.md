# MA-TSK-247 · Auditoría de cobertura de la entrega integral

Inventario del **2026-10-20**. Este documento termina T01; **no acredita una
entrega integral ni cierra EP-030**. Contrato: [EP-001](../ep-001/especificacion.md),
[CSV v1](../ep-001/contrato-csv.md) y [casos A–O](../ep-001/casos-referencia.md).
Diseño vigente: [EP-026 v1](../ep-026/prototipo/aprobacion.md).

## Identidad y método

- Código auditado: `173361aafc98de46f144e0bc2cd4a001a658cd5e`, rama configurada
  `ticket/ma-tsk-193`, remoto `origin` de este proyecto. Versión fuente
  **0.1.0+1**; Flutter **3.47.0**, Dart **3.13.0**, esquema existente sin cambios.
  No existe aquí un candidato final identificado por hashes de ambos paquetes.
- Epic Board consultado por `GET http://localhost:4310/api/data`, tablero
  **My autofinance**, workspace exactamente coincidente. Leídos MA-TSK-247,
  EP-030, propietarios y criterios de 131/202/207/217/226/235/245. La consulta
  es de solo lectura: no se crean, reabren ni modifican tickets.
- El checkout ya contenía README, ocho fuentes Drive y otros prototipos/fixtures
  ajenos sin confirmar. Las ocho fuentes usadas se identifican por hash en
  [evidencia-auditoria.json](evidencia-auditoria.json). Tres no están en HEAD:
  `drive_upload_factory.dart`, `validated_drive_uploader.dart`, `drive_upload.dart`.
  HEAD ya consume esas dependencias. La ejecución local no certifica un checkout
  limpio reproducible; su publicación corresponde a EP-007/MA-TSK-064.
- No se abren instalaciones, sesiones, extractos ni bases personales. Se
  inspeccionan código, contratos, resultados versionados y configuración pública;
  las pruebas usan sus instalaciones sintéticas temporales. No se han recibido
  adjuntos ni ruta privada de muestra Openbank; no se afirma haber leído sus bytes.

**Estados:** «comprobado» se limita al alcance de la evidencia citada;
«pendiente» significa que falta ejecución o aceptación; «bloqueado» identifica
un impedimento concreto. El estado de entrega de cada fila se refiere al
candidato final instalado en **PC Windows y teléfono Android físicos**.
Una pasada histórica, una variante Android en host o un build no satisface ese
estado. La matriz separa cobertura existente y entrega para evitar esa inferencia.

## Catálogo de evidencia reutilizada

Cada E identifica un informe leído y su commit documental, **no necesariamente
el commit exacto de los binarios ensayados**. Cuando el informe no lo vincula,
esa trazabilidad queda pendiente del expediente MA-TSK-255. Todos corresponden
a la línea de versión fuente `0.1.0+1`; no prueban identidad de un paquete final.
Las fechas siguientes son las de la revisión documentada. H = host Windows con
widgets de ambas disposiciones; RN = runner nativo; EM = emulador; P = paquete
production instalado; F = dispositivo físico. Ninguna E acredita P+F en ambos
extremos con Google real. No se suman pasadas históricas como una suite actual.

| ID | Fecha / commit documental | Evidencia y alcance reutilizable |
|---|---|---|
| E01 | 2026-10-20 / código auditado | [Casos EP-001](../ep-001/casos-referencia.md), CSV SHA-256 `0b997f5c8092369aa47a08c8cca6d4c22050abca320880a173818d4e34576b62`; verificador numérico ejecutado en T01, correcto. No prueba UI. |
| E02 | 2026-10-05 / `45bc574` | [Movimientos MA-TSK-095](../ep-010/verificacion-recorrido.md): SQLite, edición, Discrecionalidad, lotes, procedencia, rollback y reapertura; H. |
| E03 | 2026-10-05 / `8a0e3d9` | [Presupuesto mensual MA-TSK-105](../ep-011/verificacion-presupuesto-mensual.md): editor y conflictos sobre SQLite; interfaces Windows/Android. |
| E04 | 2026-10-08 / `ca3e911` | [CSV MA-TSK-120](../ep-013/integracion-csv.md): composición real, lector/adaptador, revisión y repetición; automatización H y canales de selección, sin recorrido humano del selector en teléfono. |
| E05 | 2026-10-09 / `c0b583b` | [Pendientes MA-TSK-138](../ep-015/verificacion-categorizacion.md): 9 dirigidas, RN Windows profile; Android H, sin RN Android en esa entrega. Guion hoy afectado por I01. |
| E06 | 2026-10-09 / `906f67f` | [Periodos MA-TSK-146](../ep-016/verificacion-historico.md): histórico/futuro, Madrid, borradores y retornos; no certifica informes todavía ausentes en aquella fecha. |
| E07 | 2026-10-10 / `c9a0594` | [Propuesta MA-TSK-156](../ep-018/verificacion-integral.md): H, RN Windows profile/Android EM API 37, cancelación/sustitución/reapertura. |
| E08 | 2026-10-11 / `57df0d0` | [Estado MA-TSK-164](../ep-019/verificacion-integrada.md): consulta, desgloses, edición y retorno. |
| E09 | 2026-10-12 / `bba9a73` | [Anual presupuesto MA-TSK-172](../ep-021/verificacion-integral.md): SQLite, matriz/tarjetas, UUID, cero, conflictos, restauración. |
| E10 | 2026-10-14 / `696641c` | [Real anual MA-TSK-180](../ep-022/validacion-integral.md): H y RN Windows; Android RN no acreditado en ese informe. Complemento H posterior en E18. |
| E11 | 2026-10-15 / `fbc7dbe` | [Indicador MA-TSK-188](../ep-023/validacion-integrada.md): dos recorridos RN por plataforma, Android EM API 37; razones/entradas/retorno/restauración. |
| E12 | 2026-10-16 / `27c6d4b` | [Desgloses MA-TSK-194](../ep-024/verificacion-tres-informes.md): 35 regresiones, RN Windows debug y Android EM; filtros/subtotales/retorno. |
| E13 | 2026-10-16 / `e62d631` | [Diagnóstico MA-TSK-202](../ep-025/verificacion-recorrido.md): 93 dirigidas, siete hitos RN Windows/Android EM, servicios reales y lectura sin reparación. Calidad global fallida documentada. |
| E14 | 2026-10-14 / `5db43b2` | [Rediseño MA-TSK-217](../ep-026/validacion-integral.md): 120 capturas RN, Android EM; antigua revisión parcial. Sin aceptación visual final. |
| E15 | 2026-10-17 / `9b7e03f` | [Portabilidad MA-TSK-226](../ep-027/verificacion-portabilidad.md) y [JSON](../ep-027/evidencia-portabilidad.json): RN Windows/Android EM, destinos nativos, SQLite estándar en Windows sin Flutter; 8 exportaciones/plataforma. |
| E16 | 2026-10-18 / `60ded3f` | [Windows MA-TSK-235](../ep-028/verificacion-e2e.md): **sin paquete production ni E2E cliente**; CI/fixtures no equivalen a instalación real. Referencia de calidad: [MA-TSK-233](../ep-028/verificacion-generacion.md), `68a87c1`. |
| E17 | 2026-10-18 / `d45f944` | [Openbank MA-TSK-131](../ep-014/verificacion-reapertura-131.md): no lector/adaptador/muestra; prueba `synthetic-contract-131` solo acredita EP-012 e invariancia patrimonial. |
| E18 | 2026-10-20 / `173361a` | [APK MA-TSK-245](../ep-029/verificacion-final-245.md): 17 casos únicos H seleccionados pasan entre ejecución/reintento autorizado; no APK final, Google real ni teléfono. [T07](../ep-029/evidencia-actualizacion.json): apertura Android bloqueada en EM API 24/4 KB y API 36/16 KB. |
| E19 | 2026-10-02 / `656bef7` | [Recuperación MA-TSK-059](../ep-006/verificacion-recuperacion.md): ocho casos de fichero real, reinicios y procesos interrumpidos. Revisar I02 antes de reutilizar como conformidad actual. |
| E20 | 2026-10-02 / `d954b63` | [Drive MA-TSK-069](../ep-007/verificacion-sincronizacion.md): dos instalaciones SQLite y servidor/proveedor **simulados**, carrera incluida; Google real pendiente. |
| E21 | 2026-10-20 / código auditado + overlay | [Ejecución T01](evidencia-auditoria.json): calidad, comparación dirigida y huellas; alcance y resultados en «Verificación de T01». |

## Matriz del recorrido familiar

Rutas de implementación y pruebas son relativas a la raíz del repositorio.
Las cinco vistas contractuales son Estado, Patrimonio, Presupuesto anual,
Real anual e Indicadores. Inicio es su entrada de resumen; diagnóstico es una
acción adicional. **W/A** en cada fila exige los dos paquetes finales físicos;
la columna E delimita qué parte se ha ejecutado hasta ahora.
E21 añade la suite de host actual: todos sus casos pasan salvo los dos de I01;
no amplía el alcance nativo, físico ni de proveedores de las evidencias citadas.

| ID / paso · plataforma | Caso / oráculo aprobado | Propietario y código / suite reutilizable | Cobertura comprobada y evidencia | Estado de entrega / evidencia faltante |
|---|---|---|---|---|
| R01 Importar CSV · W/A | A: 48 partidas/10 reales, normalización una vez, anual +13.200/+2.329,65; cancelar/renombrar mismos bytes = 0 altas, dos Café distintos | EP-013 MA-TSK-116/119/120/122 y EP-012 109/110; `lib/app/csv_import_factory.dart`, `lib/features/importing/data/historical_csv_reader.dart`; `test/importing/csv_import_flow_test.dart`, `import_redesign_test.dart` | Comprobado en lector/SQLite y flujo automatizado: E01/E04/E14/E18 | **Pendiente**: selector real, revisión/asignación y persistencia sobre hashes finales; MA-TSK-248/250/251. |
| R02 Openbank · W/A | §7, EP-014 131: lectura caracterizada, cuenta/ordinal/originales, repetición 0, solapamientos revisados y fotos intactas | EP-014 MA-TSK-124/125/126/129/130/131; `lib/app/openbank_selector_factory.dart`, entrada deshabilitada en `lib/app/navigation/app_router.dart`; `test/importing/bank_import_wealth_test.dart` solo contrato sintético | **Bloqueado**: E17 y código actual; selector binario existente, lector/adaptador ausentes | **Bloqueado** B01: muestra y entrega EP-014, después repetir en MA-TSK-250/251. No sustituir por CSV ni sintético. |
| R03 Categorizar individual · W/A | §2, J/N; cambia solo categoría/timestamp, conserva UUID, signo, cuenta, Discrecionalidad y origen; cancelar no escribe | EP-010 MA-TSK-093/095 y EP-015 134/135/138; `lib/features/movements/domain/pending_movement_management.dart`; `test/movements/pending_movement_test.dart`, `movement_lifecycle_test.dart` | Comprobado en servicios/recorridos históricos: E02/E05/E13. I01 impide dar por verde el recorrido completo vigente de bandeja | **Pendiente**: acceso/guardar/retorno en paquetes, actualizar evidencia I01; 250/251. |
| R04 Categorizar en lote · W/A | §2, N: solo selección visible; cancelación y fallo en segunda escritura revierten todo; duplicados legítimos conservados | EP-010 MA-TSK-090/094/095, EP-015 134/138; `lib/features/movements/domain/movement_management.dart`; `test/movements/movement_batch_test.dart`, `pending_lifecycle_test.dart` | E02/E05; cobertura de dominio existente, **recorrido actual bloqueado I01** | **Pendiente**: selección/confirmación/cancelación, concurrencia y procedencia en 250/251/253. |
| R05 Movimientos y Discrecionalidad · W/A | §2, J/K/L: fecha de valor, importe firmado, categoría NULL, texto conservado sin filtro específico; dos piernas solo si se registran | EP-010 MA-TSK-087/092/093/095; `lib/features/movements/presentation/movement_form_screen.dart`; `test/movements/movement_form_test.dart`, `movement_lifecycle_test.dart` | Comprobado en H: E02; agregaciones posteriores E10/E12; no exige filtro de Discrecionalidad | **Pendiente**: crear/editar/borrar/volver/reabrir y conservación del texto en 250/251. |
| R06 Árbol de categorías · W/A | §2.1, L–O: tres niveles, UUID y tipo raíz; archivo/traslado conserva historia; padre/descendiente conflictivo revierte | EP-008 MA-TSK-079/080/083/085; `lib/app/category_management_factory.dart`; `test/persistence/category_reorganization_test.dart`, `test/movements/category_lifecycle_test.dart` | E01 (solo cifras L/M), suites SQLite inventariadas; no confundir comprobador numérico con prueba de O | **Pendiente**: revisar árbol y selectores durante categorización, verificar rollback de O con suite propietaria y recorrido 250/251. |
| R07 Presupuesto mensual · W/A | §3, E/H/O: +1.100 por mes, cero distinto de ausencia, sin padre+descendiente; guardado explícito | EP-011 MA-TSK-100/102/103/105; `lib/features/budget/presentation/monthly_budget_screen.dart`; `test/budget/budget_lifecycle_test.dart` | Comprobado E03/E09/E14; antiguas incidencias de timeout no se consideran solución por un build | **Pendiente**: edición Windows/formulario Android y reapertura 250/251; fallos integrados 253. |
| R08 Vista Presupuesto anual · W/A | §5.3, E: 12 meses, +13.200, 48 partidas, ingresos +36.000, sin doble conteo | EP-021 MA-TSK-168/169/170/172; `lib/features/budget/domain/annual_budget_query.dart`, `lib/features/budget/presentation/annual_budget_screen.dart`; `test/budget/annual_budget_lifecycle_test.dart` | Comprobado E09/E14 | **Pendiente**: resumen→detalle matriz/tarjetas→editar→retorno y UUID en 250/251. |
| R09 Propuesta de nuevo año · W/A | §3, H: enero Alimentación −360 desde −350,25, febrero −430; ceros editables, desglose retira padre, sustituir exige confirmación | EP-018 MA-TSK-150/151/152/154/156; `lib/features/budget/domain/budget_proposal_calculator.dart`, `lib/features/budget/presentation/budget_proposal_screen.dart`; `test/budget/budget_proposal_acceptance_test.dart` | Comprobado E07/E14, RN Windows profile y Android EM | **Pendiente**: generar/revisar/editar/cancelar/confirmar sin tocar 2026 en 250/251. |
| R10 Inicio y vista Estado · W/A | §5.1, B/C/J/K/L: enero +1.229,75 / +1.100 / +129,75; febrero +1.099,90 / +1.100 / −0,10; Ocio sin presupuesto sigue en total | EP-019 MA-TSK-160/161/162/164, EP-026 210; `lib/app/monthly_status_query_factory.dart`; `test/monthly_status/monthly_status_journey_test.dart`, `test/redesign_integration_test.dart` | Comprobado E08/E14/E18 (H posterior de ambos tamaños) | **Pendiente**: resumen→detalle→origen y actualización de cifras en 250/251, sin sumar padre+hoja. |
| R11 Vista Real anual · W/A | §5.4, F/J/K/L: +2.329,65, meses sin reales = 0; Sin clasificar +4 en variante J | EP-022 MA-TSK-174/176/177/178/180; `lib/app/annual_actual_query_factory.dart`, `lib/features/actual_spending/presentation/annual_actual_screen.dart`; `test/actual_spending/annual_actual_lifecycle_test.dart` | **Implementada hoy**; E10/E12/E18. Marcador de E14 es histórico | **Pendiente**: resumen/matriz/tarjetas/origen/retorno en 250/251 y evidencia visual 217 actualizada. |
| R12 Periodos e histórico · W/A | §5, histórico 146: cruce diciembre/enero, Madrid, ausencia/cero, memoria de periodo y borrador, lectura sin escritura | EP-016 MA-TSK-140/142/143/146; `lib/app/navigation/navigation_session.dart`; `test/historical_navigation_journey_test.dart`, `test/navigation_session_test.dart` | Comprobado E06 y recorridos posteriores E09–E13; no heredar todas las vistas de una prueba anterior a su implementación | **Pendiente**: recorrer cinco vistas con mismo periodo y contextos locales en 250/251. |
| R13 Desgloses y filtros locales · W/A | §5, B/E/F/J: suma/UUID del origen = cifra; NULL/directos/rama/mes/año, subtotal completo independiente de página; retorno conserva contexto | EP-024 MA-TSK-190/192/193/194 y enlaces 162/170/178; `lib/features/budget/domain/budget_list_query.dart`, `lib/features/movements/domain/movement_list_query.dart`; `test/drilldowns/report_source_reconciliation_test.dart`, `report_drilldown_journey_test.dart` | **Implementados hoy**, E12; incidencia global histórica Windows registrada, pasada aislada no acredita suite general | **Pendiente**: tres informes→listas→edición→retorno, filtros y reconciliación en 250/251. |
| R14 Fotos día 1 y vista Patrimonio · W/A | §4/5.2, D: líquidos 9.000/neto 14.000 en enero; febrero ausente/parcial sin dato; completo con cero 11.900; corrección 12.000 sin cambiar enero ni flujos | EP-009 MA-TSK-072/073/074/075/076/077, EP-017 148, EP-026 212; `lib/features/wealth/presentation/wealth_photo_screen.dart`, `lib/features/wealth/domain/wealth_reading.dart`; `test/wealth/wealth_lifecycle_test.dart` | Comprobado E13/E14/E15/E18; fichas/vigencia/liquidez existentes, independientes de movimientos | **Pendiente**: capturar/corregir/consultar sin acarreo, liquidez histórica y reapertura en 250/251. |
| R15 Vista Indicadores · W/A | §6/6.1, G/D/L/M: 9.000/(36.000/12)=3 meses; parcial/ausente/incompleto/nulo/negativo con motivo; cero líquido válido; único indicador | EP-023 MA-TSK-182/183/184/186/188; `lib/features/indicators/domain/emergency_cushion_calculation.dart`, `lib/features/indicators/presentation/indicator_screen.dart`; `test/indicators/indicator_acceptance_test.dart` | **Implementada hoy**, E11/E13/E18; no es ya el marcador de E14 | **Pendiente**: fuentes/formula/motivos y completar dato→retorno sobre paquetes en 250/251. |
| R16 Diagnóstico manual · W/A | EP-001 y contrato EP-025: repetición no alta, duplicados legítimos no error, sin presupuesto válido; detecta referencias/conflictos sin reparar; invalidar tras guardar/restaurar | EP-025 MA-TSK-197/198/201/202; `lib/app/diagnostic_factory.dart`, `lib/features/diagnostics/presentation/diagnostic_screen.dart`; `test/diagnostics/diagnostic_acceptance_test.dart` | **Implementado hoy**, E13, siete hitos RN por plataforma; cumple recorrido propio en su alcance, sin conformidad global | **Pendiente**: ejecutar/ver orígenes/cancelar/repetir y comparar todas tablas en 250/251/253. |
| R17 Exportar CSV · W/A | EP-027 v1, A–G/J: 10/48, +2.329,65/+13.200; enero 6/4, +1.229,75/+1.100; rango vacío solo cabeceras; Unicode/Discrecionalidad/céntimos intactos | EP-027 MA-TSK-219/220/222/224/226; `lib/features/synchronization/data/csv_data_exporter.dart`; `test/synchronization/data_export_test.dart`, `integration_test/export_portability_test.dart` | Comprobado E15: archivos de destinos nativos Windows/Downloads EM leídos fuera de Flutter | **Pendiente**: exportaciones de las instalaciones finales y lector independiente en 254. |
| R18 Copia SQLite portable / consulta independiente · W/A | EP-027 contrato v1 y guía SQL: 12 tablas, identidad/revisión/hashes, integrity/foreign_key, todas filas y cifras iguales; no reconstruir desde CSV | EP-027 MA-TSK-221/225/226; `lib/features/synchronization/data/portable_backup_exporter.dart`; `test/synchronization/portable_backup_export_test.dart`; [guía SQL](../ep-027/recuperacion-sqlite.md) | Comprobado E15 con SQLite estándar Windows, sin app/Flutter para lectura | **Pendiente**: repetir extracción de ambos paquetes finales en carpetas nuevas, registrar hashes/versión SQLite en 254. |
| R19 Copia local y persistencia · W/A | §7.1, D/I, EP-006: manuales conservadas, tres automáticas, copia consistente; restaurar conserva todas tablas/revisión y respaldo; reabrir datos | EP-006 MA-TSK-052/053/055/056/059; `lib/app/local_backup_factory.dart`, `lib/features/synchronization/data/local_restore_service.dart`; `test/synchronization/local_recovery_journey_test.dart` | E19/E13/E15 y comparación I02; los fallos globales no se borran por pasadas aisladas | **Pendiente**: crear/reabrir/restaurar anterior y recuperar fallo en paquetes, 250/251/253. |
| R20 OAuth / cuenta / carpeta · W/A | §7.1: mismo proyecto de ensayo, consentimiento solo `drive.file`, cuenta/carpeta visibles, sesión protegida | EP-005 MA-TSK-042/044/045/049; Windows EP-030 **249**, Android EP-029 **239**; `lib/app/drive_access_factory.dart`, `config/google-oauth.public.json`; suites de sesión `test/synchronization` | Implementaciones existentes; **configuración bloqueada** B02. E18/E20 no son autorización Google real | **Bloqueado**: proyecto/clientes/API/tester; configurar sin rehacer clientes y acreditar sesión real en 249/239. |
| R21 Subir / Descargar PC↔Android · W/A | §7.1, I: único archivo, 48/10/foto tras Windows→Android y viceversa; solo botones; versión/fecha visibles; respaldo antes de aplicar | EP-007 MA-TSK-064/065/067/068/069, EP-030 252; `lib/app/drive_ui_factory.dart`; `test/synchronization/drive_two_installations_test.dart`, `integration_test/synchronization_redesign_test.dart` | Comprobado con proveedor/HTTP **simulados** E20/E14; SQLite/copia reales; fuentes concurrentes B03 | **Bloqueado** B02/B03/B04: dos paquetes, Google y dispositivos; prueba remota efectiva 252. |
| R22 Divergencia, incertidumbre y fallos · W/A | §7.1, I: base local/remota conservadas, cancelar no aplica, inválido/incompleto no sustituye; no fusión ni background. Carrera de único archivo aceptada | EP-006/007 MA-TSK-054/056/063/066/069, EP-030 253; `lib/features/synchronization/data/manual_drive_reconciliation.dart`, `lib/features/synchronization/data/safe_drive_download_application.dart`; `test/synchronization/drive_reconciliation_test.dart`, `drive_two_installations_test.dart` | E19/E20/E14, fallos de disco/red controlados; no implica fallo físico ni Google real | **Bloqueado** para remoto por B02/B04; recuperación local en 253. Registrar historial/ganador de carrera sin exigir compare-and-swap condicional ausente del contrato. |
| R23 Windows instalado y actualizado · W | Contrato EP-028: usuario estándar/offline sin SDK/VS/CRT global, N→N+1 conserva datos/copias/estado/sesión; downgrade rechazado y uninstall conserva datos | EP-028 MA-TSK-229/230/232/233/235; `scripts/windows-delivery.mjs`; [plan E01–E12](../ep-028/plan-e2e-windows.md) | E16: fixtures/CI, **no entrega production**; toolchain productiva y cliente limpio pendientes | **Bloqueado** B04, 235 entrega evidencia obligatoria antes de 250/255. |
| R24 Android firmado y actualizado · A | Contrato EP-029: production, no debug, firma estable/hash/ABI/SDK; N→N+1 sin desinstalar, Keystore/sesión/datos; teléfono ARM64 y matriz 4/16 KB | EP-029 MA-TSK-238/239/241/242/243/245; `scripts/android-delivery.mjs`; [evidencia T07](../ep-029/evidencia-actualizacion.json) | E18: APK técnico no es final; EM release `APP_ENV=test` bloqueado al abrir almacenamiento. No teléfono acreditado | **Bloqueado** B02/B04/B05; resolver propietario de almacenamiento/243 y acreditar 245 antes de 251/255. |
| R25 Visual, accesibilidad y aceptación · W/A | EP-026 v1 y 217: resumen/detalle, 1440/1024/412/360/320 y texto 200 %, foco/Back/tacto, lectores/ajustes SO, estados de cinco vistas y flujos | EP-026 MA-TSK-207/208/217, EP-030 256; `lib/ui/autofinance_ui.dart`; `integration_test/redesign_validation_test.dart` | E14: capturas de RN con viewport forzado, **no HTML ni goldens**; partes antiguas; aprobación HTML 207 únicamente | **Pendiente** B06: capturas actuales completas, revisión humana/lectores físicos y aceptación visual 217, después aceptación de entrega 256. |

## Contraste de la revisión EP-026 con el producto actual

El informe E14 queda conservado como evidencia del **14 de octubre**, sin
reescribirlo como si hubiera probado el producto de hoy. En el código actual,
`AutofinanceApp` inyecta desde `LocalBackupSession` `annualActual`, `indicators`,
`diagnostics` y sus invalidaciones; `app_router.dart` abre `AnnualActualRoute`,
`IndicatorRoute` y `DiagnosticRoute`. EP-024 ya entrega filtros y listas.
E10–E13/E18 prueban partes de estos recorridos después de aquella revisión.
Por tanto, los marcadores de Real/Indicadores/diagnóstico y el backlog de filtros
de E14 **no son carencias funcionales actuales**. Sí sigue deshabilitada Openbank.

La consulta humana actual devuelve MA-TSK-207 `approvedAt=2026-10-12T14:56:25.247Z`
y la discusión «Propuesta visual aceptada: /mockups/autofinance-integral-v1.html».
MA-TSK-217 figura `done`, pero `approvedAt` y `discussion` están vacíos en la
respuesta consultada. Su informe declara que falta la aceptación final; no hay
evidencia humana posterior localizada en estas fuentes. No se interpreta el
estado administrativo ni la aprobación de 207 como aceptación de 217.

Quedan por acreditar con 217: capturas vigentes de las interfaces añadidas,
resumen/detalle y estados completos, cotejo humano contra el HTML de hash
`5f000e2db4ebac1c0678899c5f18ad2351e8aeedae202deb038cfe66158ed4f6`,
las diferencias de controles/alturas/densidad ya señaladas en E14, Narrador y
TalkBack, teclado/tacto/Back físicos, escala/contraste del SO y carga sostenida.
Los PNG antiguos son capturas de contenido Flutter RN con tamaños y MediaQuery
forzados; no incluyen selectores/teclado/marco SO. Esta auditoría no ha realizado
un nuevo cotejo visual de la app ni convertido esas imágenes en aceptación.

## Bloqueos y derivaciones concretas

No se cambia ningún ticket existente. Estas son entregas necesarias para que
sus propietarios y EP-030 continúen; las dependencias cruzadas se comprueban
manualmente, Epic Board no las ejecuta automáticamente.

| ID | Hallazgo / entrega necesaria | Propietario y siguiente consumidor |
|---|---|---|
| B01 | Sin muestra verificable, lector, adaptador ni fixtures Openbank; ruta deshabilitada. Entregar caracterización y recorrido real con hashes y protección de fotos | EP-014 124/125/126/129/130/**131** → EP-029 245 y EP-030 248/250/251. No desarrollar otro importador en EP-030. |
| B02 | `blocked_external`: proyecto/clientes nulos, API/tester falsos; scope público correcto `drive.file`. Completar mismo proyecto compatible y consentimiento de ensayo | Windows **249**; Android EP-029 **239** → 252/253. No registrar secretos ni usar sesiones personales. |
| B03 | Dependencias Drive consumidas pero no publicadas. Confirmar/subir solo sus fuentes por el propietario y verificar checkout limpio | EP-007 **064** → generadores EP-028/029 y candidato 255. T01 no incorpora archivos ajenos. |
| B04 | Faltan paquetes finales y evidencias efectivas 235/245. Windows: OAuth, VS2022/MSVC/CRT fijados y cliente limpio; Android: OAuth, conservación y teléfono. Conservar N/N+1 y copias recuperables | EP-028 **235**, EP-029 **245** → 250/251/252/253/254/255. Un APK técnico, runner o CI de fixtures no levanta el bloqueo. |
| B05 | Ensayo Android T07 rechaza alias `/data/user/0 → /data/data` como `invalidMetadata` antes de SQLite; 24/4 KB y 36/16 KB no acreditan N→N+1 | Contrato/almacenamiento EP-006/EP-004 con EP-029 **242/243**: aislar/corregir y repetir preservando validaciones; 245/251 consumen. Es evidencia existente, no reproducción nueva de T01. No relajar seguridad incidentalmente. |
| B06 | Falta aceptación visual humana actual y revisión física de accesibilidad; marcadores antiguos no representan la cobertura actual | EP-026 **217** → 255/256. Si exige interacción nueva, derivar suplemento a propietario y obtener aprobación antes de implementar. |
| I01 | Guion de bandeja busca el `PopupMenuButton<String>` eliminado de Real anual en `pending_lifecycle_journey.dart:144`; no alcanza las aserciones financieras | EP-015 **138**, coordinación EP-022/026; EP-030 253 puede corregir el guion de integración tras el contraste, usando navegación existente. No se acredita pérdida financiera por esta excepción de test. |
| I02 | Fallos de recuperación en las suites históricas de EP-028: timeout/restored frente a recoveryRequired. Contrastar aislado y referencia antes de atribuir causa | EP-006 **059**, coordinación EP-030 **253**. Preservar fallos generales históricos y pasadas actuales como resultados distintos; no aumentar timeouts ni alterar motor sin causa reproducible. |

## Condiciones obligatorias de cierre de EP-030

1. MA-TSK-248 entrega datos sintéticos y oráculos compartidos identificados por
   hash; variantes independientes D/G/H/J/K/L–O y archivos Openbank derivados
   de muestra caracterizada por su propietario. Una muestra ausente mantiene
   R02 bloqueada aunque se complete este inventario.
2. Evidencia efectiva **202, 217, 226, 235 y 245**, con sus límites resueltos para
   el candidato. 202/226 ya aportan recorridos verificables reutilizables; no
   convierten en verde la calidad global ni sustituyen paquete/físico/aceptación.
   Los cinco figuran `done` en el tablero; 217/235/245 conservan requisitos
   de cierre no acreditados. 131 aporta Openbank sin duplicación.
3. Paquetes privados finales W/A identificados por commit limpio, versión,
   configuración pública y SHA-256; mismo contenido del expediente y de las
   instalaciones. Instalar/actualizar en ensayos aislados, conservar originales,
   versiones N/N+1 y respaldos; no desinstalar ni tocar sesiones personales.
4. MA-TSK-250/251 registran cada R aplicable en PC/teléfono reales con fecha,
   modelo/SO/API/ABI/páginas, versión/hash, acciones, cifras/UUID, persistencia y
   origen de evidencia. H/RN/EM no se rotulan como P/F. Resolver y volver a
   comprobar fallos reproducibles de integración; carencias nuevas al propietario.
5. MA-TSK-249 y EP-029 239 acreditan OAuth real compatible; MA-TSK-252 ejecuta
   PC→Android→PC con cuenta de ensayo, solo botones y único archivo. MA-TSK-253
   acredita divergencias, incertidumbre, cancelación, red/archivo/respaldo/aplicación
   fallidos y recuperación con ambas versiones conservadas. La carrera aceptada
   del único archivo no se convierte en una exigencia de escritura condicional.
6. MA-TSK-254 contrasta exportación y copias de **ambas instalaciones finales**,
   consulta con SQLite estándar fuera de Flutter en carpetas nuevas, tablas,
   revisión/identidad/hashes/céntimos/orígenes y ausencia/parcial/cero/liquidez.
7. MA-TSK-255 consolida matriz con resultados finales y expediente sin secretos,
   calidad pertinente sin fallos sin resolver, paquetes privados y guías
   concordantes. Cualquier cambio de candidato invalida la evidencia afectada;
   volver a comprobarla. No publicar binarios privados, bases ni extractos.
8. **Aceptación explícita humana** MA-TSK-256 tras recorrer el expediente y los
   paquetes en ambos dispositivos, además de aceptación visual 217. Sin esto no
   se cierra EP-030. Documentar un bloqueo nunca satisface su criterio bloqueado.
   Confirmar/subir únicamente cambios propios a la rama configurada, sin force.

Preparación 247/248/249 independiente. Pruebas 250/251/254 requieren datos y sus
paquetes; 252/253 requieren además OAuth Windows y entregas remotas necesarias.
255 integra auditoría y todas las pruebas; 256 requiere 255. Son requisitos de
resultados, no una inferencia por numeración de tickets.

## Verificación de T01

La referencia de contraste es `68a87c138b7fa63240c2051fa9a78f340840efe7`,
commit del informe MA-TSK-233. Se extrajo con `git archive` a una carpeta nueva
ignorada `.tools/ma-tsk-247/reference`; no se cambia de rama ni se descartan
cambios concurrentes. Se añadieron **las mismas ocho fuentes Drive actuales**
a la referencia para compilar. Esto **no reconstruye el checkout histórico
original ni es una baseline pura**. Los hashes de ese overlay quedan en el JSON.

El contraste de **318 archivos** (todo `lib`, `test/support`, las dos suites,
`pubspec.yaml`, lockfile y toolchain) resulta idéntico tras normalizar CRLF→LF.
Tampoco hay diferencias versionadas entre referencia y HEAD en Windows, Linux
o assets. El único cambio versionado en `lib`/`test` desde esa referencia es
`test/android_upgrade_transport_test.dart`, ajeno a estas dos suites. Esta
comparación acota la atribución; no demuestra por sí sola corrección de datos,
equivalencia de ensayos nativos ni causa de los fallos antiguos.

La preparación de dependencias de la referencia resolvió el lockfile en modo
offline, pero Flutter devolvió error por no poder crear symlinks de plugins,
incluso con permisos de ejecución ampliados. Sin cambiar Developer Mode ni
preferencias globales, se prepararon junctions locales a los mismos dos plugins
ya instalados (`jni` y `path_provider_windows`). Su package_config apunta a la
propia referencia. Los ensayos posteriores usan `--no-pub` y salida propia.

Para reproducir las **dos ejecuciones dirigidas**, terminar primero cualquier
suite/build que pueda cargar SQLite. Ejecutar secuencialmente desde el checkout
auditado y desde la referencia preparada, con los mismos permisos nativos:

```powershell
flutter test --no-pub --concurrency=1 --reporter expanded `
  test/movements/pending_lifecycle_test.dart `
  test/synchronization/local_recovery_journey_test.dart
```

Son pruebas de **host Windows**, con variantes de widgets Windows/Android en
Pendientes; no prueban paquetes ni dispositivos. Conservan timeouts y
aserciones originales, y no modifican código de producto ni pruebas para
ocultar los fallos. La comparación controlada no reproduce toda la carga ni
el entorno de la suite general del 18 de octubre.

Resultados finales de calidad y contraste, hashes de logs locales y límites:
[evidencia-auditoria.json](evidencia-auditoria.json).

Comprobaciones de esta auditoría:

- `flutter --version` y `check-toolchain.ps1`: correctos. Lockfile, SDK,
  dependencias, esquema y código de producto/pruebas sin cambios propios.
- Primer `check-quality.ps1` en sandbox: falla al consultar advisories de
  pub.dev, error de red 10057; no alcanza análisis ni pruebas.
- Repetición autorizada del script original: resolución estricta correcta,
  **506 archivos sin cambios de formato**, análisis **sin incidencias**;
  suite completa **2.012 aprobadas / 2 fallidas, 13 min 06 s**. Fallan solo las
  variantes Windows/Android de `pending_lifecycle_test.dart`, `No element` en
  `pending_lifecycle_journey.dart:144`. Los ocho casos de recuperación pasan
  también en esta suite. **Calidad global no aprobada**; las cuatro variantes
  `APP_ENV` posteriores no se ejecutan porque el script se detiene. No se
  repite por rutina la suite ni se ocultan sus dos fallos.
- `node docs/ep-001/verificar-casos.mjs`: correcto, con las cifras de E01;
  hash del CSV contrastado. Los validadores públicos OAuth Windows/Android
  terminan con salida **1**, bloqueo esperado por configuración pendiente;
  no autorizan ni transfieren datos de Google.
- Comprobadas las 25 filas únicas, sus propietarios/estados, enlaces locales
  y rutas de código/pruebas citadas. No se añaden tests que dupliquen la tabla.
  Los scripts auxiliares y logs de auditoría permanecen ignorados en `.tools`;
  el resumen JSON conserva hashes y resultados sin publicar sus logs completos.
- Sin nuevos builds: solo cambian estos documentos. Un build aislado no aporta
  evidencia que levante los bloqueos del candidato. Sin ensayo de paquete
  production, dispositivo físico, Google real, lector Openbank, nueva captura
  visual o aceptación humana en T01. Se reutiliza la evidencia con esos límites.

| Suite dirigida, mismo comando y permisos | Candidato + overlay | Referencia 68a87c1 + mismo overlay |
|---|---|---|
| `pending_lifecycle_test.dart` | 0 aprobadas / 2 fallidas | 0 aprobadas / 2 fallidas |
| `local_recovery_journey_test.dart` | 8 aprobadas / 0 fallidas | 8 aprobadas / 0 fallidas |
| Resultado total / duración de tests | 8 aprobadas / 2 fallidas; 1 min 45 s | 8 aprobadas / 2 fallidas; 1 min 47 s |

**I01:** ambos árboles fallan en la misma búsqueda de menú, antes de categorizar.
El guion conserva la expectativa de navegación anterior a Real anual; la ruta
actual ofrece Gestión mediante la navegación EP-026. Es una incompatibilidad
reproducible del guion con la integración actual, ya presente en la referencia
preparada, no una regresión introducida entre estos dos puntos ni evidencia de
que se pierdan movimientos. E12 ya documentaba esta búsqueda obsoleta. Queda
derivada la actualización del recorrido, sin añadir un menú de producto para
satisfacer una prueba antigua ni rebajar las aserciones financieras.

**I02:** las dos incidencias señaladas por MA-TSK-233 y los otros seis escenarios
de recuperación pasan en ambos árboles, y los ocho también pasan en la suite
general actual. **No se reproduce aquí el fallo histórico**. Esto no prueba
que esté corregido ni identifica su causa: no se ha reconstruido la carga,
el overlay original ni todo el entorno del 18 de octubre. No se atribuye a
EP-028, EP-027, al motor de recuperación o al sandbox sin evidencia adicional.
MA-TSK-253 conserva la verificación de fallos/recuperación de los paquetes reales.

Los únicos archivos de entrega T01 son este informe y su JSON. La matriz es
completable aunque permanezcan B01–B06; sus criterios de producto siguen
pendientes/bloqueados. No se cierra ni se acepta EP-030 desde esta auditoría.

## Actualización T09 · 2026-10-21

Esta actualización conserva el inventario histórico anterior y lo contrasta con
las salidas T04–T08 publicadas. Referencias, fechas, commits documentales y hashes
están en [el expediente T09](expediente-entrega.md) y su
[evidencia estructurada](evidencia-entrega.json). Cada fila mantiene el contrato,
oráculo y propietario de la matriz original. **Ninguna fila acredita aún el
candidato final físico W/A**: faltan paquetes y hashes finales; versión fuente
0.1.0+1 no es versión instalada acreditada. No hay nuevas capturas T09.

T04–T08 datan del 2026-10-20. Host = pruebas automatizadas Windows, incluidas
disposiciones Android; runner/emulador se indican expresamente. Sus hashes y
commits permiten revisar los resultados sin atribuirles production o Google real.

| Criterio / plataforma | Resultado disponible y evidencia | Estado obligatorio del candidato / siguiente acción |
|---|---|---|
| R01 · W/A | [T02](verificacion-datos.md), [T04](verificacion-windows.md), [T05](verificacion-android.md): CSV exacto y flujo host; mismos oráculos | Bloqueado: ejecutar selector/importación/persistencia de ambos paquetes |
| R02 · W/A | [131](../ep-014/verificacion-reapertura-131.md), T04/T05: sin muestra/lector/fixture caracterizado | Bloqueado EP-014/131; no reemplazar por CSV |
| R03 · W/A | T04 corrige guion I01 y pasan dos variantes host con SQLite temporal | Bloqueado físico 250/251; I01 ya no es fallo vigente del guion |
| R04 · W/A | T04 incluye selección/lote, cancelación y procedencia tras corregir I01 | Bloqueado físico 250/251/253 |
| R05 · W/A | E02 y T04/T05 conservan cobertura existente y guion de edición/reapertura | Bloqueado en ambos paquetes |
| R06 · W/A | E01/E02, T04/T05: reglas y suites existentes, sin nuevo ensayo físico | Bloqueado: árbol/selectores/rollback sobre candidato |
| R07 · W/A | E03/E09, T04/T05: edición y restricciones host | Bloqueado: guardar/reabrir en ambos paquetes |
| R08 · W/A | E09/E18, T04/T05: anual implementado y comprobaciones host | Bloqueado: anual de ambos paquetes |
| R09 · W/A | E07, T04/T05: runner histórico Windows/emulador; propuesta/cancelación | Bloqueado: propuesta en candidato físico |
| R10 · W/A | E08/E14/E18, T04/T05: entrada/resumen/Estado, guion actual | Bloqueado: cifras y retorno físico |
| R11 · W/A | E10/E18, T04/T05: Real anual existente, no marcador | Bloqueado: matriz/tarjetas físicas |
| R12 · W/A | E06/E12, T04/T05: periodos existentes y retorno | Bloqueado: persistencia/periodos físicos |
| R13 · W/A | E12, T04/T05: filtros/desgloses existentes; runner histórico Windows/emulador | Bloqueado: filtros/retorno en paquetes |
| R14 · W/A | [T08](verificacion-portabilidad.md) y [T06](verificacion-drive-real.md): fallo de texto en test de foto tras guardar; fotos/datos de exportación histórica comprobados | Bloqueado: contrastar fallo EP-017/026 y verificar fotos físicas; no inferir pérdida financiera |
| R15 · W/A | E11/E18, T04/T05: indicador existente, runner histórico/emulador | Bloqueado: foto/ausencias/denominador físico |
| R16 · W/A | [202](../ep-025/verificacion-recorrido.md): 93 dirigidas y siete hitos runner Windows/emulador | Bloqueado: diagnóstico manual de ambos paquetes finales |
| R17 · W/A | T08: 57 dirigidas; relectura de 16 ZIP históricos Windows runner/emulador, no nuevas exportaciones nativas | Bloqueado: exportar y transferir desde finales |
| R18 · W/A | T08: cuatro SQLite históricas, 12 tablas y guía independiente; hashes conservados | Bloqueado: consulta de copias finales de ambas instalaciones |
| R19 · W/A | [T07](verificacion-fallos-recuperacion.md): 31 dirigidas, runner Windows debug 1/1; fallos de recuperación en suite general conservados | Bloqueado: resolver calidad EP-006/059 y recuperación/persistencia finales |
| R20 · W/A | [T03](oauth-windows.md), T06: configuración pública blocked_external; controles específicos salida 1 | Bloqueado: 249/239 y autorización Google real compatible |
| R21 · W/A | T06: 61 dirigidas host con proveedor/HTTP simulado; S00–S10 reales sin ejecutar | Bloqueado: Google real PC↔teléfono sobre hashes finales |
| R22 · W/A | T07/T06: fallos inyectados host y conservación; no Google real | Bloqueado: fallos/recuperación remotos de ambos paquetes, respetando carrera aceptada |
| R23 · W | [235](../ep-028/verificacion-e2e.md), T04: fixtures/CI sin candidato production | Bloqueado EP-028/235: instalar/actualizar en perfil aislado |
| R24 · A | [245](../ep-029/verificacion-final-245.md), T05: APK técnico no final; apertura/actualización 243 pendiente | Bloqueado EP-029/243/245: paquete/firma/teléfono/actualización |
| R25 · W/A | [217](../ep-026/validacion-integral.md): capturas runner parciales antiguas; consulta T09 sin approvedAt/discussion | Pendiente de aceptación visual humana 217 y accesibilidad física; después T10/256 |

Las pasadas dirigidas no anulan calidad global fallida. Resultados nuevos de
T09 se registran en el JSON/expediente, sin reescribir como actuales las pruebas
históricas. Todos los bloqueos siguen siendo criterios sin satisfacer, aunque
sus tickets propietarios figuren `done`. T09 y EP-030 no se cierran.
