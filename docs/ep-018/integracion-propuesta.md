# MA-TSK-154 · Propuesta revisable en Windows y Android

Implementación de la propuesta sobre el [motor](motor-propuesta.md), el
[editor de sesión](edicion-borrador.md) y el [guardado atómico](guardado-atomico.md).
MA-TSK-151/152 figuran completados en Epic Board. Se consultó MA-TSK-154 y la
aprobación explícita de MA-TSK-153 del 2026-10-10, registrada en
[el suplemento visual](propuesta-visual.md). Se mantienen EP-001 §3/caso H y
los flujos de EP-002, sin una nueva matriz de informes.

## Entrada, periodo y borrador

Presupuesto mensual ofrece **Proponer año siguiente**. La secundaria
`/presupuesto/propuesta?a=2026` admite también `m` para conservar el origen.
Inicializa el año desde el periodo común de EP-016 y no modifica el contexto
primario mientras se edita. Cancelar vuelve al año fuente; guardar vuelve al
año destino, al mes recordado por la sesión o enero. El retorno por la pila
conserva posición y foco del botón de entrada.

El año fuente admite 1–9998. **Generar propuesta** lee datos reales mediante
los repositorios existentes. PC muestra tabla raíz × doce meses desplazable
dentro de su contenedor; Android muestra tarjetas por raíz con total anual y
doce meses desplegables. Cada mes identifica el real fuente, la propuesta
inicial y las asignaciones actuales. «Sin reales» no se presenta como un real
registrado; los ceros de las asignaciones son explícitos.

El borrador solo existe en memoria. Cambiar el campo de año no recalcula ni
cambia el año del borrador generado. **Regenerar propuesta** exige descartar
expresamente las ediciones y solo sustituye el borrador cuando la lectura
nueva termina correctamente. Un fallo conserva la instantánea anterior.

Editar aplica céntimos firmados sin redondearlos de nuevo. El desglose permite
seleccionar descendientes activos, hasta nivel tres, retirando el padre solo
de ese mes. La suma debe conservar el importe previo o coincidir con un nuevo
total escrito expresamente. Conflictos y errores conservan la distribución
anterior y los campos del diálogo para corregirlos. Los signos atípicos de
fuente o asignación exigen la casilla de revisión; editar invalida su revisión
según el contrato del editor. Los reales excluidos aparecen con fecha, motivo,
ruta disponible e importe, como advertencia no bloqueante.

## Comparación y persistencia

`BudgetSource` recibe calculador y coordinador por constructor, compuestos en
`app/budget_factory.dart` sobre la misma conexión SQLite. La pantalla conserva
el coordinador que emitió la revisión; resolver otra visita no sustituye su
identidad ni la autorización de esa revisión.

**Revisar y guardar** valida signos y estructura, contrasta la identidad de la
base activa y pide al coordinador una comparación completa. El diálogo enumera
nuevas, correcciones, sin cambio y retiradas, con mes/ruta/anterior/nuevo,
incluidos ceros y ausencias diferenciadas. La casilla de confirmación nace
desmarcada. Con existentes la acción es **Sustituir partidas**; sin existentes,
**Guardar propuesta**. Cancelar, Escape o Atrás conservan el borrador.

La escritura vuelve a comprobar la base activa y usa la revalidación y
transacción del coordinador. Solo después de persistir invalida la consulta
mensual, navega al destino y anuncia éxito. Los errores conservan el borrador.
Datos relevantes obsoletos o una base sustituida bloquean nuevos intentos de
guardar hasta regenerar y revisar expresamente. Nunca se recalculan encima de
ediciones manuales. Durante comprobación, diálogo o escritura se bloquean el
doble envío y la salida incompatible. El teclado también respeta el bloqueo
de guardado cuando no existen ámbitos activos.

No se añaden tablas, migraciones, almacenamiento de borradores, edición de
reales, fotos, Drive, inflación, porcentajes ni informes. El alcance financiero
de la sustitución sigue siendo el de MA-TSK-152.

## Verificación reproducible

Datos exclusivamente sintéticos. Flutter 3.47.0/Dart 3.13.0 comprobados con
`flutter --version` y `scripts/check-toolchain.ps1`; dependencias resueltas con
`flutter pub get --enforce-lockfile`. El SDK y el lockfile no se actualizan.

```powershell
flutter test --no-pub test/budget/budget_proposal_screen_test.dart
flutter test --no-pub -d windows integration_test/budget_proposal_test.dart --dart-define=APP_ENV=test
flutter test --no-pub -d <id-android> integration_test/budget_proposal_test.dart --dart-define=APP_ENV=test
./scripts/check-quality.ps1
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

Las 16 pruebas de widgets cubren cálculo, doce meses, edición, desglose hasta
nivel tres, total explícito, revisión de signos e invalidación, exclusiones,
cancelación de comparación, datos concurrentes, rollback SQLite y reintento,
fallo de lectura/regeneración, doble envío, propuesta vacía, periodos comunes,
ámbitos ajenos, relevo de identidad de la base antes/después de comparar y foco.
Incluyen Windows, Android, 320×800 px con texto 200 %,
Ctrl+Intro, Escape y Atrás del binding.

El recorrido nativo pasó en Windows y en el emulador Android
`Medium_Phone_API_37.0`, con JDK 17 para Gradle. Comprueba edición/desglose,
cancelación por Escape/Atrás, comparación con retirada del padre, sustitución
real y reapertura del archivo SQLite, manteniendo presupuesto fuente y reales.
Su carpeta temporal se resuelve y verifica antes de borrarla. No usa la base
personal ni exige cuentas remotas. No se verificó teléfono físico ni lector
de pantalla.

Las capturas opcionales (`PROPOSAL_CAPTURE=true`) de las pruebas usan una fuente
legible del sistema en Windows y permanecen en `.tools`, fuera del commit.

### Verificación final del 2026-10-10

El checkout contiene cambios concurrentes de sincronización, README y otros
prototipos. El HEAD inicial `0c2b486` consume APIs de subida Drive pendientes de
confirmar por su ticket. La copia `.tools/ma-tsk-154-review` conserva esas
fuentes preexistentes para compilar; se comprobó igualdad del contenido de lib,
test e integration_test, normalizando únicamente saltos de línea. No se incluyen
esas dependencias ajenas en esta entrega. Un checkout limpio del remoto necesita
que su ticket complete los cambios de sincronización.

- `scripts/check-quality.ps1`: 323 archivos con formato correcto y análisis sin
  incidencias. La batería general termina con 1.504 pruebas correctas y dos
  fallos en archivos preexistentes sin modificar: timeout de recuperación local
  en `local_recovery_journey_test.dart` y una expectativa de ruta/pendientes en
  `wealth_photo_screen_test.dart`. No se declara la batería general correcta.
- La ejecución dirigida inicial pasa 80 pruebas de propuesta, motor, editor,
  guardado y arquitectura. Se añaden dos pruebas de relevo de base activa antes
  y después de comparar; el análisis dirigido de ese archivo no tiene incidencias.
- Las cuatro variantes development/test/production/invalid-synthetic de APP_ENV
  pasan por separado, porque el fallo general detuvo el script antes de ese paso.
- Windows release y Android APK debug compilan con APP_ENV=test y los comandos
  fijados, en la copia aislada. Android usa JDK 17 mediante configuración temporal
  del ticket; no se cambia la configuración global, SDK, lockfile ni plataformas.
- Las capturas Windows y 320 px/200 % de edición/comparación se inspeccionaron.
  Los registros nativos previos de Windows y del emulador Android muestran el
  recorrido completo correcto con las mismas fuentes de lib: cancelación,
  edición/desglose, sustitución y reapertura SQLite. Esta continuación añade
  cobertura de tests y vuelve a compilar, sin cambiar esas fuentes.

La repetición aislada con concurrencia 1 termina con 39 pruebas correctas:
las 16 de propuesta, todo el archivo de recuperación local y todo el de foto
patrimonial, incluidos los dos casos fallidos en la batería general. No se
modifica código ajeno para obtener este resultado. El análisis del archivo de
pruebas actualizado y su comprobación final de formato también son correctos.
El commit y push incluyen solo los once archivos de MA-TSK-154 en la rama
configurada `ticket/ma-tsk-113`, sin forzar la subida. No se cierra la épica ni se
incluyen los archivos de sus tickets posteriores.
