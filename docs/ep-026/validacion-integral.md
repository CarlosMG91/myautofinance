# MA-TSK-217 · Validación integral del rediseño

Revisión del 2026-10-14 sobre el checkout compartido, rama configurada
`ticket/ma-tsk-113`. **La épica y el ticket no cumplen todavía todos los
criterios de cierre.** Faltan las interfaces propietarias EP-022–025 y la
aceptación visual final del usuario. No se sustituye una pantalla pendiente
con lógica del prototipo ni se considera un build prueba de integración.

## Referencia y baseline

Se consultaron MA-TSK-217, sus requisitos y EP-022–025 mediante
`GET http://localhost:4310/api/data`, tablero **My autofinance**.
T01–T13 figuran `done`. La salida de T01 / MA-TSK-204 explica que no pudo
inventariar el repositorio por fallo de terminal y no modificó archivos;
no existe una baseline entregada que pueda atribuirse a ese ticket.
Esta revisión recupera el catálogo de T02 y las pruebas existentes como
inventario comprobable, sin afirmar que T01 se ejecutó correctamente.

La discusión de T04 / MA-TSK-207 contiene la aceptación del usuario
«Propuesta visual aceptada: /mockups/autofinance-integral-v1.html».
Se reconciliaron el [registro](prototipo/aprobacion.md), el traspaso,
AGENTS y la referencia histórica EP-002. El HTML publicado y el local tienen
SHA-256 `5f000e2db4ebac1c0678899c5f18ad2351e8aeedae202deb038cfe66158ed4f6`.
El campo `approvedAt`, comprobado el 2026-10-14, registra
`2026-10-12T14:56:25.247Z`. La aprobación del HTML no es la aceptación final de la app.

## Inventario de cobertura y propietarios

| Entrada / recorrido | Implementación y pruebas reutilizadas | Estado de integración |
| --- | --- | --- |
| `/inicio` → `/estado` → registros → editar → retorno | `home_screen_test.dart`, `monthly_status_journey.dart` y nuevo `redesign_journey.dart`; SQLite y consultas reales | Nuevo recorrido integrado, con cifras/contexto/borrador/persistencia y comparación entre tamaños |
| `/presupuesto` → detalle, captura, propuesta → revisión/cancelación/guardado | Pruebas `test/budget`, `budget_proposal_acceptance_test.dart` nativo | Implementado por T08, conserva doce meses y ámbito de sustitución |
| `/patrimonio` → detalle/foto/fichas/intervalos | `test/wealth`, nuevo guardado de cero desde Inicio, `catalog_redesign_test.dart` existente | Implementado por T09/T12; foto día 1 independiente de movimientos |
| `/movimientos` → filtros, detalle, alta/edición/lote | `test/movements`, nuevo dataset 5.004 registros | Implementado por T10; EP-024 aún debe entregar sus filtros/retorno adicionales |
| CSV → revisión/confirmación/resultado/repetición/historial → pendientes | `import_redesign_test.dart`, `pending_categorization_test.dart`, suites importing/movements | Lectura y SQLite reales; selecciones y adaptadores de los guiones se identifican como sintéticos |
| Categorías y fichas → formulario/archivo/traslado/liquidez | `test/movements/category_*`, `test/accounts`, `test/wealth`, capturas T12 | Implementado por T12; se conserva propiedad y validación del árbol |
| Drive/copias → crear/cancelar/restaurar/recuperar | `synchronization_redesign_test.dart`, suites synchronization y recovery | Copia/restauración SQLite reales; respuestas Drive sintéticas, ninguna cuenta remota real |
| `/real` y registros anuales | EP-022 / MA-TSK-176, 177, 178; consulta MA-TSK-174 existente | **Bloqueado:** UI/enlaces sin entregar; la app muestra marcador |
| `/indicadores` | EP-023 / MA-TSK-183, 184, 186 | **Backlog:** entradas/cálculo/vista sin entregar; no se fabrica colchón ni valor disponible |
| Filtros y desgloses adicionales | EP-024 / MA-TSK-192 | **Backlog:** no se declara su integración completa |
| `/diagnostico` | EP-025 / MA-TSK-198, 201 | **Backlog:** aviso de interfaz pendiente; no ejecuta ni corrige datos |
| Openbank desde Gestión | Catálogo T02, entrada `/importaciones/openbank` | Acceso de producto aún deshabilitado; el motor y guiones existentes no acreditan ese selector conectado |

EP-014 figura administrativamente `done`, pero los resultados de MA-TSK-126,
130 y 131 declaran el bloqueo por falta de muestra verificable, lector y
adaptador Openbank. Se contrastó con
[`../ep-014/integracion-recorrido.md`](../ep-014/integracion-recorrido.md) y
el código actual: hay selector binario, pero no lector/adaptador bancario.
No se ha leído ningún extracto privado ni se fabrica un lector desde la
simulación HTML. El estado del tablero por sí solo no acredita esta entrega.

Las dependencias entre épicas son narrativas. Sus propietarios no dependen
de T14. No se cambia el tablero ni se marca otro ticket terminado por esta
revisión. Las capturas de marcadores hacen visible el bloqueo: no acreditan
fidelidad de Real/Indicadores ni ausencia de pantallas antiguas.

## Nuevo recorrido y protección financiera

La revisión nativa detectó y corrigió tres defectos de integración propios:

- El detalle de Estado conservaba tarjetas Material y colores azules/rojos
  anteriores a EP-026. Se sustituyen las tarjetas por `AfCard` y los colores
  de presupuesto, diferencia, cabecera, filas y bordes por `AfTokens`, con la
  alternativa de alto contraste del tema. No cambian cifras, claves, enlaces,
  consultas, árbol, validaciones ni persistencia.
- Android exige la ruta canónica de la instalación temporal para reutilizar
  el coordinador real de recuperación. El runner resuelve sus aliases y
  comprueba que la carpeta sigue dentro del ámbito sintético antes de usarla.
- El guion nativo de propuesta todavía tocaba categoría/Enero como en la
  interfaz anterior. En EP-026 ese paso abría un dropdown que tapaba Editar.
  Se usa la revisión mensual inicial y el tema de producto, conservando
  todas las aserciones de cancelación, desglose, sustitución y reapertura.
  El guardado espera su acuse visible de SQLite en lugar de depender de una
  espera fija de 300 ms; la condición tiene límite y conserva la aserción.

La suite completa también detectó una espera obsoleta en el recorrido de
patrimonio. El guion solo reconocía la barra de progreso anterior; ahora espera
los indicadores circulares, el estado tipado `AfStatusKind.loading` del kit y
la aparición del campo antes de escribir. Mantiene las verificaciones de las
fotos, liquidez, altas rechazadas, borradores, rollback y reapertura.

`test/support/redesign_journey.dart` se comparte entre pruebas de widgets y
el runner nativo. Crea una instalación temporal exclusiva, usa los repositorios
de producto y la fixture EP-001 `seedRecoveryReference`, y la elimina al acabar.
No abre la base personal ni compone OAuth. Las únicas modificaciones del
recorrido principal son guardar un Café de −10 a −9 EUR y guardar la foto
de Cuenta principal de 6.000 a 0 EUR, mediante sus formularios reales.

- Inicio comienza en enero 2026 con real +1.229,75 EUR, presupuesto
  +1.100,00 EUR, diferencia +129,75 EUR y foto neta 14.000 EUR.
- El detalle Ocio conserva los dos Café legítimos y subtotal −20 EUR.
  Back solicita resolver el borrador; «Seguir editando» conserva −9 EUR
  y no cambia la revisión SQLite. Guardar deja subtotal −19 EUR y real
  +1.230,75 EUR, sin modificar presupuestos ni foto.
- Volver conserva mes/año y la expansión de Alimentación. Guardar cero en
  la foto deja patrimonio neto 8.000 EUR y real +1.230,75 EUR. Las visitas a
  informes y gestión conservan la revisión posterior al guardado explícito.
- Febrero mantiene real +1.099,90 EUR y foto ausente «sin dato». No arrastra
  patrimonio de enero. Reabrir la instalación conserva los importes editados.
- El lote grande añade 5.000 reales alternos +1/−1 EUR en febrero: 5.004
  registros totales, subtotal +1.099,90 EUR. La pantalla recibe como máximo
  100 registros; no construye las 5.004 filas. Tab sigue operable. Los tiempos
  del runner incluyen las esperas del harness y no son un benchmark de SLA.

Los guiones financieros existentes ejercitan importación con normalización
única de signos, propuesta/sustitución/conflictos/concurrencia, categorización
individual/lote, reabrir y restaurar. No se añaden métodos financieros ni se
duplican cálculos. `node docs/ep-001/verificar-casos.mjs` confirma 48 partidas,
10 reales, real anual +2.329,65 EUR y presupuesto anual +13.200 EUR.

## Capturas y revisión visual

El runner `integration_test/redesign_validation_test.dart` conserva imágenes
PNG de `RenderRepaintBoundary` del motor de la app **ejecutándose nativamente**.
No son HTML, dibujos deducidos del código ni goldens del host. Son capturas
del contenido Flutter completo; no incluyen marco del SO, selector del sistema
o teclado. `setSurfaceSize` fuerza los viewports de referencia en el runner;
`MediaQuery` fuerza texto 200 % y reducción de movimiento. Esto no demuestra
un cambio de tamaño/escala en ajustes físicos del SO.

Windows: 1440×900, 1024×768, 320×800/texto 200 %. Android: 412×915,
360×800, 320×800/texto 200 %. El runner reutiliza los E2E nativos de
importación, categorización, propuesta y copias; luego ejecuta el recorrido
global en los tres tamaños de cada plataforma. El driver valida los nombres,
extrae bytes PNG y devuelve métricas de la ejecución. Ver
[`validacion-capturas/`](validacion-capturas/) y sus JSON por plataforma.

El driver exige 57 capturas del recorrido global y tres del CSV por plataforma,
comprueba los PNG y dimensiones, y registra SHA-256 y origen en manifiestos.
`node scripts/redesign-evidence.mjs` verifica los manifiestos y genera la
[`galería de revisión`](validacion-capturas/index.html); `--check` comprueba
que sigue siendo reproducible. Son 120 PNG en total. A 320 px/texto 200 % se
conserva el viewport original y otro desplazado al contenido para que los
controles de periodo/navegación no oculten la evidencia financiera. No se
modifica la escala ni se recorta la imagen para producir esta segunda captura.
La galería señala los
marcadores pendientes y no registra por sí sola aceptación visual.

Las pruebas del kit y de presentación comprueban tokens/contraste, cifras
firmadas/cero/ausencia, semántica y alternativa textual de gráficos, reducción
de movimiento, foco/teclado y reflujo. Back y las entradas de teclado/tacto
del guion se inyectan mediante el binding de pruebas en la app nativa.
TalkBack/Narrador, teclado físico, gesto predictivo Back, escala y alto
contraste desde ajustes del SO necesitan revisión manual adicional; no se
afirman verificados por inspección del código o por el resultado de un test.

### Cotejo visual de las pantallas disponibles

Se han inspeccionado muestras renderizadas del HTML aprobado y capturas de
Windows/Android de Inicio, Estado, presupuesto/detalle, patrimonio, movimientos
y formulario/borrador, con el kit y los tokens como referencia. Inicio conserva
la jerarquía resultado real/presupuesto/diferencia y la foto separada; Estado
queda con superficie blanca, previsto violeta y diferencias con los colores
normativos. Presupuesto mantiene el total +13.200 EUR y las 48 partidas en
detalle; Patrimonio muestra 8.000 EUR tras la acción explícita de guardar
cero, y Movimientos mantiene el subtotal de todo el ámbito con página de 100.
Los viewports desplazados a 320/200 % permiten leer contenido y cifras con
su escala original, además de conservar el viewport de navegación.

Existen diferencias visibles respecto al HTML: controles de periodo con
«Ir al periodo» y anterior/siguiente/actual, contexto en formato 2026-01,
acciones colocadas en otra fila, alturas de tarjetas distintas por sus textos
y navegación que refluye dentro del scroll al 200 %. El detalle completo es
más denso que el resumen. Estas diferencias y los marcadores pendientes se
presentan para revisión; no se declara coincidencia de píxeles ni fidelidad
final aceptada. El cotejo de las muestras no sustituye revisar todos los
estados, las interfaces faltantes y los lectores nativos.

## Comandos reproducibles

Usar Flutter/Dart y Android/JDK de `toolchain.json`, sin actualizar SDK,
paquetes o lockfile. La configuración de Flutter para estas comprobaciones
se mantiene en `.tools/217-flutter-config` mediante `APPDATA`, con JDK 17.
Windows usa profile para el runner por la limitación previa del enlace CRT
debug; la entrada de producto se compila release aparte.

Ejecutar calidad, runners nativos y builds en secuencia. La ejecución conjunta
de tests de host, Windows y el emulador produjo timeouts de recuperación y
retrasos del emulador; las comprobaciones posteriores se realizan sin esas
cargas simultáneas. No interpretar sus tiempos como un benchmark de producto.

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub test/redesign_integration_test.dart
./scripts/check-quality.ps1
node docs/ep-001/verificar-casos.mjs
node docs/ep-026/prototipo/generar.mjs --check
flutter drive --profile --no-pub -d windows --driver=test_driver/redesign_validation.dart --target=integration_test/redesign_validation_test.dart --dart-define=APP_ENV=test
flutter drive --debug --no-pub -d emulator-5554 --driver=test_driver/redesign_validation.dart --target=integration_test/redesign_validation_test.dart --dart-define=APP_ENV=test
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
node scripts/redesign-evidence.mjs --check
```

## Límites de entrega y condición de cierre

| Criterio de MA-TSK-217 | Alcance acreditado / pendiente |
| --- | --- |
| Capturas y fidelidad | Viewports de referencia y 320/200 %, navegación y contenido. Cotejo de las pantallas disponibles; faltan interfaces propietarias y revisión visual final completa. |
| EP-001 y persistencia | Fixture, consultas y SQLite existentes; referencias, signos, ausencia/cero, guardado explícito y reapertura. No se fabrica el indicador pendiente. |
| Recorridos y retorno | Inicio/Estado/edición/foto, propuesta, importación, categorización y copias reutilizados. Los recorridos de EP-022–025 requieren sus interfaces. |
| Sistema aprobado en informes pendientes | Pendiente EP-022/023/024/025; sus marcadores no se contabilizan como producto entregado. |
| Accesibilidad y carga | Kit, semántica/alternativas de gráficos, contraste, reducción de movimiento, foco y paginación de 100 sobre 5.004. Lectores y ajustes físicos del SO e interacción sostenida bajo carga requieren comprobación manual. |
| Calidad, builds y ejecución | Resultados concretos de los comandos en el apartado final; se distinguen runner nativo, entrada de producto y checkout compartido. |
| Revisión y aceptación | Guía/AGENTS/README/traspaso actualizados; aceptación visual final explícita pendiente. No se cierra ticket ni épica. |

El checkout inicial ya contiene cambios de README, servicios Drive/subida y
prototipos de otras épicas. Se recuperan y revisan los archivos previos propios
de T14 y se completa su entrega. Del README solo se confirma la actualización
de navegación/diseño/validación; el apartado concurrente de subida Drive queda
fuera del commit, junto con servicios y prototipos ajenos. La base versionada
importa `domain/drive_upload.dart`, pero ese contrato y la fábrica de subida
siguen sin confirmar entre los cambios de MA-TSK-064. Las verificaciones sobre
el checkout compartido no acreditan un checkout remoto limpio sin esa
dependencia previa; corresponde publicarla a su propietario.

Para cerrar: entregar EP-022/023/024/025, conectar los accesos pendientes,
repetir los recorridos de esas interfaces con sus cifras y fuentes, ampliar
la revisión visual de estados y lectores nativos, y obtener **aceptación visual
final explícita del usuario** sobre las capturas completas. Una aprobación
de T04 o un resultado verde de las pruebas no elimina estos requisitos.

## Resultado ejecutado · 2026-10-14

- Flutter 3.47.0 / Dart 3.13.0, verificador y resolución con
  `--enforce-lockfile`: correctos. El SDK local está en el tag 3.47.0 sin
  rama activa y reporta `[user-branch]`; no se modifica SDK ni lockfile.
  Android utiliza Temurin JDK 17.0.20.1 y los paquetes fijados en toolchain.
- Calidad final en secuencia: **1.740 pruebas** correctas, los cuatro
  arranques development/test/production/invalid-synthetic, 411 archivos sin
  cambios de formato y análisis sin incidencias. Formato final incluyendo
  drivers: **415 archivos** sin cambios; análisis final sin incidencias tras
  ajustar la espera del aviso temporal de guardado.
- Los intentos anteriores no se consideran verdes: la carga simultánea
  produjo dos fallos por timeout en recuperación; la siguiente suite superó
  recuperación y detectó la espera obsoleta de patrimonio. Sus dos variantes
  pasaron aisladamente y la suite final completa pasó después del ajuste.
  La propuesta Android expuso el dropdown antiguo y la espera de su aviso
  temporal; el recorrido final conserva y supera todas sus aserciones.
- Windows profile y Android debug: **ocho recorridos nativos por plataforma**
  correctos, más cierre del binding. Android se ejecutó en el emulador API 37;
  el APK se compila con API 36. Windows usa el compilador Visual Studio 2026
  Insiders disponible; no se afirma haber usado Visual Studio 2022.
- **120 PNG** exportados, manifiestos con hashes, tres escenarios reabiertos
  por plataforma y galería generada/comprobada con `--check`. El dataset
  grande mantiene 5.004 registros y una página de 100. Tiempos del harness:
  Windows 1.591 ms y Android 2.139 ms; no son un SLA ni una medida aislada de
  latencia de interacción. Las limitaciones físicas y visuales siguen vigentes.
- EP-001 y generación del HTML aprobado: verificadores correctos. Ningún
  cambio en reglas, fixture financiera, esquema, SDK o dependencias fijadas.
- Entrada principal Windows **release** y Android **APK debug**, `APP_ENV=test`:
  builds correctos en secuencia. Salidas locales:
  `build/windows/x64/runner/Release/` (EXE, DLL y data juntos) y
  `build/app/outputs/flutter-apk/app-debug.apk`. Los runners anteriores eran
  entradas de prueba; estos dos builds corresponden a `lib/main.dart`.

La entrega propia se confirma y sube a la rama configurada sin archivos
concurrentes ni force; el identificador y la comprobación remota constan en
la respuesta de entrega. Las pruebas y builds describen el checkout compartido:
la dependencia Drive pendiente de publicación impide acreditar un checkout
remoto limpio. **Este informe no declara MA-TSK-217 ni EP-026 completos.**
La revisión solicitada de la galería es parcial; no se ha recibido aceptación
visual final de la app completa.
