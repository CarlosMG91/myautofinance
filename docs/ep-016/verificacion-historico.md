# MA-TSK-146 · Verificación de la navegación histórica

Ticket y épica consultados el 2026-10-09 en `GET http://localhost:4310/api/data`,
tablero **My autofinance**. Se conservan la rama configurada
`ticket/ma-tsk-113` y `origin`. Los cambios concurrentes de sincronización,
README y prototipos quedan fuera de esta entrega.

## Fuentes y alcance comprobado

Se reutilizan [periodo y sesión](periodo-sesion.md),
[controles aprobados](integracion-navegacion.md),
[histórico de vistas entregadas](historico-vistas.md),
[EP-002](../ep-002/entrega-flutter.md) y
[reglas financieras](../ep-001/especificacion.md), §§4–6.

El tablero marca MA-TSK-144/145 `done`, pero sus resultados indican que no
pudieron iniciar comandos y no hicieron entregas. En este checkout no hay
documentación ni fixtures de esos tickets. No se da por validada esa entrega:
MA-TSK-146 incorpora un dataset desechable y pruebas consumidoras de los
contratos **existentes** de MA-TSK-140/142/143. Esto permite verificar navegación
sin desarrollar los informes futuros ni trasladar lógica desde MyFinance.

`test/support/historical_navigation_fixture.dart` crea datos exclusivamente
sintéticos mediante los repositorios reales. El recorrido usa SQLite en archivo;
las pruebas consumidoras de contrato usan SQLite en memoria. Ninguna prueba
abre la base personal, importa archivos bancarios ni llama a Drive.

## Dataset reproducible y expectativas

Todos los importes de esta tabla están en céntimos. Las fichas cuenta/deuda
están vigentes desde diciembre de 2025 hasta febrero de 2026, ambos incluidos.
La cuenta conserva su liquidez histórica y aparece como cuenta cerrada al
consultar el histórico. Hay una raíz archivada con presupuesto/movimiento en
diciembre, una raíz activa Hogar y 18 raíces vacías para ejercitar scroll/foco.

| Periodo | REAL en repositorio/listado | Presupuesto mensual | Foto patrimonial |
| --- | --- | --- | --- |
| 2025-12 | −1.000, fecha civil 31/12, rama archivada | −20.000, archivado incluido | Cuenta 90.000 y deuda 10.000; neto 80.000 |
| 2026-01 | +30.000 el 01/01 y −5.000 el 15/01 sin categoría | Hogar explícito 0; otras ramas ausentes | Cuenta 70.000 y deuda ausente: incompleta, totales sin dato |
| 2026-02 | Vacío al sembrar | Hogar −12.300 | Cuenta y deuda explícitas 0: foto completa, neto 0 |
| 2026-03 | Vacío | Sin presupuesto | Ausente, sin fichas vigentes ni valores, sin dato |
| 1980-01 / 2035-01 | Vacío, subtotal 0 | Sin presupuesto | Ausente, sin dato |

El recorrido guarda después el movimiento de 30.000 en **2026-02-01** y una
partida explícita de cero en febrero para la última raíz vacía. Son dos
confirmaciones intencionadas; el incremento de revisión esperado es dos.
Antes de esos guardados, visitar histórico/futuro y cancelar borradores conserva
la revisión. Los meses no se preparan ni heredan fotos al consultarlos.

## Matriz de evidencia: vistas entregadas

`test/support/historical_navigation_journey.dart` se ejecuta desde
`test/historical_navigation_journey_test.dart` en widgets Windows/Android y desde
`integration_test/historical_navigation_test.dart` en los runners nativos.

| Criterio | Comprobación |
| --- | --- |
| Fecha Madrid y sesión nueva | 2025-12-31 23:30 UTC inicia enero; Mes actual con 2026-01-31 23:30 UTC elige febrero y conserva Patrimonio. Desmontar/montar inicia Estado/febrero sobre la misma base. |
| Cinco destinos y cruce de año | Diciembre/enero con anterior/siguiente; cambio entre cinco pestañas conserva periodo y no deja pila de destinos principales. |
| Histórico/futuro sin escrituras | Año directo 2035/1980; foto ausente, presupuesto ausente y listado vacío/subtotal cero; revisión intacta. |
| Foto exacta | Diciembre completo, enero incompleto, febrero cero completo y marzo ausente, sin arrastrar valores ni sumar fotos anuales. |
| Presupuesto ausente/cero | Enero muestra `0,00 € (registrado)`, marzo `Sin presupuesto`; diciembre incluye rama archivada. |
| Movimiento: cancelar/guardar/Ver mes | Rango de un día y filtro de concepto; Seguir editando conserva borrador, Descartar conserva selección. Guardar en febrero conserva origen de enero, invalida selección y ofrece Ver mes; pop recupera el mismo controlador/rango/filtro. |
| Partida: cancelar/guardar/Ver mes | Abrir última raíz tras scroll; cancelación protegida restaura scroll/foco. Guardar en febrero conserva enero; Ver mes abre febrero y pop recupera origen. Cambiar periodo reinicia posición/foco. |

Las regresiones de `test/historical_views_test.dart` comprueban además selección
y página obsoletas, lecturas tardías de Movimientos/Presupuesto/Patrimonio,
errores sin cifras previas, rangos locales, scroll/foco de fichas y movimientos.
`test/period_controls_test.dart` y `test/navigation_session_test.dart` cubren
memoria anual, año mensual que conserva mes, elección directa de mes, borrador
ante cambio de periodo/pestaña, teclado, 320 px/texto 200 %, límites civiles,
bisiesto/DST, guard cancelado/tardío, rutas inválidas y origen sin historial.
Esos fallos controlados y variantes se verifican en el host mediante widgets y
contratos; no se atribuyen automáticamente a la ejecución nativa del recorrido.

## Matriz separada: consumidores pendientes

`test/historical_navigation_contract_test.dart` verifica contratos y consultas
existentes, **no informes financieros**:

| Consumidor futuro | Contrato comprobado | Sigue pendiente |
| --- | --- | --- |
| Estado | Año/mes, intervalo mensual exclusivo, rama/alcance/filtro y origen con posición/foco; REAL vacío cero y presupuesto ausente distinto de partida cero | Vista y comparación real/previsto/diferencia |
| Real anual | Año enero–enero, mes enfocado independiente, links públicos a movimientos y origen seguro; memoria por año o enero | Matriz, agregaciones y totales del informe |
| Presupuesto anual | Contexto anual y memoria; consulta existente `readYear` devuelve partidas sin convertir ausencia en registro; retorno a contexto mensual | Matriz y navegación desde sus celdas; el destino implementado sigue siendo presupuesto **mensual** |
| Indicadores | Foto exacta del mes y consulta de ingresos presupuestados del mismo año; foto ausente/incompleta sin numerador, foto cero completa con numerador cero | Catálogo, cálculo del colchón, resultado y motivos del indicador |

Los marcadores Estado/Real/Indicadores reciben el periodo pero no presentan
euros inventados. En el contrato futuro, ausencia REAL aporta cero; ausencia
presupuestaria aporta cero aritmético con etiqueta sin presupuesto. El indicador
requiere foto completa y doce meses de ingresos registrados del mismo año;
las condiciones y orden de motivos siguen perteneciendo a EP-001 §6.1. No se
calcula un resultado a partir del dataset incompleto de esta verificación.

## Comandos y resultados locales

Los logs quedan en `.tools/ma-tsk-146-*.log`, ignorados. Los archivos SQLite
se crean en directorios temporales privados y se eliminan después de desmontar
la app y cerrar los repositorios. El script versionado de calidad no se cambia;
la ejecución selecciona concurrencia 1 mediante una función PowerShell local.

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
./scripts/check-quality.ps1
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
flutter drive -d windows --profile --no-pub --dart-define=APP_ENV=test --driver=test/support/historical_navigation_native_driver.dart --target=integration_test/historical_navigation_test.dart
flutter drive -d emulator-5554 --no-pub --dart-define=APP_ENV=test --driver=test/support/historical_navigation_native_driver.dart --target=integration_test/historical_navigation_test.dart
```

- `flutter --version`, `check-toolchain.ps1` y resolución con lockfile correctos:
  Flutter 3.47.0 / Dart 3.13.0, sin cambios en `pubspec.lock` ni `toolchain.json`.
- `scripts/check-quality.ps1` **correcto**, con pruebas secuenciales: 310
  archivos sin cambios de formato, análisis sin incidencias y **1.427 pruebas
  correctas**, incluidas las seis nuevas de MA-TSK-146. Arranque correcto además
  en development, test, production e invalid-synthetic (fallo seguro esperado).
  Log: `ma-tsk-146-quality.log`. La suite general tardó 22 minutos 19 segundos.
- Build Windows release correcto: `build/windows/x64/runner/Release/`.
- Build APK debug correcto con la configuración aislada JDK 17:
  `build/app/outputs/flutter-apk/app-debug.apk`.
- Recorrido nativo Android **correcto**, 80 segundos en el emulador API 37,
  usando el mismo guion completo que los widgets y SQLite real en archivo.
  Log: `ma-tsk-146-native-android.log`; build: `ma-tsk-146-build-android-jdk17.log`.
- Recorrido nativo Windows **correcto**, 46 segundos sobre el runner profile,
  con SQLite real en archivo; driver terminado con código 0 y `All tests passed`.
  Log: `ma-tsk-146-native-windows-final.log`. Windows advierte de plugin
  `integration_test` no detectado al cerrar; el driver recupera los resultados
  mediante VM Service. No se afirma captura mediante instrumentación nativa.
- `git diff --cached --check` correcto; siete archivos propios, sin SDK,
  caches, bases, logs ni binarios en el commit. Emulador creado para esta prueba
  cerrado tras finalizar Android; carpetas sintéticas eliminadas por el guion.

Estas verificaciones corresponden al checkout disponible, con los cambios
concurrentes identificados al inicio. El commit de MA-TSK-146 incluye solo sus
pruebas y este informe, no esos cambios concurrentes ni binarios generados.

## Límites del entorno

Flutter/Dart tienen las versiones fijadas 3.47.0/3.13.0 y el lockfile no se
actualiza. Doctor identifica el checkout Flutter como `[user-branch]` y Visual
Studio Community **2026 Insiders**, en vez de VS 2022. El primer runner Windows
debug falla en el enlazado CRT (`_calloc_dbg`, `_CrtDbgReportW`, LNK1120);
la verificación nativa usa profile, y el build requerido usa release.

Para Android se reutiliza el JDK local Temurin **17.0.20.1+1** mediante una
configuración Flutter aislada en `.tools/ma-tsk-146-flutter-config`, aplicada
solo al proceso. La configuración habitual con Java 25 permanece intacta.
Están instalados API 36, Build-Tools 36.0.0 y NDK 28.2.13676358. El emulador
disponible es **API 37**, ejecutado oculto; no se afirma prueba en dispositivo
físico ni emulador API 36. Doctor advierte de licencias Android pendientes.
Los builds locales no acreditan CI, firma de distribución ni OAuth/Drive real.
