# MA-TSK-140 · Periodo compartido y contexto de sesión

Contrato técnico de EP-016. Fuentes: ticket MA-TSK-140 leído en la API local de
Epic Board (2026-10-09), [navegación EP-002](../ep-002/mapa-navegacion.md),
[entrega visual aprobada](../ep-002/entrega-flutter.md) y
[especificación financiera](../ep-001/especificacion.md).

## Estado y calendario

`AutofinanceApp` posee una `NavigationSession` durante la vida de su `State`.
Reconstruir el widget conserva la misma sesión; desmontarlo y volverlo a montar
crea otra. Puede inyectarse una sesión para pruebas (su propietario la dispone)
o un `NavigationClock`, que devuelve un instante. El reloj se consulta una vez
al crear la sesión y al solicitar explícitamente `currentMonth()`.

La sesión comienza en Estado y el mes actual Europe/Madrid, usando la función
`madridMonth` de navegación patrimonial existente. La app abre ese marcador
técnico con `a` y `m`; la recuperación local de arranque continúa teniendo
prioridad. Un contexto inicial explícito evita consultar el reloj. No existen
preferencias de navegación, tablas, archivos, escrituras financieras ni llamadas
a Drive. `/` conserva su índice técnico para desarrollo.

`NavigationPeriod` reutiliza `Month` y ofrece adaptaciones a `BudgetMonth` y
`ValueDate`, sin sustituir sus contratos. Admite años 0001–9999 y meses 01–12.
Anterior/siguiente mensual hacen aritmética civil y devuelven `null` en los
extremos. No suman duraciones de 24 horas ni convierten fechas de calendario
por DST. El reloj de Madrid solo elige el mes actual; no transforma fechas
históricas de movimientos o fotos.

## Año y mes enfocado

`NavigationContext` distingue `PeriodView.monthly` y `PeriodView.annual`.
Cambiar destino conserva año y mes. Estado, Patrimonio e Indicadores tienen
contexto mensual; Real y Presupuesto anuales tienen contexto anual por defecto.
La ruta del presupuesto actualmente implementado se declara **mensual** mientras
se use su cargador: su navegación no se convierte accidentalmente en anual.

| Acción | Resultado |
| --- | --- |
| Seleccionar periodo completo | Prevalece la elección explícita y se recuerda el mes para ese año. |
| Cambiar año en vista mensual | Conserva el mes actual, aunque el año tenga otro mes recordado. |
| Cambiar año en vista anual | Recupera el mes recordado de ese año; si no existe, enero. |
| Anterior/siguiente anual | Cambia año aplicando la misma memoria; no desborda 0001/9999. |
| Cambiar destino | Conserva el periodo; los filtros propios del destino anterior no se heredan. |
| Mes actual | Consulta el reloj y elige explícitamente el periodo actual de Madrid. |
| Nueva sesión | Estado y mes actual; sin memoria de la sesión anterior. |

`AnnualNavigationPeriod` expone `year`, `focusedPeriod`/`focusedMonth` y límites
civiles de todo el año (`firstDay` enero 1 y `until` enero 1 siguiente, exclusivo).
En 9999 el límite superior es `null` dentro del calendario admitido. El mes
enfocado permite volver a una celda; **no representa un total anual ni limita
la consulta anual al mes**. El contrato no calcula cifras.

## Origen, borrador y rutas

`NavigationContext` captura destino, periodo, tipo de vista, identidad de rama,
alcance directo/rama, filtros del consumidor, scroll y token de foco. Los filtros
son una copia inmutable; scroll debe ser finito y no negativo. Los filtros pueden
expresar rangos explícitos de movimientos sin alterar el periodo común. Sus
semánticas y consultas permanecen en los módulos propietarios.

`openSecondary()` captura el origen completo sin cambiar la sesión;
`returnToOrigin()` restaura esa instantánea. El observador de Navigator registra
orígenes al abrir rutas, conserva sesión al abrir detalles y restaura el origen
al hacer pop, incluidos filtros/scroll/foco ya publicados por el consumidor.
Guardar en otro mes no selecciona ese mes automáticamente: el consumidor debe
informar del nuevo mes y ofrecer una elección explícita, según EP-002.

Las operaciones de sesión aceptan un `NavigationLeaveGuard` asíncrono. El
consumidor muestra la protección de borrador existente antes de autorizar el
cambio; `false` conserva contexto y memoria. Una confirmación tardía no pisa
una transición posterior ni una sesión ya dispuesta. `setContext` publica
también cambios de filtros/posición del consumidor. Cambiar periodo conserva
filtros pero reinicia scroll/foco; invalidar selección/páginas y proteger
resultados de consultas tardías corresponde a los consumidores (MA-TSK-143).

`SessionLocation.resolve` valida rutas principales locales sin efectos. Acepta
`a=YYYY&m=MM` (también meses de un dígito de enlaces previos), ausencia de ambos
para usar la sesión y `a=YYYY` para aplicar
la regla de año mensual/anual. Rechaza meses sin año, ceros de calendario,
desbordamientos, formas no canónicas, parámetros duplicados o rama ambigua,
fragmentos y destinos externos. `encode` incluye siempre el mes enfocado.
Conserva `rama`/`c`, `alcance` directo/rama y los filtros de las rutas públicas
existentes. Los demás parámetros son filtros opacos del consumidor y no provocan
acciones; su semántica se valida en el módulo propietario. `a`, `m`, `rama`, `c`
y `alcance` son campos estructurales reservados. Posición/foco viajan en el
contexto de memoria; no en preferencias. `encode` transmite rama y filtros,
y el contexto completo puede acompañarlo como argumento en memoria.
Las rutas secundarias mantienen sus parsers y argumentos públicos existentes.

Un periodo inválido en una ruta principal muestra `SessionNavigationError`
antes de invocar cargadores. El retorno hace pop o, sin historial, abre el
destino validado de la última instantánea con su periodo y contexto. La ruta
de error no modifica memoria ni inventa datos. El bloqueo de recuperación local
también se aplica a estos errores. Las rutas desconocidas mantienen el error
técnico existente y retorno por historial o al origen validado de sesión;
el router técnico sin sesión conserva su retorno al índice local seguro.

## Traspaso y verificación

Los módulos no importan `app`: app adapta e inyecta periodos y callbacks por
constructor. `NavigationSessionScope` es un acceso para composición en app.
Los controles comunes y sus diálogos dependen de MA-TSK-141/142; conectar
selectores internos, filtros, scroll/foco de las vistas existentes corresponde
a MA-TSK-143. Los puntos de integración de informes pendientes son MA-TSK-144.
No se han implementado informes, pantallas financieras ni controles nuevos.

`test/navigation_session_test.dart` verifica los límites civiles, cambios
diciembre/enero y meses bisiestos/DST, Madrid en cambios de fecha respecto UTC,
elección explícita, memoria por año, mes enfocado anual, guard cancelado/tardío,
contexto inmutable, vida de sesión, destinos sin parámetros, pop de detalles y
error sin consultas con retorno completo sin historial. Se adaptan las pruebas
de arranque y Gestión al inicio en Estado; el índice técnico sigue comprobado.

Verificación del 2026-10-09:

- Flutter 3.47.0 y Dart 3.13.0 comprobados con `check-toolchain.ps1`;
  `flutter pub get --enforce-lockfile` correcto, sin cambiar el lockfile.
- `scripts/check-quality.ps1`: formato de 300 archivos sin cambios y análisis
  sin incidencias. La ejecución final de todas las pruebas, con concurrencia 2,
  terminó con 1398 correctas y dos fallos: timeout al cerrar SQLite en el
  recorrido Windows de presupuesto y expectativa de actualización de foto
  patrimonial. Por ello **la ejecución completa del script no terminó verde**.
- Repetición sin concurrencia de los módulos de presupuesto/foto afectados,
  navegación de sesión y arquitectura: **57 pruebas correctas**, sin cambios
  adicionales de código. Los dos fallos anteriores no se reprodujeron en esta
  ejecución aislada; no se afirma que se haya eliminado su intermitencia.
- Arranque comprobado por separado en development, test, production e
  invalid-synthetic: todos correctos, incluido el fallo seguro esperado.
- `git diff --check` correcto. Los logs locales permanecen en `.tools/` ignorado
  (`ma-tsk-140-quality-verified.log`, `ma-tsk-140-isolated.log` y logs de entorno).

No se ejecutaron builds ni arranques nativos: el cambio es composición/estado
Dart y no modifica proyectos de plataforma. Las pruebas de widgets no acreditan
ejecución nativa. No se afirma validación de informes o controles pendientes.
Los cambios concurrentes de sincronización, README y prototipos quedan fuera
del commit de MA-TSK-140. Se conserva la rama configurada `ticket/ma-tsk-113`.
