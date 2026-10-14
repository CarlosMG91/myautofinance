# MA-TSK-176 · Real anual en Flutter

Se sustituye el marcador `/real` por un resumen de cifras reales, serie mensual
firmada y gráfico anual por raíces más Sin clasificar. `/real/detalle` presenta
la matriz completa enero–diciembre y total anual. Ambas composiciones consumen
`AnnualActualQuery` de MA-TSK-174 y `AnnualActualNavigation` de MA-TSK-178,
sin otro motor, fórmulas financieras ni edición de celdas.

## Referencia y composición

Ticket y requisitos consultados en `GET http://localhost:4310/api/data`, tablero
My autofinance, el 2026-10-14. MA-TSK-174/175/178 y T05/MA-TSK-208 constan
completados. MA-TSK-175 tiene `approvedAt=2026-10-14T19:21:34.462Z` y discusión
del usuario «Propuesta visual aceptada: /mockups/autofinance-ma-tsk-175-v1.html».
Este registro prevalece sobre el texto local anterior «pendiente» del suplemento.
Se conservan EP-001 y la referencia global EP-026 v1 aprobada en MA-TSK-207.

`AnnualActualRoute` compone el shell y periodo EP-016 con la presentación de
`actual_spending`. `AutofinanceApp` permite inyectar el loader; la instalación
real lo resuelve en `LocalBackupSession` con la conexión vigente y su invalidación
compartida. Una restauración no deja la pantalla ligada a la conexión anterior.
Gestión conserva su navegación existente.

La vista utiliza AfCard, AfMoneyText, AfPageHeader, AfTimeChart, AfBarChart,
AfValueRow, AfStatus y AfDetailTable desde `ui/autofinance_ui.dart`. La matriz
queda en el detalle; Windows estrecho, Android y texto grande usan tarjetas.
Cada tarjeta permite abrir sus doce meses independientemente de la expansión
del árbol. Las raíces empiezan contraídas y admiten tres niveles.

## Cifras, origen y retorno

- Las cifras son las publicadas por la consulta: céntimos y signos originales,
  todas las cuentas, fecha de valor, doce meses, nodos archivados con histórico,
  total de raíces más Sin clasificar. No se agregan otra vez las filas hijas.
- Cada celda, total anual y dato del gráfico abre su lista de movimientos.
  Cero con registros y lista vacía siguen siendo navegables. Sin clasificar
  filtra referencia nula, sin crear una categoría ficticia.
- Añadir movimiento abre EP-010 el día 1 del mes enfocado. Guardar, editar,
  borrar o categorizar vuelve a consultar el año. Importación, cambios de
  catálogo y restauración usan la invalidación existente.
- Resumen, detalle y listas conservan año y mes de trabajo. Las capturas de
  origen incluyen ramas, tarjetas con meses abiertos, scroll de página, ambos
  ejes de la matriz y foco. Los enlaces sin pila reconstruyen ese contexto.
- Un cambio de año elimina las cifras anteriores mientras carga y descarta
  respuestas tardías. Un error ofrece Reintentar sin publicar ceros. Un año
  válido sin movimientos sí publica cero en los doce meses y en el anual.

## Extensión compatible del kit

AfDetailTable acepta controladores opcionales de scroll horizontal y vertical;
el consumidor conserva su propiedad y ciclo de vida. La cabecera y las cifras
sincronizan su desplazamiento en paneles separados, manteniendo la categoría
fija. Así, el desplazamiento automático de teclado no coloca una cifra debajo
de la etiqueta fija. Hay barra horizontal persistente en la cabecera y en las
cifras; el informe también permite flechas izquierda/derecha.

AfValueRow, AfTimePoint y AfBarDatum aceptan FocusNode opcional del consumidor,
para restaurar el foco de los datos equivalentes de los gráficos tras releer.
Los consumidores anteriores conservan sus valores por defecto. El kit continúa
sin consultar datos ni importar app/features; sus regresiones y arquitectura
se verifican junto al módulo.

## Evidencia visual y comprobaciones

Los cinco PNG de `test/actual_spending/goldens/` proceden del motor de pruebas
Flutter: resumen/detalle Windows 1440 px, resumen/detalle con TargetPlatform.android
a 412 px y Windows estrecho a 320 px/texto 200 %. Se han inspeccionado
visualmente; no son capturas de una app Android instalada.

Las capturas [resumen Windows](flutter-capturas/windows-resumen.png) y
[detalle Windows](flutter-capturas/windows-detalle.png) proceden del runner
nativo Windows mediante RenderRepaintBoundary, con superficie forzada
1440×900 y SQLite sintético del caso F. El recorrido nativo comprueba
**+2.329,65 EUR** anual, **+1.229,75 EUR** enero, expansión, lista de movimientos
y retorno al resumen conservando el periodo. No se confunden con las capturas
HTML del suplemento ni con goldens.

`annual_actual_screen_test.dart` contiene trece pruebas con SQLite real en memoria:
serie y totales, tres niveles con directos, histórico, null, neto cero en dos
cuentas, lista vacía, alta en mes enfocado, edición/borrado/categorización,
retorno con foco y desplazamiento, año vacío, error/reintento, respuesta tardía,
renombrado y sustitución de conexión, rutas inválidas, teclado y reflujo.

Comandos de reproducción:

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile --offline
flutter test --no-pub test/actual_spending test/ui test/architecture_test.dart
./scripts/check-quality.ps1
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
flutter drive -d windows --no-pub --driver=test_driver/annual_actual.dart --target=integration_test/annual_actual_screen_test.dart --dart-define=APP_ENV=test
```

Flutter 3.47.0 / Dart 3.13.0 comprobados; resolución offline correcta sin cambiar
SDK, dependencias ni lockfile. Análisis final sin incidencias, formato correcto
y comprobador financiero EP-001 OK. Las **124 pruebas** finales de Real anual,
kit, arquitectura y contratos de navegación pasan, junto a las cuatro variantes
de arranque development/test/production/invalid-synthetic. Después se añade y
verifica también el golden del resumen Android en la batería de trece widgets.
Windows release y APK debug compilan;
se usa JDK 17 configurado solo para esta verificación. Windows usa el Visual
Studio Insiders preinstalado; no se afirma haber usado Visual Studio 2022.

## Límites de validación

`check-quality.ps1` se ejecutó primero sin adaptación: pub.dev rechazó la
conexión de red. Se repitió con una función local que añade `--offline` al
pub get y limita las pruebas a dos procesos, sin modificar el script.
La batería global terminó con **1.206 correctas y 554 fallidas**. Un fallo
propio era el golden de detalle anterior a la barra horizontal persistente;
se regeneró, inspeccionó y verificó después. La batería global no se declara
correcta ni se atribuye automáticamente el resto de fallos a otros agentes.

Cuatro fallos de recorridos EP-011/021 (Windows/Android) se reproducen en una
copia de HEAD `762f584` sin cambios de MA-TSK-176, incorporando únicamente los
archivos concurrentes de sincronización que ya estaban en el checkout inicial
y que HEAD necesita para compilar. Informan de base bloqueada por restauración
o recuperación pendiente. No se ha aislado individualmente cada fallo global.

Se intentó el mismo recorrido nativo en el emulador Android conectado API 37.
El APK compiló, pero ADB rechazó la instalación con `Can't find service: package`,
también después de que el emulador indicase arranque completo. El recorrido
nativo Android queda sin verificar. La evidencia Android de esta entrega es
el build y los widgets/goldens; no acredita Back del sistema, TalkBack o una
aceptación visual humana de MA-TSK-217. Tampoco cierra MA-TSK-177/179 ni EP-026.

Logs y copias de contraste en `.tools/ma-tsk-176-*`, ignorados por Git.
La entrega excluye README, sincronización, fixtures y prototipos concurrentes.
No se cambia el estado de Epic Board ni se da por cerrada la épica.
