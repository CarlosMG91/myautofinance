# MA-TSK-214 · Selección, revisión e historial de importaciones

Entrega de presentación para CSV histórico y para la revisión común de lotes.
Se reutilizan controlador, lector, adaptación, validación, confirmación atómica
y consultas SQLite existentes. No hay cambios en parser, modelo de lote,
esquema, huella SHA-256, deduplicación ni normalización presupuestaria.

## Diseño y autorización

Se consultó `GET http://localhost:4310/api/data`, tablero **My autofinance**,
workspace coincidente, MA-TSK-214 y sus requisitos. MA-TSK-208 figura completado.
MA-TSK-207 contiene aprobación explícita: «Propuesta visual aceptada:
/mockups/autofinance-integral-v1.html», registrada en `approvedAt` el
2026-10-12 a las 14:56:25 UTC. Los documentos locales del prototipo todavía
dicen pendiente; se usa la evidencia posterior del tablero sin modificar
documentos ajenos ni las reglas de EP-001.

Se contrastaron el prototipo conservado, su captura de revisión, los tokens,
el contrato de shell y la API pública del kit MA-TSK-208. La implementación
usa `AfPageLayout`, tarjetas, tonos REAL/PRESUPUESTO, filas, acciones, estados
y campos de formulario. La secuencia visible concreta selección, revisión,
asignación, confirmación y resultado; la tabla completa se abre bajo demanda.
Windows ofrece tablas compactas; Android y texto ampliado refluyen a tarjetas.

## Comportamiento y criterios

| Criterio | Implementación y verificación |
| --- | --- |
| Original, normalizado, cuentas y referencias | Resumen separado por REAL/PRESUPUESTO con conteos y totales firmados. Asignaciones originales/destino visibles; detalle de filas paginado con ambos importes y consulta de campos originales. Diálogo con referencia original, campos del kit y ayuda persistente. |
| Cuenta y categoría | Se mantiene `canConfirm` del controlador. Cuentas requeridas; presupuestos necesitan categoría; reales sin categoría conservan Sin clasificar y acceso a pendientes del lote. Las nuevas referencias son planes en memoria hasta confirmar. |
| Errores completos | Todos los diagnósticos, incluidos los de confirmación, aparecen fuera del detalle colapsable con ordinal, campo y motivo. Archivo inválido no muestra totales parciales. Confirmación deshabilitada y motivo visible. |
| Conflictos y solapamientos | Validaciones originales sin cambios. Se comparan fila entrante y registro existente; cada solapamiento requiere aceptación explícita. No se eliminan filas por parecido. |
| Atomicidad y repetición | Confirmar llama al servicio existente, que revalida estado, referencias y huella. Repetición exacta muestra cero altas. Pruebas del núcleo cubren rollback y conservación de dos filas idénticas. |
| Cancelación y retorno | Descartar pide confirmación y elimina únicamente decisiones en memoria. Cancelar selector o confirmación no persiste lote/intento. Escape, Back, salida y sustitución conservan sus guards. Historial y enlaces mantienen la sesión y la procedencia por IDs. |
| Historial | Consulta solo lotes confirmados mediante el repositorio existente. Archivo/origen, fecha local y conteos por tipo en lista; huella/versiones/identidad en detalle. Original y registro actual corregido/borrado permanecen distinguibles. Sin nueva retención de archivos. |
| Accesibilidad y estados | Pasos con selección semántica, títulos, avisos vivos, foco existente, carga/vacío/error y reintento. Reflujo de 1440 a 320 con texto 200 %. Pruebas de objetivos táctiles y acciones rotuladas, teclado y cancelación. |

## Bloqueo preexistente de Openbank

El selector binario Windows/Android está entregado, pero no hay lector,
caracterización ni adaptador Openbank. MA-TSK-124/125/126/130 figuran `done`
en el tablero y sus resultados documentan expresamente estas piezas pendientes.
La evidencia y el punto de conexión están en
[`../ep-014/integracion-recorrido.md`](../ep-014/integracion-recorrido.md).
Los adjuntos de MA-TSK-214 y de la épica están vacíos. No se ha leído una
muestra privada ni acreditado un formato bancario no disponible.

Se conserva la entrada Openbank deshabilitada con motivo explícito. La UI
común admite lotes `bankXls` y sus pruebas sintéticas verifican revisión y
protección de fotos; no se conecta ese doble al producto. Activar e importar
Openbank sigue bloqueado por las entregas de EP-014 y no permite declarar
cumplidos todos los criterios de MA-TSK-214.

## Evidencia reproducible

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
./scripts/check-quality.ps1
flutter test --no-pub --concurrency=2 test/importing test/navigation_test.dart test/historical_navigation_contract_test.dart test/architecture_test.dart
node docs/ep-001/verificar-casos.mjs
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
flutter drive --no-pub -d windows --driver=test_driver/import_redesign.dart --target=integration_test/import_redesign_test.dart --dart-define=APP_ENV=test
flutter drive --no-pub -d emulator-5554 --driver=test_driver/import_redesign.dart --target=integration_test/import_redesign_test.dart --dart-define=APP_ENV=test
```

`test/importing/import_redesign_test.dart` genera las imágenes de
`importaciones-capturas` con `IMPORT_REDESIGN_CAPTURE=1`. Las imágenes con
prefijos `windows`, `android` y `texto-200` son renderizados de widgets Flutter,
no capturas de una instalación Android. El test nativo crea un CSV sintético
en soporte temporal y usa el lector/parser reales y SQLite en memoria sin
abrir datos personales. Por defecto sustituye solo el selector de documento;
`IMPORT_NATIVE_SELECTOR=true` permite revisar manualmente el diálogo nativo.
Las capturas `native-*` proceden del recorrido en la aplicación nativa.

El driver exporta las tres capturas mediante `reportData` antes de que Flutter
limpie la instalación de prueba. No se depende de que siga instalado el APK
para recuperar las imágenes. Se espera al repintado tras desplazar la página.
El cierre global y los recorridos integrados de toda la épica permanecen en
MA-TSK-217.

## Resultado · 2026-10-13

- Flutter 3.47.0 / Dart 3.13.0: verificador correcto y resolución con
  `--enforce-lockfile` correcta. SDK, dependencias y lockfile sin cambios.
- `scripts/check-quality.ps1`: correcto, **1.733 pruebas** y cuatro arranques
  de entorno. Tras los últimos ajustes de asignación y capturas: batería
  dirigida **288 comprobaciones**; prueba visual final **9 casos**; análisis
  final sin incidencias y formato sin cambios.
- EP-001: verificador de casos correcto; signos, conteos y cifras financieras
  conservados. Pruebas SQLite de atomicidad, conflicto, originales,
  duplicados, repetición, historial y protección patrimonial correctas.
- Windows release y APK debug de la entrada principal con APP_ENV=test:
  correctos. Android usa el JDK 17 fijado en configuración local aislada.
  El host Windows tiene Visual Studio 2026 Insiders; no se afirma haber usado
  Visual Studio 2022 ni haber cambiado la configuración global.
- Recorrido nativo Windows correcto con selector sustituido, lectura de CSV
  real y SQLite en memoria. Recorrido nativo Android correcto en el emulador
  API 37, incluido el **selector SAF real** y dos selecciones del mismo CSV
  sintético, confirmación cancelada sin escritura y repetición con cero altas.
  Se verificó también la exportación automática de capturas en ambas plataformas.
- Capturas de widgets a 1440/360/320 y texto 100/200 %, y capturas nativas
  Windows/Android conservadas. Se inspeccionaron resumen, resultado, historial,
  errores al 200 % y selector Android contra el prototipo y el kit: cifras,
  acciones y mensajes refluyen sin overflow; la tabla completa mantiene
  desplazamiento horizontal propio. Las capturas son del viewport desplazable.
- El sandbox impedía abrir algunas bases temporales. La ejecución autorizada
  las verifica. La compilación de prueba Windows también encontró contención
  sobre `sqlite3.dll` con tests simultáneos; ejecutar esos comandos en secuencia
  resolvió el problema. El primer exportador de capturas se corrigió y volvió
  a verificar antes de la entrega.

**Límites:** Openbank productivo sigue bloqueado por EP-014. No se acreditan
TalkBack/Narrador ni selección interactiva Windows: el diálogo nativo se abrió,
pero la herramienta de control Windows rechazó la interacción con su modal.
Las pruebas del canal y los builds no sustituyen esa comprobación manual.

Cambios de MA-TSK-214 recuperados de su ejecución anterior, revisados y
completados en la rama configurada `ticket/ma-tsk-113`. Se excluyen README,
Drive, prototipos y demás cambios ajenos del checkout. No se marca terminado
el ticket ni se cierra la épica mientras falte Openbank.
