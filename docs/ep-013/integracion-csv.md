# MA-TSK-120 · Importación CSV en producción

Ticket y requisitos consultados el 2026-10-08 mediante lectura de
`http://localhost:4310/api/data`, tablero **My autofinance**, con workspace
coincidente. MA-TSK-117/118/119 constan completados. MA-TSK-118 registra
aprobación explícita del mockup v1 a las `2026-10-08T07:44:47.605Z` y la
conversación «Propuesta visual aceptada». Se aplica ese suplemento a la
revisión e historial existentes de EP-012; no se modifica el tablero.

## Composición y recorrido

Gestión → **Importar CSV** abre `/importaciones/csv` en cualquier `APP_ENV`.
El origen permanece en la pila, conservando periodo y retorno. Presupuesto
protege su borrador antes de abrir la carga; Patrimonio refresca al volver.
La entrada sintética `/importaciones/revision` sigue restringida a pruebas.
XLS permanece deshabilitado.

`createCsvImportController` compone el selector nativo de MA-TSK-117,
`HistoricalCsvImportAdapter` de MA-TSK-119 y el loader SQLite de EP-012.
SHA-256 y parseo trabajan en isolates, sin SDK ni paquetes nuevos. Cada carga
conserva una instantánea inmutable de los bytes originales, sin depender de
la ruta ni volver a leer el archivo al confirmar.

Cancelar el selector, un fallo de lectura o rechazar el reemplazo conserva
la revisión vigente. Aceptar otro archivo descarta asignaciones, marcas de
solapamientos y resultados anteriores antes de preparar una nueva huella.
Se invalidan resultados tardíos de selección, preparación, parseo y lectura
de la base. Esc/Atrás cancela primero una selección pendiente; abandonar una
sesión pregunta antes de descartar. La confirmación no se puede cancelar.

La revisión reutiliza tablas PC y tarjetas Android, originales, resolución
de referencias, nuevas raíces con marca de ingreso expresa, todos los avisos
de duplicados y destinos de historial/procedencia existentes. Los errores
muestran ordinal, campo y motivo, además de línea física o byte cuando el
lector los conoce. Permanecen accesibles aunque falle la lectura SQLite.
Los fallos de parseo no muestran filas ni totales parciales: los conteos y
totales figuran como no disponibles. La corrección se hace en el original;
**Volver a cargar CSV** abre otra selección y valida todo de nuevo.

La interpretación conserva REAL e invierte PRESUPUESTO una sola vez. El
núcleo común muestra los totales firmados CSV/internos con céntimos y BigInt,
revalida contra la base actual y guarda referencias, lote, filas y originales
atómicamente. El resultado se anuncia después de persistir; un fallo conserva
la sesión y permite reintentar sin doble envío. Una huella existente muestra
**Ya importado**, cero altas y el lote existente desde la revisión, incluso
si cambió el nombre o se corrigieron/borraron sus registros.

## Verificación

Las pruebas usan exclusivamente CSV y bases SQLite sintéticos.

- Flutter 3.47.0 / Dart 3.13.0, `check-toolchain.ps1` y
  `flutter pub get --enforce-lockfile`: correctos, sin actualizar dependencias.
- Formato de lib/test/integration_test y análisis final: sin incidencias.
- Trece pruebas nuevas: selección/canal nativo, cancelación y fallos, recarga,
  huella, decisiones descartadas, resultados tardíos en cada etapa, errores
  completos incluso sin acceso SQLite, signos, referencias, avisos,
  confirmación atómica, rollback/reintento, doble envío y repetición renombrada.
  Recorrido visual a 320/412/1440 px y diagnósticos al 200 %; capturas del
  resultado inspeccionadas. Producción conserva Real enero y deshabilita XLS.
- `check-quality.ps1` final: formato y análisis correctos; **1.287 pruebas
  correctas y un timeout** en `budget_lifecycle_test.dart`, caso Android,
  esperando una lectura después del borrado. El control general no se declara
  aprobado. El primer intento también reprodujo el fallo de Patrimonio ya
  documentado por EP-012 (`Foto completa` no encontrada). No se modifican
  las pruebas ni la implementación de esas épicas para ocultar incidencias.
- Builds finales Windows release y APK debug con `APP_ENV=test`: correctos.
  Gradle confirma JDK 17; se usa JAVA_HOME/GRADLE_OPTS solo para la ejecución,
  sin cambiar la configuración global de Flutter ni la firma.
- Casos financieros EP-001 y comprobación Git de espacios: correctos.

- Regresión final de importación y arquitectura: **252 pruebas correctas**.
  Los ocho casos del controlador y cinco de pantalla nuevos pasan.
- Reintento secuencial de las pruebas ajenas afectadas: los dos recorridos
  de Presupuesto (Windows/Android) pasan. Patrimonio conserva un fallo en
  «Ruta conserva febrero, Atrás protegido y guardado actualiza origen con
  pendientes», esta vez sin encontrar `Pendientes: Z Deuda sintética`;
  los otros catorce casos del archivo pasan. Esa incidencia permanece abierta.
- Las cuatro variantes de arranque development/test/production/valor inválido
  sintético pasan tras la batería, ejecutadas expresamente porque el fallo
  general impide que el script llegue a ellas.

Logs y capturas locales: `.tools/ma-tsk-120-*`, excluidos de Git.

No se acredita un recorrido manual del selector en Windows ni en un teléfono
Android, ni pruebas reales de proveedores o de Narrador/TalkBack. El canal
nativo, la composición productiva y el recorrido se comprueban con pruebas
automatizadas; los hosts de selección corresponden a MA-TSK-117. La verificación
integral de dispositivos y los fixtures/guía siguen en MA-TSK-122/121.

La entrega se limita a los archivos de importación, su composición/navegación,
sus pruebas y esta guía. Los cambios concurrentes de README, Drive y mockup de
categorías quedan fuera del commit. No se cambian contratos financieros,
esquema SQLite, SDK, lockfile ni datos personales.
