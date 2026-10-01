# MA-TSK-022 · Entorno reproducible

`toolchain.json` es la fuente única de versiones para desarrollo y CI: Flutter
**3.47.0**, canal **stable**, con su Dart **3.13.0** incluido. No instalar Dart
por separado ni ejecutar `flutter upgrade`. Es una versión estable concreta,
no una selección flotante de «latest». Cambiarla requiere revisar este contrato
y verificar Windows y Android juntos.

## Preparar Windows y Android

1. Usar Windows 10/11 de 64 bits con Git y PowerShell. Descargar el SDK Windows
   x64 3.47.0 desde el [archivo oficial](https://docs.flutter.dev/install/archive),
   comprobar su SHA-256 con el manifiesto oficial y extraerlo en una carpeta local
   escribible, fuera de Program Files y del repositorio. Añadir su directorio
   `bin` al PATH del usuario y abrir una terminal nueva. Alternativa con Git:
   `git clone --branch 3.47.0 --depth 1 https://github.com/flutter/flutter.git`
   desde la carpeta elegida para herramientas; añadir también su `bin` al PATH.
2. Instalar **Visual Studio 2022**, con **Desktop development with C++**
   (`Microsoft.VisualStudio.Workload.NativeDesktop`) y sus componentes
   recomendados: MSVC v143 para x64/x86, C++ CMake tools for Windows y Windows
   SDK. Visual Studio Code no sustituye este compilador. En CI se utiliza
   `windows-2022`, cuya imagen proporciona Visual Studio 2022; registrar la
   revisión efectiva mediante doctor porque la imagen recibe actualizaciones.
3. Instalar Android Studio estable y, mediante SDK Manager, Android SDK Platform
   **API 36**, Build-Tools **36.0.0**, Platform-Tools, Command-line Tools,
   NDK (Side by side) **28.2.13676358** y CMake. Para depuración sin teléfono,
   instalar Android Emulator y una imagen API 36 x86_64, crear un AVD y activar
   virtualización. Emulator e imagen no son necesarios para compilar.
4. Instalar JDK **17** (Temurin) y seleccionarlo como Gradle JDK. Configurar
   `JAVA_HOME` localmente. Flutter puede preferir el Java de Android Studio:
   ejecutar `flutter config --jdk-dir "$env:JAVA_HOME"` para usar el JDK elegido.
   Si el SDK Android no se detecta, configurar localmente `ANDROID_HOME` y
   ejecutar `flutter config --android-sdk "$env:ANDROID_HOME"`.
5. Con `sdkmanager` en PATH, los paquetes de compilación se pueden instalar con:

   ```powershell
   sdkmanager 'platforms;android-36' 'build-tools;36.0.0' 'platform-tools' 'ndk;28.2.13676358'
   ```

   Command-line Tools se instala inicialmente con SDK Manager. CMake se añade
   desde SDK Tools; su revisión concreta se fijará si algún módulo nativo lo
   requiere. No se promete reproducibilidad binaria de componentes auxiliares
   ni del sistema operativo.
6. Revisar y aceptar personalmente las licencias con
   `flutter doctor --android-licenses`. Después:

   ```powershell
   flutter config --enable-windows-desktop --enable-android
   ./scripts/check-toolchain.ps1
   flutter doctor -v
   flutter devices
   flutter emulators
   ```

La comprobación de versiones falla si PATH apunta a otro Flutter o Dart. Doctor
debe mostrar sin incidencias **Flutter**, **Windows Version**, **Android
toolchain** y **Visual Studio - develop Windows apps**. Android Studio debe
detectarse en la preparación con IDE. Debe aparecer un dispositivo Windows y,
para probar Android, un teléfono autorizado o emulador arrancado. Chrome, iOS y
Linux desktop no son requisitos. Un código de salida cero de doctor por sí solo
no acredita todos los componentes: revisar sus secciones y advertencias.

Las rutas dependen de cada máquina. No versionar SDK, `local.properties`, caches,
salidas de compilación ni logs de doctor sin eliminar rutas personales y datos
del dispositivo. Las credenciales y firmas quedan fuera del ticket.

## CI y límites de este ticket

`.github/workflows/toolchain.yml` lee `toolchain.json`, instala exactamente esa
versión mediante Flutter Action y comprueba Flutter/Dart en Windows y Ubuntu
(host del futuro build Android). Doctor deja diagnóstico en los logs del runner;
no se usa como prueba automática de disponibilidad de todos los destinos.
Los runners no necesitan dispositivos para compilar. Todavía no hay `pubspec.yaml`:
análisis, pruebas y builds de la aplicación corresponden a los siguientes
tickets de EP-003. Esos jobs deben leer el mismo archivo y ejecutar el mismo
verificador, además de preparar Android SDK/JDK según este contrato.

## Fuentes verificadas el 2026-10-01

- [Release estable 3.47.0](https://docs.flutter.dev/release/release-notes/release-notes-3.47.0).
- [Dependencias del tag 3.47.0](https://github.com/flutter/flutter/blob/3.47.0/DEPS)
  y [VERSION del Dart incluido](https://github.com/dart-lang/sdk/blob/da6595cd6bb5d4c0a185d759a025e879ff06e631/tools/VERSION).
- [Valores Android de Flutter 3.47.0](https://github.com/flutter/flutter/blob/3.47.0/packages/flutter_tools/lib/src/android/gradle_utils.dart).
- [Preparación oficial Windows](https://docs.flutter.dev/platform-integration/windows/setup)
  y [Android](https://docs.flutter.dev/platform-integration/android/setup).

Ver el [informe local](verificacion-entorno.md) para distinguir requisitos de
comprobaciones realmente ejecutadas.
