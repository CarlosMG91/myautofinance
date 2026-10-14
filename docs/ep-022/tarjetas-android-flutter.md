# MA-TSK-177 · Tarjetas Android de Real anual

La composición Android reutiliza `AnnualActualScreen`, la consulta de MA-TSK-174,
los callbacks de MA-TSK-178 y el shell/periodo EP-016 ya entregados por la interfaz
Windows. `/real` mantiene el resumen anual y la gráfica de enero a diciembre;
`/real/detalle` presenta tarjetas, incluso en Android ancho. No hay otro motor
financiero ni un editor de importes.

## Referencias y comportamiento

Ticket y requisitos consultados en `GET http://localhost:4310/api/data`, tablero
**My autofinance**, el 2026-10-14. MA-TSK-174/175/178 y T05/MA-TSK-208 constan
completados. La aprobación específica de MA-TSK-175 tiene
`approvedAt=2026-10-14T19:21:34.462Z`; prevalece sobre el texto antiguo pendiente
del suplemento local. Se conservan el prototipo global EP-026 v1 aprobado,
EP-001 y los contratos de consulta/enlaces de esta épica.

La composición consume AfCard, AfValueRow, AfMoneyText, AfTimeChart, AfBarChart
y AfStatus desde `lib/ui/autofinance_ui.dart`. Windows conserva su matriz;
Windows estrecho o con texto grande reutiliza las tarjetas. No depende de
componentes pendientes de Presupuesto ni modifica sus archivos.

- Raíces inicialmente contraídas, expansión independiente de los tres niveles,
  ruta y nivel explícitos. Sin clasificar es el grupo con referencia nula.
- Total anual, mes enfocado destacado y doce meses desplegables por tarjeta,
  también en Total general. El mes enfocado no reduce la consulta anual.
- Importes y contadores de la misma consulta que PC: signos originales, todas
  las cuentas, archivo con histórico, meses vacíos cero y neto cero navegable.
- Los botones de expansión exponen su estado semántico y conservan foco. Las
  acciones usan los objetivos táctiles de 48 px del kit y permiten reflujo.
- Las cifras abren el año/mes y rama mediante la interfaz existente. Añadir usa
  el formulario EP-010 con el día 1 del mes enfocado. El retorno relee las cifras
  y conserva año, mes, ramas, doce meses abiertos, desplazamiento y foco.
- Android Back vuelve al origen con pila. En un enlace directo al detalle sin
  pila, `PopScope` reconstruye el resumen, igual que el botón Volver al resumen.
- Carga/error/reintento y descarte de resultados tardíos siguen siendo comunes
  a PC y Android; un error no se presenta como un año de ceros.

## Compatibilidad del origen

El filtro de presentación `meses` admite el token adicional `total-general`
para conservar el despliegue del total al volver o reconstruir un enlace.
No identifica una categoría ni se admite en `rama` o `abiertas`. Los UUID y
el token anterior `sin-clasificar` conservan su validación; se comprueban tanto
el recorrido completo de enlaces como el rechazo de usos fuera de `meses`.
No cambia las fórmulas, la consulta, SQLite, migraciones ni contratos EP-001.

## Verificación

Datos exclusivamente sintéticos, SQLite real en memoria. Las pruebas Android
recorren 320 px/texto 200 %, 412 px y 840 px: comparan cada cifra de las tarjetas
y los doce totales generales con la consulta, tres niveles, archivo, referencia
nula, ausencia, transferencia neta cero en dos cuentas, retorno con foco/scroll,
alta mediante el formulario existente y actualización al volver. Back se ejerce
mediante `handlePopRoute`, también desde un detalle sin pila. La prueba de años
tardíos/error/reintento se ejecuta para Windows y Android.

Los PNG de `test/actual_spending/goldens/` son **goldens del motor de pruebas
Flutter**, no capturas de Android instalado. Se actualizan detalle Android y
Windows estrecho/texto 200 %, y se añade Android a 320 px/texto 200 %. Resumen
Android, resumen Windows y matriz Windows conservan sus referencias. Inspección
visual realizada; estas pruebas no implican aprobación humana MA-TSK-217.

Comandos utilizados (Flutter 3.47.0 / Dart 3.13.0):

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile --offline
flutter test --no-pub test/actual_spending test/ui test/architecture_test.dart --concurrency=2
./scripts/check-quality.ps1
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
flutter drive -d emulator-5554 --no-pub --driver=test_driver/annual_actual.dart --target=integration_test/annual_actual_screen_test.dart --dart-define=APP_ENV=test
```

SDK y lockfile sin cambios. Windows release compila con Visual Studio Insiders
preinstalado; APK debug compila con JDK 17 y los paquetes Android fijados. La
configuración temporal del JDK se restaura después del build/recorrido.
Formato final: 421 archivos sin cambios; análisis final sin incidencias.
Las **68 pruebas dirigidas** de Real anual, kit y arquitectura pasan sin
regenerar goldens, junto a las cuatro variantes de arranque
development/test/production/invalid-synthetic. La copia aislada conserva el
mismo SHA-256 del archivo de pruebas final del checkout principal.

El intento de recorrido nativo Android API 37 no instala la aplicación: ADB
responde `Can't find service: package` en tres intentos. Back físico, TalkBack
y fidelidad en Android instalado quedan sin verificar; el build y los widgets
no sustituyen esa evidencia ni la aceptación visual independiente de EP-026.

El script de calidad original falla por acceso a pub.dev. Se repite con una
función local que añade `--offline` a pub get y limita las pruebas a dos procesos,
sin cambiar el script. La batería global termina con **1.216 correctas y 553
fallidas**, incluidas incidencias de recuperación/bases bloqueadas, y no se
declara correcta ni se atribuyen todos los fallos a otros tickets. Los cuatro
recorridos de presupuesto EP-011/021 se comparan en una copia de HEAD `4c387b2`
sin cambios de este ticket, con únicamente las fuentes concurrentes iniciales
de sincronización necesarias para compilar: fallan dentro del sandbox y pasan
los cuatro al ejecutar la misma copia con permisos ampliados. Esto identifica
una restricción de entorno para esos cuatro casos; no aísla los otros 549.
Las pruebas dirigidas finales se ejecutan
en una copia aislada del código para evitar la DLL SQLite ocupada por la suite
global; las fuentes y goldens son los de esta entrega.

Logs y copia de verificación en `.tools/ma-tsk-177-*`, ignorados. La entrega
excluye los cambios concurrentes iniciales de README, sincronización, fixtures
y prototipos. No se cambia el estado del tablero ni se cierra EP-022/EP-026.
La rama configurada de esta sesión es `ticket/ma-tsk-113`, con upstream
`origin/ticket/ma-tsk-113`; se utiliza esa rama sin cambiarla ni forzar la subida.
