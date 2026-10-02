# MA-TSK-058 · Copias locales desde la app

## Aprobaciones y alcance

Consulta de `GET http://localhost:4310/api/data` del 2026-10-02, tablero
**My autofinance**, workspace de este repositorio. MA-TSK-058 figura en ejecución
y coincide con el ticket facilitado; MA-TSK-056 y MA-TSK-057 están completados.
La discusión humana de MA-TSK-057 acepta el mockup v1, con aprobación del
2026-10-02T11:53:21.943Z. MA-TSK-019 está aprobado y MA-TSK-020 completado.
Se implementan el [suplemento aprobado](mockup-recuperacion-local.html) y la
[entrega EP-002](../ep-002/entrega-flutter.md); se actualiza el registro local
de aprobación sin alterar el HTML aprobado.

Gestión → **Copias locales** está disponible desde el índice técnico y los cinco
destinos existentes. Las rutas `/copias-locales` y `/copias-locales/:id` ofrecen
catálogo, creación manual, detalle, restauración y eliminación expresa. No se
añade un sexto destino. Las vistas financieras siguen siendo marcadores; las
otras entradas de Gestión se incorporarán con sus funcionalidades.

## Composición y recuperación

`LocalBackupSession` posee un único `LocalDatabaseStore` y compone los puertos
reales de MA-TSK-052/053/055. `main` presenta progreso de arranque; `initializeApp`
valida APP_ENV y abre el store, que resuelve el diario de MA-TSK-056 antes de
abrir, migrar o crear SQLite. La base ilegible ofrece directamente recuperación,
sin una ruta de datos debajo. El catálogo se consulta independientemente de la
activa. Errores de configuración conservan el fallo técnico anterior.

La presentación solo recibe puertos locales por constructor. No recibe OAuth,
HTTP, metadatos Drive, credenciales ni rutas de archivos elegidos. No inicia
conexiones remotas. Un diario pendiente detectado al arrancar, en el catálogo o
tras un fallo de restauración bloquea datos y nuevas sustituciones; requiere
reiniciar para resolverlo con el coordinador existente. Una base futura también
bloquea sustituciones y muestra el motivo de compatibilidad.

El catálogo muestra fecha/hora local con desplazamiento UTC, origen, bytes,
última comprobación y estado. Tabla desde 840 unidades lógicas; tarjetas por
debajo, márgenes 16/24/32 y lateral 200/216. Las cinco etiquetas de navegación
inferior crecen y envuelven en pantallas estrechas o con texto ampliado.
Las rutas de origen permanecen en la pila; se conservan nombre, argumentos,
periodo y estado de la vista. Los parámetros `a`/`m`, cuando existen, identifican
el periodo en Volver. Las pestañas abandonan las rutas secundarias sin apilarlas.

Crear pide confirmación de almacenamiento local. Restaurar identifica la copia,
explica la sustitución de todos los datos y exige marcar la aceptación. Cancelar,
Esc, Atrás y cierre del diálogo no invocan restauración ni respaldo. Cancelar
tiene foco inicial y devuelve el foco al control que abrió la confirmación.
Los objetivos táctiles miden al menos 48, los diálogos son desplazables y las
acciones permanecen disponibles al ampliar texto. Los estados usan regiones
semánticas de anuncio y texto explícito además del color.

Las operaciones no muestran porcentajes ni fases individuales inventadas:
los puertos actuales devuelven un resultado, sin eventos de fases internas.
Se comunica la operación pendiente (crear/comprobar/registrar o
validar/proteger/restaurar) y se bloquean navegación, Atrás y nuevas operaciones
hasta recibir el resultado seguro. El éxito solo procede de ese resultado.

Los rechazos tipados se traducen a español. Vacío, catálogo inaccesible, copia
incompleta/incompatible, validación rechazada, rollback y recuperación pendiente
tienen mensajes diferentes. `storageFailure` incluye permisos, acceso y falta de
espacio: la UI pide revisar permisos y liberar espacio, conserva copias manuales
y ofrece reintento. El puerto existente no distingue de manera fiable disco
lleno de otros errores de escritura; la pantalla no inventa ese diagnóstico.

Tras éxito se ofrece **Ver copia anterior** si existe respaldo automático. Con
activa dañada se explica el aislamiento de originales, sin prometer que sean
restaurables. La advertencia de contraste Drive pendiente no consulta la red;
la señal duradera sigue siendo la publicada por MA-TSK-055/056. Limpieza pendiente
se anuncia conservando el exceso. Manuales indefinidas y retención de tres
automáticas permanecen a cargo de los servicios existentes.

## Verificación y límites

Datos exclusivamente sintéticos. Las pruebas de interfaz comprueban cancelación
y foco, confirmación con aceptación, bloqueo de Atrás en operación, acceso desde
arranque fallido, errores de almacenamiento y validación, rollback, diario
pendiente, catálogo inaccesible distinto de vacío y retorno a los cinco destinos
y a un periodo explícito. Revisan 320/360/412/839/840/1024/1199/1200/1440 con
texto 200 %, sin excepciones de layout y con los controles alcanzables por scroll.

Las pruebas de sesión usan SQLite y disco reales: creación catalogada,
cancelación sin perder ediciones, restauración con respaldo, señal de contraste,
base ilegible con conservación de los bytes originales y rechazo de huella
alterada antes del intercambio. Se ejecutan fuera del sandbox porque la
verificación de enlaces necesita resolver los antecesores del temporal Windows.

Resultados del 2026-10-02: Flutter 3.47.0 / Dart 3.13.0 correctos;
`scripts/check-quality.ps1` completo correcto, formato sin cambios, análisis sin
incidencias, **619 pruebas correctas** y cuatro variantes adicionales APP_ENV
correctas. Resolución con `--enforce-lockfile`, sin cambiar SDK, paquetes o
lockfile. `node docs/ep-001/verificar-casos.mjs` y `git diff --check` correctos.
La captura opcional pasó sus 19 pruebas de interfaz y generación de imágenes;
después se añadieron las dos pruebas de periodo/diario incluidas en las 619.

Ambas compilaciones se intentaron con los comandos fijados: Windows release
bloqueado por falta de Visual Studio C++; APK debug bloqueado por falta de
Android SDK. No se acredita un binario nativo compilado ni ejecución física.

Capturas del renderer Flutter con Segoe UI/Roboto cargadas localmente:
[Windows 1440](verificacion-app/windows-catalogo.png),
[Android 412](verificacion-app/android-catalogo.png) y
[confirmación 320, texto 200 %](verificacion-app/confirmacion-320-texto-200.png).
Se inspeccionaron visualmente; son renders de widgets, no capturas de dispositivos.
Reproducción opcional en Windows:

```powershell
flutter test --no-pub --dart-define=CAPTURE_BACKUP_UI=true test/synchronization/local_backup_screen_test.dart
```

Escribe los PNG en `.tools/`, con fixtures sintéticos y fuentes locales; las
capturas opcionales no forman parte de las pruebas CI ni cambian dependencias.

La comprobación en Android físico, lector de pantalla del sistema, alto contraste
nativo y cierre forzado del proceso en dispositivos sigue pendiente. Las pruebas
automatizadas de widgets y SQLite no acreditan esos recorridos nativos.
