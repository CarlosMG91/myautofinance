# MA-TSK-112 · Revisión e historial en Flutter

El 2026-10-07 se consultaron MA-EPIC-106 y MA-TSK-112 mediante
`GET http://localhost:4310/api/data`, tablero **My autofinance**, workspace
coincidente. MA-TSK-108/109/110/111 están completados; la aprobación de
MA-TSK-108 consta también en los requisitos facilitados por el usuario.
Se aplica su mockup conservado y EP-002. No se modifica el estado del tablero.

## Composición y entrada

`LocalBackupSession.imports()` resuelve la base activa por operación.
`createImportServices` compone previsualizador, confirmador e historial reales
de MA-TSK-109/110/111; tras confirmar invalida los consumidores del catálogo.
No hay migraciones ni modificaciones de las reglas financieras.

Gestión ofrece **Historial de importaciones** desde el índice, los marcadores,
Patrimonio y Presupuesto. CSV y XLS siguen deshabilitados. Las rutas secundarias son:

| Ruta | Contenido |
|---|---|
| `/importaciones` | Lotes confirmados, paginados |
| `/importaciones/lotes/<UUID>` | Metadatos y filas por ordinal, paginadas |
| `/importaciones/origen/<UUID>` | Originales y registro actual, o registro borrado |
| `/importaciones/revision` | Sesión común, únicamente con lanzamiento de pruebas autorizado |

`ImportReviewLaunch` recibe archivo, adaptador y ruta de origen. La composición
de la app solo acepta este lanzamiento cuando `APP_ENV=test`; development y
production no interpretan ni confirman esa entrada. El único adaptador de este
ticket está en `test/support/import_ui_fixture.dart`, fuera de `lib/` y de los
binarios. No existe botón para importar datos sintéticos en la app.
EP-013/014 incorporarán selección y lectores reales usando los puertos
existentes; deberán incorporar expresamente su entrada productiva.
Los escenarios exhaustivos del adaptador integrado pertenecen a MA-TSK-113.

## Revisión y confirmación

Se presentan Leyendo, Revisión, Confirmando, Importado, Ya importado y Error.
La tabla PC cambia a tarjetas por debajo de 840 px o con texto ampliado.
Las filas conservan ordinal, tipo, fecha/mes, concepto, importe original e
interno, cuenta, ruta, estado y consulta de campos originales. Conteos y totales
firmados se separan por tipo; BigInt evita desbordar totales y se formatean sin
double. Se paginan las filas visibles, sin limitar la validación del lote.

La referencia se resuelve para todas sus filas mediante identidad existente
o alta preparada. Las cuentas exigen nombre, vigencia y liquidez. Una categoría
nueva admite padre existente o preparado; la raíz exige elegir Ingreso/No
ingreso y el hijo hereda esa marca. El núcleo valida vigencia, profundidad,
conflictos y toda la sesión. Cambiar una decisión elimina su plan anterior,
poda antecesores preparados sin uso y borra las marcas de solapamiento.
REAL con categoría ausente se presenta Sin clasificar; presupuesto siempre
exige categoría. Ningún diálogo de referencia escribe en SQLite.

Cada solapamiento muestra el registro actual y exige revisión expresa de su
pareja ordinal/UUID; nunca elimina filas. Confirmar requiere revisión válida,
todos los avisos revisados y consentimiento independiente en «Importar todo».
SQLite revalida y confirma el lote completo. Confirmando bloquea dobles envíos,
Atrás y cierre solicitado por Flutter; no ofrece cancelar una transacción.
Un fallo conserva archivo, interpretación y decisiones, recarga la revisión y
exige revisar nuevamente los solapamientos. Una lectura fallida deshabilita
la confirmación incluso si existía una revisión anterior válida.

Cancelar el consentimiento vuelve a revisión; descartar sesión no escribe.
Una lectura pendiente descartada no puede reinstalar su resultado tardío.
El cierre nativo solicitado pide descartar la sesión; durante confirmación se
rechaza. Un cierre forzoso del proceso no es cancelación de SQLite.
El resultado anuncia persistencia local y enlaza lote/origen y periodos de
Estado, Presupuesto y Real. Repetir bytes renombrados muestra Ya importado y
cero altas, conservando correcciones y borrados.

## Historial y retornos

Las consultas usan SQLite y los cursores estables existentes, con 50 entradas
por página y sin truncar el total. El historial incluye nombre, confirmación,
origen, versiones, SHA-256 y conteos originales. El detalle conserva página al
volver de una fila. Visitar historial y regresar conserva la revisión.
«Recargar contexto» reinicia cursores tras restaurar o sustituir la base.

El origen separa campos originales de concepto/importe/fecha/cuenta/categoría
actuales, permite abrir el registro actual con su periodo y se recarga al
volver de ese registro. Destinos borrados mantienen procedencia y no ofrecen
recrearlos; lotes antiguos sin payload muestran «Original no disponible».
No se guarda el archivo completo, intentos fallidos o cancelados ni deshacer.

## Verificación

26 pruebas nuevas usan SQLite real y un adaptador sintético exclusivo de tests:
13 del controlador y 13 de interfaz/formato. Cubren lectura pendiente/error,
cancelación sin escrituras, asignaciones y altas, signos/cero, ordinales
idénticos, revisión de solapamientos, base cambiada, doble confirmación,
fallo/reintento, repetición después de borrar, invalidación tras commit,
originales/correcciones/borrados, consentimiento con Escape, historial,
paginación y retorno, enlaces de periodo y bloqueo de entrada en producción.

La interfaz se comprueba a 320, 390, 840 y 1280 px, con texto al 200 %, sin
excepciones de layout y con guías Flutter de etiquetas y objetivos táctiles.
Los mensajes de fase/error usan regiones semánticas de estado; los controles
son nativos de Material. Se inspeccionan capturas del render Flutter con Segoe
UI real en Windows y con tarjetas a 390 px/200 %, generadas en
`build/ma-tsk-112/` (artefactos locales ignorados).

Resultados locales con Flutter 3.47.0 / Dart 3.13.0:

- `check-toolchain.ps1` y dependencias con `--enforce-lockfile`: correctos.
- Formato sin cambios y análisis completo sin incidencias.
- Las 26 pruebas nuevas pasan; toda la suite pasa con
  `flutter test --no-pub --concurrency=1`: **1.147 pruebas**.
- `check-quality.ps1` se ejecutó dos veces con su concurrencia predeterminada:
  ambas ejecuciones fallaron únicamente en «Ruta conserva febrero, Atrás
  protegido y guardado actualiza origen con pendientes» de
  `wealth_photo_screen_test.dart`, al no encontrar el estado visible esperado.
  Ese archivo pasa aislado y en la suite secuencial. No se modifica Patrimonio
  ni el verificador para ocultar el fallo; queda registrada esta incidencia
  de la comprobación concurrente.
- Los casos financieros de `node docs/ep-001/verificar-casos.mjs` pasan.

- Las cuatro variantes `APP_ENV` (development, test, production y valor inválido
  sintético) pasan `environment_bootstrap_test.dart`.
- Los builds del código final pasan:
  `flutter build windows --release --no-pub --dart-define=APP_ENV=test` y
  `flutter build apk --debug --no-pub --dart-define=APP_ENV=test`.
  Android usa el JDK 17 local existente mediante `JAVA_HOME` y
  `GRADLE_OPTS=-Dorg.gradle.java.home=<ruta-JDK17>` para esa ejecución;
  el log de Gradle confirma `javaVersion=17`. No se cambia la configuración
  global de Flutter/Java ni la firma de distribución.

El análisis y las pruebas generales necesitaron permisos para cachés, pub.dev y
bloqueos SQLite; el intento de MSBuild dentro del sandbox no pudo usar FileTracker.
SDK, lockfile y contratos financieros se conservan. No se acredita un recorrido
manual en un teléfono Android ni lectura con Narrador/TalkBack: los recorridos
y la accesibilidad descritos son pruebas automatizadas y render de widgets.
Los lectores CSV/XLS reales y su validación siguen fuera de este ticket.

La entrega Git incluye únicamente estos cambios. README, Drive y los mockups
concurrentes de EP-008 permanecen fuera de su commit.
