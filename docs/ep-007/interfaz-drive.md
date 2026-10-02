# MA-TSK-068 · Interfaz de copia manual en Drive

La ruta `/drive`, accesible desde Gestión → Copia en Drive en los cinco
destinos, reutiliza el mockup aprobado de MA-TSK-019 y el traspaso de
[MA-TSK-020](../ep-002/entrega-flutter.md). Conserva el origen en la pila,
con su periodo, desplazamiento y foco. No crea un nuevo mockup ni implementa
las pantallas financieras que todavía son marcadores técnicos.

La tarjeta muestra cuenta, última versión/fecha conocidas, referencia local
y cambios locales. «Remoto desconocido» no equivale a «Sin copia en Drive»:
solo una consulta expresa que acredita ausencia permite mostrar lo segundo.
Abrir, volver o redimensionar lee únicamente metadatos locales. La sesión se
restaura desde el almacenamiento seguro sin renovar ni consultar Drive.

Subir copia y Descargar última copia son acciones expresas. Se componen el
subidor con reconciliación de MA-TSK-066 y la aplicación segura de MA-TSK-067.
La autorización y la búsqueda de carpeta forman parte de esa acción; solo
Subir copia permite crear la carpeta si falta. Los fallos, divergencias y
respuestas de subida inciertas nunca se anuncian como éxito. El conflicto
muestra las versiones conocidas y ofrece Conservar datos locales o descargar.

La descarga presenta cuenta, fecha y versión antes de aplicar; cuando hay
cambios o la relación local es desconocida, advierte de su pérdida en la base
activa y del respaldo recuperable. Cancelar, Esc y Atrás conservan los datos.
La opción conservadora recibe el foco inicial y este vuelve al disparador
cuando termina la operación. Sin cambios locales continúa tras el clic sin
diálogo de pérdida. Los diálogos contienen el recorrido de foco.
El margen móvil es 16 y el ancho máximo del diálogo es 560.

Durante la operación se deshabilitan ambos botones y las salidas. Se anuncian
fases sin porcentajes inventados. La validación de descarga precede al aviso de
preparación de respaldo/sustitución/apertura; el nuevo callback opcional
`DriveDownloadApplication.onApplying` aporta esa transición sin alterar
validación, atomicidad ni recuperación. La cancelación se entrega al
coordinador seguro y espera su resultado. Una publicación remota ya en curso
inhabilita la cancelación. El éxito de descarga identifica el respaldo en
Copias locales; recuperación pendiente bloquea las acciones y ofrece abrir
esa ruta. No hay fusión, reintento ni transferencia en segundo plano.

## Configuración y recorrido nativo pendiente

La composición nativa usa los identificadores **públicos**
`GOOGLE_WINDOWS_CLIENT_ID` y `GOOGLE_ANDROID_SERVER_CLIENT_ID` mediante
`--dart-define`. Deben corresponder a los clientes registrados siguiendo
[EP-005](../ep-005/oauth-google.md). No introducir tokens, secretos ni firmas
en estos valores. Sin identificador, la vista explica el bloqueo y deshabilita
las acciones. `config/google-oauth.public.json` continúa documentando el alta
OAuth pendiente; este ticket no inventa ni registra clientes Google.

Con los requisitos nativos y OAuth preparados, recorrer en Windows Gestión →
Copia en Drive con Tab/Mayús+Tab, Intro/Espacio, Esc y foco de retorno. En
Android recorrer con tacto y Atrás; probar datos locales modificados, cancelar
y confirmar una descarga y recuperar su respaldo desde Copias locales.
Comprobar también error de red, divergencia y respuesta incierta entre dos
instalaciones sintéticas. Esta prueba con cuenta y dispositivo reales sigue
pendiente y no se sustituye por los dobles de prueba.

## Evidencia del 2026-10-02

- Flutter 3.47.0 / Dart 3.13.0: `flutter --version` y
  `scripts/check-toolchain.ps1` correctos. Dependencias resueltas con
  `flutter pub get --enforce-lockfile`, sin cambiar SDK ni lockfile.
- Formato y análisis con `--fatal-infos --fatal-warnings`: correctos.
- 21 pruebas de interacción, más 3 capturas: teclado Windows, tacto Android,
  confirmación, Esc/Atrás, foco de retorno, cancelación, exclusión de acciones,
  ausencia remota, errores, divergencia, resultado incierto y recuperación
  bloqueada. Anchos 320, 360, 412, 839, 840, 1024, 1200 y 1440, texto 200 %,
  sin excepciones de layout. Son pruebas de widgets, no una sesión nativa real.
- 30 pruebas de aplicación segura, arquitectura, navegación y arranque:
  correctas. Incluyen respaldos, fallos de apertura/sustitución, cancelación
  y recuperación tras interrupción. Los cuatro `APP_ENV` pasan por separado.
- `scripts/check-quality.ps1`: correcto en la versión final, incluidos
  formato, análisis, las 780 pruebas de la batería completa y los cuatro
  entornos de arranque. La evidencia está en `.tools/068-quality-delivery.log`.
- Capturas sintéticas revisadas con Segoe UI/Roboto en
  `.tools/068-{1440,412,320}-{reposo,confirmacion}.png`. Se regeneran mediante
  `flutter test --no-pub --dart-define=CAPTURE_DRIVE_UI=true
  test/synchronization/drive_screen_test.dart`; 320 usa texto 200 %.
- Ambos builds requeridos se intentaron con `APP_ENV=test`: Windows falla por
  ausencia de compilador C++; Android por ausencia de SDK. No se generaron
  ejecutables de aceptación. `flutter devices` no encuentra Android.

Las comprobaciones usan solo datos sintéticos y temporales dentro de `.tools`.
Esta entrega no acredita Drive real, teclado físico ni dispositivo Android.
Los logs locales `068-*` distinguen cada ejecución y no contienen credenciales.

## Alcance del commit

Al iniciar había modificaciones y archivos sin seguimiento de MA-TSK-064,
incluidos `drive_upload_factory.dart`, `drive_upload.dart` y
`validated_drive_uploader.dart`. La integración y las pruebas utilizan esos
servicios locales existentes, pero este ticket **no los incluye** en su commit
ni modifica sus archivos. Su publicación debe completarse por separado para
que un checkout del remoto disponga de todas las dependencias de EP-007.
Tampoco se incluyen los cambios previos de README, transferencia y estado de
instalación. MA-TSK-068 publica únicamente su interfaz, composición, rutas,
callback de fase, pruebas y esta documentación.
