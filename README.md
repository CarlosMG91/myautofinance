# Autofinance

Aplicación de finanzas familiares para Windows y Android, en español (es-ES)
y EUR. La base técnica Flutter está implementada; las cinco vistas son rutas
con marcadores técnicos, sin datos ni lógica financiera.

## Preparación y arranque

Usar las versiones de `toolchain.json`: Flutter 3.47.0 stable, Dart 3.13.0
incluido y JDK 17. No ejecutar `flutter upgrade`. Seguir
[entorno reproducible](docs/ep-003/entorno.md) para instalar Visual Studio 2022
con Desktop development with C++, Android SDK API 36, Build-Tools 36.0.0 y
NDK 28.2.13676358, configurar PATH y aceptar las licencias Android.
Los scripts locales funcionan con PowerShell; CI usa PowerShell 7.

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter doctor -v
flutter pub get --enforce-lockfile
flutter devices
flutter run -d windows --dart-define=APP_ENV=development
# Con teléfono autorizado o emulador arrancado: sustituir <id> por su ID.
flutter run -d <id> --dart-define=APP_ENV=development
```

`APP_ENV` admite development, test y production (valor por defecto). Son
ajustes públicos incluidos en el binario; nunca introducir secretos. La
[infraestructura SQLite](docs/ep-004/persistencia-local.md) todavía no se conecta
al arranque de los marcadores técnicos ni a repositorios de negocio.

## Verificación y compilaciones

```powershell
./scripts/check-quality.ps1
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

Calidad comprueba versiones, lockfile, formato, análisis y pruebas, incluidas
las variantes de arranque. Para corregir formato: `dart format lib test`.
Windows requiere el compilador de Visual Studio; Android requiere SDK/JDK,
pero no emulador para compilar. Las salidas locales son
`build/windows/x64/runner/Release/` (conservar EXE, DLL y carpeta data juntos)
y `build/app/outputs/flutter-apk/app-debug.apk`. El APK usa la clave debug
autogenerada: sirve para inspección, sin firma ni distribución de producción.

GitHub Actions ejecuta [calidad](.github/workflows/quality.yml),
[entorno](.github/workflows/toolchain.yml) y
[compilaciones](.github/workflows/build.yml) en push, pull request y manualmente.
Build usa Windows 2022 y Ubuntu 24.04 con Android SDK, lee la versión fijada y
falla si falta la salida. En la ejecución de **Compilaciones Flutter**, descargar
los dos ZIP de **Artifacts**, `autofinance-windows-<sha>` y
`autofinance-android-<sha>`; caducan a los 14 días. La descarga requiere acceso
al repositorio y sesión GitHub. No son instaladores ni entregas de distribución.

## Estructura y traspaso

| Ruta | Responsabilidad |
|---|---|
| `lib/main.dart`, `lib/app/` | Arranque, composición, configuración regional y navegación |
| `lib/core/` | Contratos técnicos compartidos sin Flutter ni reglas financieras |
| `lib/features/` | monthly_status, wealth, budget, actual_spending, indicators, movements, importing y synchronization |
| `test/` | Arquitectura, navegación, localización, arranque y widgets |
| `android/`, `windows/` | Proyectos nativos generados para los dos destinos |
| `scripts/`, `.github/workflows/` | Verificadores comunes y CI |
| `docs/ep-001/`, `docs/ep-002/`, `docs/ep-003/` | Contrato funcional, diseño y documentación técnica |

Cada módulo publica su entrada `<nombre>.dart`; añadir domain, data y
presentation cuando haya implementación. `app` inyecta adaptadores por
constructor. Seguir [arquitectura y dependencias](docs/ep-003/arquitectura.md).

Las rutas `/estado`, `/patrimonio`, `/presupuesto`, `/real` e `/indicadores`
son vacías; `/` es un índice de desarrollo y `/error` un marcador técnico.
EP-002 entrega el [diseño y flujos para Flutter](docs/ep-002/entrega-flutter.md),
que registra la aprobación de MA-TSK-019. Las épicas funcionales sustituirán
los marcadores dentro de su alcance; este ticket no implementa pantallas.
Las épicas de datos definirán esquema SQLite, migraciones y puertos en los
módulos propietarios; importación y Drive continúan pendientes. No copiar los
servicios simulados del prototipo ni código del proyecto MyFinance.

## Contrato funcional

La [guía de integración SQLite](docs/ep-004/guia-integracion.md) entrega las
API de repositorios, esquema v6, migraciones y límites para CSV, Openbank,
informes y Drive, con el recorrido integrado automatizado de MA-TSK-040.

EP-001 fue aprobado el 2026-10-01. Consultar
[especificación](docs/ep-001/especificacion.md),
[contrato CSV](docs/ep-001/contrato-csv.md),
[ejemplo sintético](docs/ep-001/historico-ejemplo.csv),
[casos de referencia](docs/ep-001/casos-referencia.md) y
[decisiones](docs/ep-001/decisiones.md) antes de implementar reglas.

La evidencia local y remota de MA-TSK-029 está en
[CI de compilaciones](docs/ep-003/ci-compilaciones.md).

MA-TSK-042 prepara la [configuración mínima de OAuth Google](docs/ep-005/oauth-google.md)
para Android y Windows, con inventario público y verificador local. El
[registro de entrega](docs/ep-005/verificacion-oauth.md) documenta el bloqueo de
acceso a Google Cloud; los clientes reales y el consentimiento siguen pendientes.

MA-TSK-043 entrega el [contrato común de sesión y cuenta Drive](docs/ep-005/sesion-drive.md),
con estados, autorización y renovación explícitas, desconexión local y carpeta
vinculada a la cuenta. Se verifica con proveedor falso; los adaptadores OAuth
y el almacenamiento seguro nativo se implementarán en los tickets posteriores.

MA-TSK-044 implementa el [adaptador de autorización Android](docs/ep-005/autorizacion-android.md)
con `google_sign_in`, validación de cuenta Drive y metadatos cifrados por
instalación. Incluye pruebas sintéticas y un recorrido técnico manual; el alta
OAuth, la firma registrada y la comprobación en dispositivo siguen pendientes.
