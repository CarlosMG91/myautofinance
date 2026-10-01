# MA-TSK-027 · Pruebas de base y comandos de calidad

Desde la raíz del repositorio, usar las versiones de `toolchain.json` y añadir
el `bin` de ese Flutter al PATH según [entorno.md](entorno.md). Dart se incluye
en Flutter. En Windows se admite Windows PowerShell; para CI en Windows o Linux
se utiliza PowerShell 7 (`pwsh`). Ejecutar:

```powershell
./scripts/check-quality.ps1
```

El script comprueba las versiones, resuelve el lockfile sin permitir cambios,
verifica formato, analiza y ejecuta todas las pruebas. Además comprueba el
arranque con los tres entornos públicos y con una configuración inválida
sintética. Se detiene con error ante cualquier comprobación fallida y restaura
el directorio de trabajo. Los futuros jobs de calidad de CI deben ejecutar este
mismo script; las compilaciones Windows/Android corresponden al ticket de CI.

## Comandos individuales

```powershell
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub --fatal-infos --fatal-warnings
flutter test --no-pub
flutter test --no-pub --dart-define=APP_ENV=development test/environment_bootstrap_test.dart
flutter test --no-pub --dart-define=APP_ENV=test test/environment_bootstrap_test.dart
flutter test --no-pub --dart-define=APP_ENV=production test/environment_bootstrap_test.dart
flutter test --no-pub --dart-define=APP_ENV=invalid-synthetic test/environment_bootstrap_test.dart
```

Para aplicar el formato: `dart format lib test`. Revisar después el diff.
Los comandos `flutter analyze` y `flutter test` sin opciones también ejecutan
las comprobaciones habituales, incluyendo resolución de dependencias.
La suite completa presupone el entorno predeterminado; las variantes de
`APP_ENV` se ejecutan solo sobre `environment_bootstrap_test.dart`.

## Cobertura y límites

| Archivo | Comportamiento comprobado |
|---|---|
| `widget_test.dart` | Punto de entrada real `main`, índice técnico y entorno predeterminado. |
| `navigation_test.dart` | Acceso y retorno de las cinco rutas, locale y traducción Material, ruta desconocida y error explícito, retorno del sistema y recuperación sin historial. |
| `regional_config_test.dart` | EUR positivo, negativo y cero, rechazo de no finitos, es-ES con dispositivo inglés, validación e inyección de configuración, fallos síncronos/asíncronos sin exposición de detalles. |
| `environment_bootstrap_test.dart` | `APP_ENV` realmente compilado llega al arranque; un valor inválido muestra el fallo seguro en español sin navegar ni exponer su contenido. |
| `architecture_test.dart` | Módulos completos, fronteras entre capas y dependencias sin ciclos. |

Las pruebas ejecutan interacciones y verifican resultados observables. Todos
los importes y errores son sintéticos. No necesitan base de datos, credenciales,
Google Drive, dispositivos, emuladores ni servicios externos. La primera
resolución de paquetes puede requerir red; con SDK y paquetes en caché se puede
usar `flutter pub get --offline --enforce-lockfile` y los comandos `--no-pub`.
No implementan ni validan pantallas de producto o reglas financieras.
Las pruebas de widgets no acreditan el arranque nativo ni la compilación de
Windows/Android.

## Verificación local · 2026-10-01

- `scripts/check-quality.ps1` completado con Flutter 3.47.0 y Dart 3.13.0.
- Lockfile resuelto sin cambios; formato correcto y análisis sin incidencias.
- Suite completa: 21 pruebas correctas. Cuatro ejecuciones adicionales del
  arranque compilado (development, test, production e inválido): correctas.
- `git diff --check`: sin errores.

No se compilaron ni arrancaron aplicaciones nativas; el entorno carece de
Visual Studio y Android SDK según [proyecto-flutter.md](proyecto-flutter.md).
Se ha usado el ticket completo proporcionado por el usuario: no hay herramienta
Epic Board disponible en esta sesión y no se ha actualizado el tablero.
`AGENTS.md` y `README.md` ya estaban sin seguimiento al comenzar y se excluyen
de la entrega.
