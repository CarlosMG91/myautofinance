# MA-TSK-216 · Drive, copias y recuperación

Implementación de presentación sobre el prototipo integral v1 aprobado en
MA-TSK-207 (discusión del ticket en Epic Board) y el kit de MA-TSK-208.
Entrada en Gestión → Copia en Drive / Copias locales; conserva el shell,
el periodo y el retorno de origen de MA-TSK-209.

## Comportamiento

- Drive separa base local, última copia conocida y acciones manuales. Muestra
  cuenta, referencia local, cambios locales, versión y fecha remotas conocidas.
  Desconocido y sin copia son distintos; sin copia no reutiliza la fecha ni la
  versión de una observación anterior. Las versiones distintas y el contraste
  pendiente se presentan por separado, sin afirmar una comparación actual.
  Al cambiar de cuenta se descartan los metadatos observados de la anterior;
  leer el nuevo estado local tampoco consulta la red.
- Entrar, ver Inicio y abrir el catálogo local no comprueban Drive. Solo los
  botones existentes Subir copia y Descargar última copia ejecutan `prepare`
  y los coordinadores remotos. No hay reintento, conexión o fusión automática.
- Las confirmaciones conservan advertencia de pérdida, respaldo previo,
  Cancelar, Escape, Atrás y retorno de foco. Cancelar descarga no aplica datos;
  cancelar creación/restauración local no llama a sus servicios de escritura.
- El progreso muestra las fases entregadas por los coordinadores existentes
  con indicador indeterminado, sin estimar porcentajes. Los resultados solo
  llevan «Completado» ante el resultado de éxito confirmado. Una cancelación,
  respuesta incierta o error mantiene su mensaje y acción manual; los fallos de
  restauración remota también muestran la causa del coordinador local.
- Copias locales conserva catálogo, detalle, validación, creación, eliminación,
  restauración, protección de la última copia y recuperación con base dañada.
  Presenta disponibilidad de la base y cantidad registrada; catálogo ilegible
  muestra cantidad desconocida. PC mantiene tabla; Android y texto al 200 %
  usan tarjetas. Una base dañada explica aislamiento de originales sin prometer
  que puedan restaurarse. La política de conservación permanece intacta.

Solo se cambian vistas y estado de presentación; no OAuth, permisos,
transferencias, SQLite, sincronización, versiones, respaldos ni retención.
Las modificaciones concurrentes de esos servicios quedan fuera del commit.

## Verificación reproducible

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
./scripts/check-quality.ps1
flutter test --no-pub test/synchronization
flutter drive --profile --no-pub -d windows --driver=test_driver/synchronization_redesign.dart --target=integration_test/synchronization_redesign_test.dart --dart-define=APP_ENV=test --dart-define=CAPTURE_SYNC_REDESIGN=true --dart-define=SYNC_CAPTURE_DIRECTORY=docs/ep-026/copias-capturas
flutter test --no-pub --no-uninstall -d emulator-5554 --dart-define=APP_ENV=test --dart-define=CAPTURE_SYNC_REDESIGN=true integration_test/synchronization_redesign_test.dart
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

La prueba nativa usa una instalación SQLite temporal, crea una copia, modifica
una categoría sintética, cancela restauración y comprueba que persiste el cambio,
restaura y verifica la categoría original, respaldo previo y dos entradas en
el catálogo. Los puertos remotos simulan divergencia y cancelación; no acceden
a cuentas ni Drive reales. Comprueba que Inicio/entrada/catálogo no invocan
acciones remotas y que solo los dos botones incrementan sus contadores.

`copias-capturas/` conserva imágenes del renderizado de la aplicación ejecutada
en Windows y en el emulador Android durante el recorrido nativo. No son mockups
HTML ni goldens de `flutter test` en el host. En Android se guardan dentro de
los datos privados de la app de prueba y se extraen con `adb run-as`.
`--no-uninstall` conserva la app sintética hasta extraerlos. La extracción debe
preservar bytes binarios y verificar PNG; redirigirlos como texto en PowerShell
no es válido. Las seis imágenes Android dañadas de la ejecución anterior se
han reemplazado por capturas verificadas del recorrido correcto.
Las fechas de las copias locales y sus UUID proceden de los servicios reales
sobre datos exclusivamente sintéticos. No contienen información personal.

El driver Windows usa profile porque el compilador C++ instalado falla al
enlazar las bibliotecas CRT de debug. No se modifica el proyecto para evitarlo.
El driver emite un aviso de plugin de integración no detectado en Windows;
los resultados también se recogen con `integrationDriver` y sus aserciones.
La compilación release se verifica aparte. Android debe usar JDK 17 y los
paquetes de `toolchain.json`; el emulador disponible tiene API 37.

Los lectores de pantalla nativos y la integración completa de las cinco vistas
permanecen en T14. Este recorrido no acredita OAuth ni transferencias reales.

## Resultado de la entrega · 2026-10-13

Se consultaron MA-TSK-216, MA-TSK-208 y la discusión de MA-TSK-207 mediante
`GET http://localhost:4310/api/data`. El usuario aceptó expresamente
`/mockups/autofinance-integral-v1.html`; el registro local antiguo de T04 aún
dice pendiente y corresponde reconciliarlo a su propietario.

- Toolchain Flutter 3.47.0 / Dart 3.13.0 comprobada, dependencias resueltas
  con lockfile estricto; sin cambios en SDK ni paquetes.
- Análisis final sin incidencias y **53 pruebas de presentación** correctas:
  estados locales/remotos, cambio de cuenta, ausencia de copia, divergencia,
  contraste pendiente, respuesta incierta, autenticación/red/integridad,
  respaldo, cancelación, recuperación bloqueada, foco/teclado/Back y reflujo
  320–1440 px con texto 200 %.
- Recorrido nativo Windows profile correcto; recorrido Android correcto con
  JDK 17, emulador API 37, SQLite real temporal y respuestas Drive sintéticas.
  Se verifican cancelación sin escritura, creación, restauración, protección
  de la base anterior y catálogo. Capturas nativas de seis estados por plataforma
  inspeccionadas visualmente: textos, botones, advertencias y foco legibles.
- Referencias EP-001 comprobadas mediante `node docs/ep-001/verificar-casos.mjs`.
- Suite general final: **1.733 pruebas correctas** con todos los cambios de
  presentación terminados, incluidas copias, transferencias, instalación,
  interrupciones de proceso, recuperación, arquitectura y reglas financieras.
  `./scripts/check-quality.ps1` finalizado correctamente: formato sin cambios,
  análisis sin incidencias y cuatro variantes de arranque
  development/test/production/invalid-synthetic también correctas.
- Compilaciones de la entrada principal: Windows release y Android APK debug
  correctas con `APP_ENV=test`. Android usa JDK 17 en configuración local
  aislada mediante `APPDATA`, sin modificar la configuración global del usuario.

La primera ejecución de calidad coincidió con la incorporación de una prueba
que requería el nuevo estado de presentación del controlador local, mientras
el compilador aún usaba su versión anterior. La repetición con código terminado
y directorio de build aislado finalizó correctamente; las pruebas específicas
y nativas finales también utilizan el estado actualizado.

## Límite previo de la entrega en Git

La base confirmada (`c70388a`) ya importa `domain/drive_upload.dart` desde el
controlador y usa sus tipos en composición, pero ese contrato y su exportación
siguen entre los cambios locales de MA-TSK-064. Ese ticket figura completado en
Epic Board. Las verificaciones de esta entrega usan el checkout existente,
incluido ese prerrequisito; no acreditan compilar un checkout limpio sin él.
El commit de MA-TSK-216 excluye esos archivos, el motor de subida, README y
las importaciones concurrentes. Su propietario debe confirmar/publicar la
entrega de MA-TSK-064 para que el remoto contenga la dependencia previa.
