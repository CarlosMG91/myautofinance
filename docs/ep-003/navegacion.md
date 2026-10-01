# MA-TSK-025 · Navegación técnica

`lib/app/navigation/app_routes.dart` centraliza los identificadores y el catálogo
de las cinco áreas: `/estado`, `/patrimonio`, `/presupuesto`, `/real` e
`/indicadores`. Cada entrada identifica su módulo de MA-TSK-024. `/` es un
índice temporal de desarrollo y `/error` permite abrir el marcador de error.

`AppRouter.generateRoute` registra los destinos en el arranque mediante
`MaterialApp.onGenerateRoute`. Cualquier nombre desconocido abre el mismo
marcador de error, conservando el nombre y los argumentos de la petición en
`RouteSettings`. No se requiere una dependencia adicional de navegación.

Desde el índice se abre cada área con `pushNamed`. Tanto «Volver» como el
retorno estándar del navegador restauran la ruta anterior; si el marcador se
abre sin historial, «Volver» reemplaza la ruta por el índice. Las páginas solo
contienen etiquetas técnicas y controles de navegación, sin tablas, tarjetas,
periodos, datos ni flujos de producto. No activan servicios ni módulos.

El índice no establece el arranque definitivo ni la navegación visual de EP-002.
La implementación de producto espera aprobación explícita de MA-TSK-019; los
nombres y presentación se ajustarán a MA-TSK-020. Las cinco rutas corresponden
a EP-001 §5 y al mapa de navegación entregado por EP-002.

## Verificación · 2026-10-01

- Flutter 3.47.0 y Dart 3.13.0, SDK fijado en `.tools/flutter`.
- `dart format lib/app test/navigation_test.dart`: sin cambios pendientes.
- `flutter analyze --no-pub`: sin incidencias.
- `flutter test --no-pub`: 13 pruebas correctas, incluidas las de arquitectura y
  arranque existentes. Las diez nuevas comprueban registro, transición hacia
  cada área y retorno, error explícito y desconocido, retorno del sistema con
  historial y recuperación del índice sin historial.
- `git diff --check`: sin errores.

No se ejecutaron compilaciones ni arranques nativos: el entorno documentado en
MA-TSK-023 carece de Visual Studio y Android SDK. Las pruebas de widgets no
demuestran el arranque en dispositivos. Este ticket no cambia plataformas.

Se ha utilizado el ticket completo proporcionado por el usuario; Epic Board
no tiene una herramienta disponible en esta sesión y no se ha modificado su
estado. `AGENTS.md` y `README.md` estaban sin seguimiento al comenzar y se
excluyen de la entrega de este ticket.
