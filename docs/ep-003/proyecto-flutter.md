# MA-TSK-023 · Proyecto Flutter

Aplicación generada con Flutter **3.47.0** (revisión
`4cf24164269a5ebf0c16a028a00727d0e77bbb05`) y Dart **3.13.0**, según
`toolchain.json`. Se utilizó la plantilla oficial vacía:

```powershell
flutter create --platforms=windows,android --org com.carlosmg91 --project-name myautofinance --empty <carpeta-temporal>
```

Se trasladaron a la raíz únicamente las plataformas, `lib`, configuración y
lockfile. El README previo se conservó. El paquete Dart y el ejecutable Windows
se llaman `myautofinance`; el nombre visible, título de ventana y metadatos de
producto son **Autofinance**. Android usa `com.carlosmg91.myautofinance` como
namespace, applicationId y paquete de MainActivity.

La única pantalla muestra «Autofinance · Base técnica». No contiene datos,
operaciones financieras, persistencia, Drive, navegación ni diseño de producto.
Los iconos son los de la plantilla, pendientes del diseño aprobado.

## Uso desde la raíz

Preparar los compiladores y SDK siguiendo [entorno.md](entorno.md). Con la
versión fijada en PATH:

```powershell
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run -d windows
flutter devices
flutter run -d <identificador-android>
```

Para comprobar compilación sin dispositivo:

```powershell
flutter build windows --debug
flutter build apk --debug
```

`pubspec.lock`, `.metadata`, Gradle y CMake se versionan. SDK, caches, rutas
locales, wrapper descargado, compilaciones y claves se ignoran conforme a la
plantilla Flutter. Flutter prepara el wrapper de Gradle al compilar Android.
La configuración de release conserva la firma de depuración de la plantilla;
no constituye firma ni distribución de producto. El CI de aplicación corresponde
a otro ticket: este no modifica el workflow de entorno.

## Verificación local · 2026-10-01

Se utilizó el ticket completo facilitado por el usuario. No hay herramienta
Epic Board disponible en esta sesión; no se consultó ni modificó su estado.
La generación oficial y `flutter pub get` finalizaron correctamente. El
verificador de MA-TSK-022 confirmó Flutter 3.47.0 y Dart 3.13.0. El SDK local
se obtuvo por checkout del tag exacto; doctor lo identifica como `user-branch`
por estar en detached HEAD, sin cambiar la revisión fijada.

Doctor detectó Windows, pero **Visual Studio no está instalado** y **no se
encuentra Android SDK**. No hay dispositivo Android conectado. Por ello el
arranque nativo de ambos destinos queda pendiente de un entorno preparado;
la prueba de widgets no sustituye esa comprobación.

- `flutter pub get --enforce-lockfile`: correcto, sin cambiar el lockfile.
- `flutter analyze`: sin incidencias.
- `flutter test`: una prueba de arranque de widgets, correcta.
- `dart format lib test`: aplicado.
- `flutter build windows --debug`: bloqueado por falta de Visual Studio.
- `flutter build apk --debug`: bloqueado por falta de Android SDK.
- Solo existen las carpetas de plataforma `windows` y `android`.
