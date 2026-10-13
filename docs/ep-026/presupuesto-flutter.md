# MA-TSK-211 · Presupuesto y propuesta anual

La entrada de Presupuesto muestra resultado anual, ingresos presupuestados,
mes enfocado y secciones por categoría. «Ver detalle» abre los doce meses y el
total; Windows conserva cabecera/categoría fijas y scroll dentro de la matriz.
Las celdas usan la tipografía compacta del kit para mantener cifras y etiquetas
completas. En la propuesta, enfocar una celda revela su columna y Enter abre
el mes, evitando que la etiqueta fija cubra el foco.
Android conserva tarjetas, meses desplegables y acceso al formulario. Back o
Escape desde el detalle devuelve al resumen; un borrador modificado exige
descartarlo expresamente. El foco vuelve al botón de detalle.

## Fuentes y autorización

Se utiliza el ticket completo aportado por el usuario, que pide implementar
MA-TSK-211 y declara completado MA-TSK-208. Epic Board no tiene herramienta
disponible en esta sesión; no se cambia el estado del tablero. Se han consultado
EP-001, el prototipo v1 conservado, su captura renderizada y el contrato del kit.
La evidencia local de T04 todavía dice pendiente: esta entrega no inventa una
aprobación humana ni modifica ese registro. La conciliación corresponde a su
propietario, como indica la entrega de T05.

## Implementación y contratos conservados

- `AnnualBudgetSummary` proyecta el mismo `AnnualBudget` que la matriz. Las
  secciones muestran raíces, incluidos históricos archivados; ingresos usa la
  marca categorial, nunca el signo. El resultado y los contadores vienen de la
  consulta anual. La suma de ingresos usa BigInt para no truncar un subtotal.
  El gráfico presenta las cifras firmadas del mes enfocado, sin generar cifras
  reales ni saldos. Ausencia y partida cero siguen siendo estados distintos.
- Se conservan los puertos y enlaces de EP-021/024, edición por celda Windows,
  formularios móvil/mensual, confirmación de borrado, conflictos de rama,
  identidad de la base, metadatos, invalidación y relectura tras retorno. No se
  modifican consultas, validaciones, SQLite, motores ni Drive.
- El contexto distingue resumen y detalle al reconstruir el origen. Los tokens
  existentes de foco/scroll siguen admitidos; `detail|` conserva el detalle al
  retornar desde captura o propuesta. No se cambia el parser de navegación.
- La propuesta de EP-018 muestra real de origen y borrador en tarjetas con
  estilos distintos. Un selector permite revisar cada mes equivalente y editar
  o desglosar sus partidas. El detalle anual contiene enero–diciembre/total en
  PC y totales mensuales accionables en Android. La selección de un mes no
  guarda ni regenera el borrador. Las ediciones actualizan resumen y detalle.
- «Revisar y guardar» mantiene la comparación completa de partidas anteriores
  y nuevas, sustitución de ámbitos, confirmación expresa, cancelación y errores
  de concurrencia. Los avisos de signos, reales excluidos, redondeo de magnitud
  a decena y revisión obligatoria siguen en sus propietarios. Cada partida
  conserva sus céntimos exactos al guardar.
- Se usan tarjetas, filas, selector, gráfico, tokens e iconos originales de
  T05. La matriz presupuestaria conserva sus controladores para restaurar
  scroll/foco. El diálogo de comparación usa los tokens sin un LayoutBuilder
  interno, porque AlertDialog mide dimensiones intrínsecas. No cambia el kit.

## Verificación reproducible

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
./scripts/check-quality.ps1
node docs/ep-001/verificar-casos.mjs
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

`test/budget/budget_redesign_test.dart` usa SQLite en memoria, el router real,
tema/fuentes locales y los datos sintéticos de EP-001. Comprueba entrada por
resumen, +13.200,00 anual, 48 UUID/importes intactos, cambio de detalle, Enter,
Escape, Back, relectura, Android 320/840 con texto 200 %, captura mensual y
propuesta de febrero desde −420,10 a −430,00, edición a −440,00 y cancelación sin
escrituras. Las regresiones existentes conservan conflictos, ceros, ausencia,
desglose, eliminación, rollback, sustitución, retorno y persistencia en archivo.
La propuesta también se prueba con el tema real en Android 320/200 %, marzo
sin reales, una salida positiva que exige revisión de signo y Back del diálogo.

Para regenerar las capturas de revisión del motor Flutter:

```powershell
$env:BUDGET_REDESIGN_CAPTURE='1'
# FLUTTER_ROOT opcional; el SDK local está en .tools/flutter.
flutter test --no-pub test/budget/budget_redesign_test.dart
```

Las imágenes de `presupuesto-capturas/` son capturas reales del renderizado de
estos widgets y sus recorridos sintéticos; no son capturas de aplicaciones
instaladas. Se revisan visualmente cifras, reflujo, jerarquía, controles y detalle.
Las capturas nativas, lectores de pantalla y recorridos integrados de las cinco
vistas siguen perteneciendo a T14. No se afirma haber realizado esa integración.

Los cambios concurrentes de README, backend Drive y prototipos de otras épicas
quedan fuera del commit. La rama configurada es `ticket/ma-tsk-113`; solo se
confirman y suben los archivos propios de este ticket. Las pruebas completas
usan el estado compartido del checkout; la entrega del backend pendiente
corresponde a su propietario.

## Resultado · 2026-10-13

- Flutter 3.47.0 / Dart 3.13.0 y resolución `--enforce-lockfile`: correctos.
  SDK, dependencias y lockfile permanecen fijados.
- `./scripts/check-quality.ps1`: correcto; 394 archivos sin cambios de formato,
  análisis sin incidencias, **1.699 pruebas** y los cuatro arranques adicionales.
  Pasan los dos recorridos presupuestarios con SQLite en archivo, incluidos
  confirmación/sustitución de propuesta, rollback, reapertura y retorno anual.
- Tras el último ajuste de tipografía se repitieron **35 comprobaciones** de
  presupuesto anual, Android y rediseño; todas correctas. Formato del módulo
  también correcto. Se mantienen +13.200,00 anual, doce +1.100,00 y 48 registros
  originales con los mismos UUID e importes.
- `node docs/ep-001/verificar-casos.mjs`: correcto; los casos originales y los
  signos de salario/impuestos siguen vigentes.
- Windows release y APK debug del código final, `APP_ENV=test`: correctos.
  Android utiliza Temurin JDK 17.0.20.1 con configuración Flutter aislada en
  `.tools/ma-tsk-211-flutter-config`, sin alterar preferencias globales.
- Doce imágenes revisadas del motor Flutter: PC, Android 320/840 al 200 %,
  resumen, detalle, captura mensual, propuesta y comparación. Se corrigieron
  cifras partidas al ampliar texto y etiquetas cortadas dentro de las celdas.
  No se realizaron capturas de aplicaciones instaladas ni pruebas de lectores
  de pantalla nativos; permanecen para T14.

Las restricciones iniciales del sandbox impidieron abrir algunas bases
temporales y utilizar cachés de compilación. Las ejecuciones autorizadas fuera
del sandbox completaron las verificaciones; no queda un bloqueo de permisos.
Git remoto se comprobó con una excepción de propiedad limitada al comando y
este repositorio, sin cambiar la configuración global.
