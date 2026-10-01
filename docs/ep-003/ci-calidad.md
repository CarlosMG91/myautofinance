# MA-TSK-028 · GitHub Actions para análisis y pruebas

El workflow [Calidad Flutter](../../.github/workflows/quality.yml) se ejecuta
con cada `push` y `pull_request`, y permite ejecución manual. Ejecuta el mismo
`scripts/check-quality.ps1` de desarrollo en `windows-2022` y `ubuntu-24.04`,
con PowerShell 7. Cada job tiene un límite de 20 minutos y ambos resultados
son independientes para facilitar el diagnóstico.

Lee Flutter y canal desde `toolchain.json`: Flutter 3.47.0 stable. El script
comprueba también Dart 3.13.0, obtiene dependencias con `--enforce-lockfile`,
comprueba formato sin modificar archivos, analiza con avisos e informaciones
fatales y ejecuta las pruebas y las cuatro variantes de arranque. Cualquier
fallo detiene el job con error; no hay `continue-on-error`.

Solo concede `contents: read`, no conserva credenciales del checkout y no usa
secretos, firmas ni servicios externos de la aplicación. La descarga del SDK
y de paquetes requiere acceso a los proveedores. Este ticket no compila
destinos nativos; las compilaciones pertenecen al ticket siguiente.

Antes de consultar la versión JSON se inicializa el SDK con `flutter --version`.
Esto evita que los mensajes del primer arranque en Windows contaminen la salida
que procesa el verificador. Los errores del script se publican como anotaciones
de Actions y conservan el resultado fallido.

## Verificación local · 2026-10-01

- `actionlint` 1.7.12: workflow válido, sin errores.
- `scripts/check-quality.ps1`: correcto con el SDK fijado; lockfile sin cambios,
  22 archivos con formato correcto y análisis sin incidencias.
- Suite completa: 21 pruebas correctas. Las cuatro variantes adicionales
  (development, test, production e inválida sintética): correctas.
- `git diff --check`: sin errores.

Se utilizó el ticket completo facilitado por el usuario. Epic Board no tiene
herramienta disponible en esta sesión y no se ha modificado el tablero.
`AGENTS.md` y `README.md` ya estaban sin seguimiento al empezar y se excluyen
del commit.

## Ejecución remota acreditada

[Ejecución 36851297636](https://github.com/CarlosMG91/myautofinance/actions/runs/36851297636),
activada por `push` a `main` del commit
`ce058eb13c1df146afe88a37226a9432006503d9`: **success**, con los dos jobs
Windows y Ubuntu completados en verde el 2026-10-01.

Los primeros intentos detectaron un fallo al interpretar JSON en el primer
arranque del SDK Windows; quedó resuelto con la inicialización previa. La API
pública de descarga de logs respondió HTTP 403 y no había navegador disponible;
las anotaciones públicas permitieron diagnosticar el error sin añadir secretos
ni permisos al workflow. No queda bloqueo externo para este ticket.

El workflow previo `toolchain.yml`, procedente de MA-TSK-022, también mostró un
fallo en Windows durante estas ejecuciones. No se modificó en este ticket. La
ejecución verde acreditada corresponde a **Calidad Flutter**; no acredita que
todos los workflows del repositorio estén en verde ni builds nativos.

## Fuentes

- [Sintaxis de GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax).
- [Flutter Action: versión y canal concretos](https://github.com/subosito/flutter-action#use-specific-version-and-channel).
