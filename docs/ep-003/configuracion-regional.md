# MA-TSK-026 · Idioma, importes y ajustes seguros

La aplicación y el fallo de arranque fijan `Locale('es', 'ES')`, con los
delegados oficiales de Flutter para Material, Cupertino y widgets. Se mantiene
el español aunque el dispositivo esté en otro idioma. `AppRegional.formatEuro`
usa `intl`, EUR, símbolo €, dos decimales y separadores españoles:
`1234.56` se presenta como `1.234,56 €`. Rechaza valores no finitos.
Es formato de presentación; no define cálculos, almacenamiento monetario,
redondeo de presupuestos ni fechas financieras de EP-001.

## Configuración pública por entorno

`AppConfig` admite exclusivamente `development`, `test` y `production`.
El arranque lee `APP_ENV` mediante `String.fromEnvironment`; el valor por
defecto es `production`. Se valida antes de montar la aplicación y se inyecta
en `AutofinanceApp`. No se realizan operaciones diferentes por entorno todavía.

```powershell
flutter run -d windows --dart-define=APP_ENV=development
flutter run -d <identificador-android> --dart-define=APP_ENV=test
flutter build apk --debug --dart-define=APP_ENV=production
```

Los valores se fijan al compilar; cambiar el entorno requiere reconstruir.
Los dart-defines están incluidos en el binario: nunca deben contener tokens,
credenciales, datos bancarios ni rutas personales. No se crean archivos `.env`,
endpoints ni ajustes de SQLite o Drive. Idioma y divisa son constantes del
producto, no opciones por entorno.

## Arranque controlado

`main` inicializa el binding de Flutter y espera `initializeApp`.
Esta función centraliza las inicializaciones futuras y captura sus excepciones
síncronas y asíncronas esperadas. Ante un fallo muestra en español:
«No se pudo iniciar Autofinance. Código técnico: INIT-001. Revisa la
configuración y reinicia la aplicación.» No muestra ni registra la excepción,
su valor de configuración ni su pila, que podrían contener datos privados.
Un entorno inválido sigue ese mismo camino. No hay reintentos ni servicios
iniciados en segundo plano. Este límite cubre la inicialización esperada;
no captura fallos nativos anteriores a Dart ni errores posteriores de widgets.
La vista de fallo es técnica y no implementa pantallas de producto.

## Verificación · 2026-10-01

- `flutter analyze --no-pub`: sin incidencias.
- `flutter test --no-pub`: 19 pruebas correctas, incluidas seis nuevas para
  formato positivo/negativo/cero y rechazo de no finitos, configuración,
  idioma efectivo sobre un sistema en inglés, inyección del entorno y fallos
  síncronos, asíncronos y de configuración sin exposición de detalles.
- `dart format lib test`: aplicado.
- Dependencias oficiales de localización y `intl` resueltas en `pubspec.lock`.

No se verificó el arranque nativo ni se compilaron Windows/Android: la falta
de Visual Studio y Android SDK ya está documentada en `proyecto-flutter.md`.
Se usa el ticket completo facilitado por el usuario; no hay herramienta
Epic Board disponible y no se consultó ni modificó el tablero.
`AGENTS.md` y `README.md` estaban sin seguimiento al comenzar y se excluyen
de la entrega de este ticket.
