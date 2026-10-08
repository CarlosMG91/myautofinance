# MA-TSK-136 · Gestión y lotes con la bandeja

## Alcance y dependencias

Se consultó `GET http://localhost:4310/api/data`, tablero My autofinance,
el 2026-10-08. MA-TSK-136 coincide con el encargo; MA-TSK-111/112/135 están
`done`. La aprobación visual consta en la entrega de MA-TSK-135.

Gestión abre `/pendientes-categorizacion` sin heredar el mes de Estado, Real,
Patrimonio o Presupuesto. Los menús habilitan el acceso cuando la composición
dispone de pendientes y categorías. Resultado (incluido «ya importado») y
detalle del historial abren la misma ruta con `?lote=<UUID>`.

Los enlaces conservan la ruta original en la pila, con sus argumentos, periodo,
filtros y estado. El enlace contextual muestra el contador actual leído de
SQLite; los conteos originales de importación permanecen inmutables. Al volver
se releen pendientes y se restaura el foco de la acción. Al volver desde el
detalle del lote al resultado también se actualiza su contador. «Ver lote»
desde la bandeja conecta el detalle existente y reutiliza el retorno de T135,
que conserva filtros, scroll y UUID aún elegibles.

La existencia del lote se comprueba con las etiquetas de procedencia EP-004,
independientes de los lectores. Un UUID inexistente muestra un error sin página
editable; un lote existente sin pendientes muestra el vacío útil de T135.
UUID y parámetros inválidos, repetidos, esquemas, autoridades o fragmentos se
rechazan antes de consultar la bandeja. No se escribe por abrir o volver.

No se modifican lectores CSV/Openbank, contratos financieros, esquema,
presupuestos, fotos, importación ni sincronización. Los archivos compartidos
de composición y presentación estaban limpios al empezar; el trabajo previo
de Drive, README, fixtures y mockups queda fuera de este ticket.

## Verificación

Pruebas con SQLite sintético: Gestión global desde Real, Patrimonio y
Presupuesto; resultado con 51 pendientes; ida y vuelta de lote/bandeja en
1440 y 412 px, categoría persistida, contador cero, foco y estado de origen;
«Ver lote» y selección conservada; vacío, UUID inexistente y consultas inválidas
sin cambiar la revisión local. Se conservan los recorridos EP-010/012 y las
pruebas de arquitectura.

`scripts/check-quality.ps1` completo correcto: 287 archivos con formato
correcto, análisis sin incidencias, **1.353 pruebas aprobadas** y las cuatro
variantes de arranque (`development`, `test`, `production`, `invalid-synthetic`).
`node docs/ep-001/verificar-casos.mjs` y `git diff --check`: correctos.

La primera ejecución detectó timeouts de los recorridos EP-012: el contador
estaba consultando dentro del snapshot SQLite y el recorrido avanzaba sin
esperarlo. El indicador de carga hace visible esa operación; los recorridos
afectados y la suite completa final pasan. No se modifica su timeout.

Compilaciones finales correctas con `--no-pub --dart-define=APP_ENV=test`:
Windows release (`build/windows/x64/runner/Release/myautofinance.exe`) y
Android debug (`build/app/outputs/flutter-apk/app-debug.apk`). Android usa
el JDK 17.0.20.1 local con APPDATA aislado por proceso en
`.tools/ma-tsk-136-flutter-config`; no cambia la configuración global.
SDK, lockfile, cachés y artefactos de compilación quedan fuera del commit.

No se acredita ejecución nativa en un dispositivo Android ni un recorrido
manual de Windows; la navegación, el foco y las tablas/tarjetas se verifican
en pruebas de widgets del host con SQLite sintético.
