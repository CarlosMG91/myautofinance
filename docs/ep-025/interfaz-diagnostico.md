# MA-TSK-201 · Diagnóstico manual en Flutter

## Referencia y aprobación

Ticket y épica consultados mediante `GET http://localhost:4310/api/data` el
2026-10-16, tablero **My autofinance**. MA-TSK-198 y MA-TSK-199 están
completados. El registro de T03 contiene `approvedAt =
2026-10-16T11:11:00.523Z` y la intervención de «Tú»:

> Propuesta visual aceptada: http://localhost:4310/mockups/autofinance-ma-tsk-199-v1.html

Esta aprobación y la petición actual autorizan implementar la interfaz. El
README conservado del prototipo todavía dice «pendiente»; no se modifica el
artefacto aprobado ni se simula una nueva aprobación. Su SHA-256 es
`2a1e89e05a40dc1ae6a216832ac703ad0003c90a78c349d916e7ae84b18f80c5`.
La apariencia global sigue siendo EP-026 v1 y su kit T05.

## Composición y comportamiento

`AutofinanceApp` y `LocalBackupSession` inyectan el ejecutor T02 existente,
su comprobador de referencias y la invalidación compartida. Construir la
aplicación o visitar la pantalla no ejecuta reglas. Solo «Ejecutar diagnóstico»
y «Repetir diagnóstico» llaman a `DiagnosticExecutor.execute`.

La entrada existente está en Análisis/Más y Gestión. `DiagnosticRoute`
reutiliza `PrimaryNavigation`, `NavigationSession` y el periodo mensual común.
La selección mensual sustituye al marcador anual anterior de esta ruta;
no cambia el periodo de los registros históricos encontrados.

La presentación usa `lib/ui/autofinance_ui.dart`: tarjetas de resumen por
severidad, filtros, grupos de hallazgos, detalle desplegable y cobertura de
las nueve reglas. Las cifras proceden de las evidencias del motor y se
formatean con `AfAmount`, sin conversiones de signo ni nuevas fórmulas.
El resumen muestra fecha, ámbito, mes, dataset, revisión y generación.

Se distinguen listo para revisar, carga/cancelación, fallo de lectura,
cambio durante lectura, sin hallazgos, revisión incompleta y resultado
obsoleto. Una regla no ejecutada conserva su motivo en la cobertura y nunca
se cuenta como conforme. Los filtros mantienen los recuentos de la ejecución.

El controlador solo vive durante la visita. Al cambiar mes conserva el
resultado anterior como obsoleto y cancela una lectura pendiente. Al volver
de un origen, reanudar la app o recibir una invalidación consulta únicamente
el marcador de vigencia, sin volver a ejecutar reglas. Ocultar la aplicación
cancela la ejecución en curso al terminar su sentencia pendiente. Una respuesta
tardía de una referencia tampoco pisa un nuevo periodo de navegación.
Una notificación de
copias sin cambio de datos no invalida por sí sola el informe. Sustituir la
conexión al restaurar sí lo invalida aunque dataset y revisión coincidan.
Filtro, expansión, scroll y foco permanecen al volver por la pila existente.

## Destinos

| Evidencia/acción | Destino existente |
| --- | --- |
| Integridad o fallo de lectura | Recuperación y copias locales |
| Referencia inexistente | Catálogo de categorías, fichas, movimientos, partidas o importaciones, según entidad; nunca el ID ausente |
| Padre/descendiente presupuestados | Cada partida por UUID y su mes histórico |
| Importación repetida | Cada lote por UUID |
| Coincidencia entre lotes | Ambos lotes, procedencias por `importRowId` y movimientos por UUID/fecha; se conservan ordinales e importes |
| Movimiento sin categoría | Bandeja EP-015; si es manual se ofrece además su editor, porque la bandeja propietaria lista importados |
| Foto ausente/incompleta | Foto del mes elegido y fichas pendientes por UUID |
| Indicador sin dato | Foto o captura de presupuesto; si hay meses de ingresos pendientes, cada mes tiene enlace y la acción principal abre el primero |

Antes de abrir una identidad se verifica su existencia sobre la conexión
activa. Si desapareció, se informa y abre su catálogo. Si la comprobación
falla, se conserva el diagnóstico y se ofrece Recuperación local.
El diagnóstico no escribe al ejecutar, filtrar o abrir resultados. No añade
historial, exportación, esquema, reparaciones, fusión ni servicios financieros.

## Evidencia y reproducción

Las pruebas usan exclusivamente fixtures sintéticas y SQLite temporal.
`test/support/diagnostic_journey.dart` compara **todas las tablas** y revisión
antes/después de diagnosticar, abrir la bandeja, volver y abrir fotos sin
guardar. Crea/restaura una copia real en su directorio privado y comprueba
que la nueva generación invalida el informe. Reiniciar la visita elimina el
resultado. No se abren archivos ni bases personales.

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub test/diagnostics test/architecture_test.dart --concurrency=1
./scripts/check-quality.ps1
flutter drive --debug --no-pub -d windows --target=integration_test/diagnostic_screen_test.dart --driver=test_driver/diagnostics.dart --dart-define=APP_ENV=test --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false
flutter drive --debug --no-pub -d emulator-5554 --target=integration_test/diagnostic_screen_test.dart --driver=test_driver/diagnostics.dart --dart-define=APP_ENV=test --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
node docs/ep-001/verificar-casos.mjs
```

Los diez PNG de [flutter-capturas](flutter-capturas) proceden del
`RenderRepaintBoundary` de los runners **nativos Flutter**, con superficies
de prueba 1440×1100 Windows y 412×1100 Android. Los JSON de origen indican
plataforma, fecha y datos sintéticos. Se han inspeccionado contra las capturas
HTML de T03; no son capturas del HTML ni goldens de widgets. Conservan inicio,
resultado, detalle, obsoleto y foto pendiente. Android se verifica en emulador
API 37; el proyecto compila con SDK/Build-Tools 36 del toolchain.

Los tamaños 320/412/1440 y el texto 200 % se comprueban adicionalmente en
widgets. El Back del recorrido se invoca mediante el binding Flutter;
no se acredita un botón físico Android, TalkBack/Narrador ni dispositivo
físico. Esta evidencia no sustituye la aceptación visual humana independiente
de MA-TSK-202/217 ni cierra otras épicas.

## Resultado de verificación y entrega

- Flutter 3.47.0 / Dart 3.13.0, `check-toolchain.ps1` y resolución con
  `--enforce-lockfile`: correctos. SDK, versiones y lockfile permanecen intactos.
- Formato completo, incluidos `test_driver`, sin cambios; análisis estático
  completo sin incidencias. `git diff --check` correcto.
- Diagnóstico/arquitectura, recuperación y patrimonio ejecutados secuencialmente:
  **71 pruebas correctas** en 5 min 31 s: 61 de diagnóstico/arquitectura,
  ocho de recuperación y dos recorridos patrimoniales Windows/Android.
  Las 11 pruebas nuevas del ticket están en `diagnostic_screen_test.dart`
  (interfaz) y `diagnostic_journey_test.dart` (recorrido).
- Se repiten las **nueve pruebas de interfaz** después de los últimos ajustes
  de navegación tardía y cancelación al pasar a segundo plano. Cubren también
  marzo pendiente frente a octubre seleccionado, errores de referencia,
  cancelación, regla no ejecutada y la conservación del contexto.
- Recorrido nativo Windows y Android: correcto en ambos runners, con diez PNG
  conservados e inspeccionados. Entrada secundaria manual, retorno desde
  bandeja, restauración real obsoleta, repetición, cambio de mes, foto y ausencia
  de historial comprobados sobre SQLite sintético.
- Windows release y APK debug de la entrada principal con `APP_ENV=test`:
  correctos. Windows usa Visual Studio 2026 Insiders preinstalado; no se afirma
  un build local con VS 2022. Android usa Temurin JDK 17.0.20.1 con configuración
  Flutter aislada en `.tools`, sin cambiar ajustes globales. No hay firma de
  distribución.
- Las cuatro variantes de arranque `development`, `test`, `production` e
  `invalid-synthetic` se verifican por separado. El comprobador sintético
  EP-001 conserva 48 presupuestos, diez reales y todas sus referencias.

`scripts/check-quality.ps1` **no queda verde**: formato y análisis pasan, pero
la batería general termina en 14 min 15 s con **1.957 pruebas correctas y cuatro
fallos**. Dos corresponden a `pending_lifecycle_test.dart`, Windows/Android,
por `Bad state: No element` en el recorrido EP-015: son los fallos previos
documentados por [T01](contrato-diagnostico.md) y [T02](ejecutor-diagnostico.md).
Los otros afectan al primer recorrido de `local_recovery_journey_test.dart`
(timeout de 30 s) y al recorrido Windows de `wealth_lifecycle_test.dart`
(«La operación patrimonial SQLite no terminó»). Estos dos **no se reproducen**
en la ejecución aislada de los diez casos de recuperación/patrimonio incluida
en las 71 pruebas anteriores. No se cambian sus fuentes, pruebas ni timeouts.
El resultado fallido del script general se conserva; la repetición aislada
no lo convierte en correcto.

Los controles finales se ejecutan secuencialmente: durante las comprobaciones
paralelas de este host se observó un bloqueo de `sqlite3.dll` al compartir
artefactos entre procesos Flutter. Se repitieron los controles dirigidos con
salidas locales aisladas. Los logs y builds locales quedan en `.tools`/`build`,
fuera del repositorio; solo se entregan evidencias sintéticas.

Se incluyen exclusivamente los 26 archivos propios de MA-TSK-201 en la rama
configurada `ticket/ma-tsk-193`. README, sincronización y los prototipos
concurrentes encontrados al iniciar quedan fuera. El remoto consultado
coincide con el punto de partida `6d82c06`; no se fuerza la subida ni se cambia
el estado administrativo del tablero.
