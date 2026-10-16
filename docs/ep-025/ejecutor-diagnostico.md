# MA-TSK-198 · Ejecutor manual de diagnóstico

## Alcance y composición

Consulta de solo lectura de `http://localhost:4310/api/data` el 2026-10-16:
tablero **My autofinance**, MA-EPIC-196, MA-TSK-198 en curso y requisito
MA-TSK-197 completado. Descripción y criterios coinciden con la petición;
sin adjuntos. No se modifica el estado administrativo del tablero.

Se implementa el [catálogo T01](contrato-diagnostico.md) sin cambiar EP-001.
`DiagnosticExecutor` recibe `DiagnosticReadSource`; la implementación SQLite
vive junto a los repositorios en app, sin importar Drift desde el dominio.
`createDiagnosticExecutor(store: store)` compone pasivamente el acceso local y
el proveedor/cálculo real EP-023, ya presentes en este checkout. No se conecta
ninguna ruta ni se ejecuta al arrancar: la UI y su aprobación pertenecen a T05.

El adaptador reutiliza `integrity_check`, `foreign_key_check` y las consultas
`categoryIntegrityErrors`, `movementIntegrityErrors`, `wealthIntegrityErrors`,
`accountCoverageErrors` y `budgetIntegrityErrors`. Antes de la consulta recursiva
de presupuesto comprueba el árbol para evitar ciclos ilimitados. Un fallo
físico acreditado se conserva como `IntegrityEvidence` con recuperación local;
los controles dependientes quedan no ejecutados. Una base que no permite leer
su marcador produce fallo de sesión con `OpenLocalRecovery`, nunca un marcador
inventado ni un resultado conforme. No se modifica la apertura protegida EP-004.

Las referencias se identifican desde las claves foráneas reales del esquema,
con propietario, campo y destino ausente; una categoría nula no infringe FK.
Los conflictos recorren todos los meses persistidos, con el árbol actual,
categorías archivadas y partidas cero, conservando las dos identidades y su mes.
Las lecturas de movimientos y lotes reutilizan sus repositorios sin quedarse
en la primera página. Los orígenes conservados tras borrar su destino son válidos.

`importMovementMatch` extrae el criterio existente EP-012 al dominio propietario
de importación: cuenta, fecha de valor, céntimos y concepto `trim/toLowerCase`.
Lo consumen tanto la previsualización como el diagnóstico; no hay nuevo lector
CSV/XLS ni otra normalización. Solo se comparan movimientos importados de lotes
distintos. Los pares se conservan como avisos con UUID, lote y ordinal. La misma
SHA persistida en dos lotes distintos es un error separado. No se requiere el
archivo original ni se infieren datos originales ausentes.

Fotos pendientes se consultan únicamente para el mes elegido mediante
`SqliteWealthRepository.read`. El indicador usa el motor EP-023 con repositorios
y unidad de lectura de esa misma conexión/snapshot, sin nuevas fórmulas.
Se preservan evaluación, versión, causa prioritaria y detalle originales.
Comprobador ausente, fallo técnico, causa no adaptada o evaluación de otra
revisión quedan no ejecutados. Corrupción estructural impide presentar como
fiables las lecturas financieras dependientes. Meses sin presupuesto no son
errores; cero registrado no es ausencia; no se concilian saldos con movimientos.

## Consistencia, vigencia y cancelación

La primera lectura del marcador dentro de `database.transaction` fija el
snapshot que comparten controles, repositorios y proveedor del indicador.
Se comprueba el marcador antes de abrir la transacción, después de cada regla
y después de cerrarla. Si cambia, se descarta toda la ejecución mediante
`DiagnosticFailed(changedDuringRead)`. No se mezclan resultados de snapshots.
Las transacciones actuales Drift reservan la escritura: otro escritor SQLite
queda bloqueado incluso en WAL; su fallo no se convierte en conformidad.

La revisión consta de dataset, revisión de datos y generación de conexión.
La generación es única por instancia de `LocalDatabase` durante el proceso,
compartida entre adaptadores: reconstruir el ejecutor no rehabilita un informe
previo. El store resuelve la conexión activa en cada consulta; cerrar/reabrir o
restaurar cambia la generación aunque UUID y revisión restaurados coincidan.

Traspaso a T05:

1. Conservar el ejecutor y llamar a `execute(month, cancellation: token)` solo
   por petición explícita. Un token cancelado no se reutiliza para repetir.
2. `DiagnosticCompleted.report` incluye fecha, mes, revisión y las nueve reglas.
   Una regla no ejecutada impide conformidad global.
3. `DiagnosticFailed` carece de informe financiero; expone motivo y reglas no
   ejecutadas. Error de lectura ofrece el destino `OpenLocalRecovery` existente.
4. Consultar `isCurrent(report, month)` al volver a la vista y tras notificaciones
   de edición/restauración. Si falla la lectura de vigencia, devuelve falso.
   Presentar como vigente exige esa comprobación; el informe es inmutable y no
   se actualiza ni se repite automáticamente. Cambiar mes también lo invalida.
5. La cancelación se comprueba entre reglas y tras las esperas; no interrumpe
   una sentencia SQLite en curso, pero descarta su resultado al recuperar control.

No hay escrituras de entidades/revisión desde el ejecutor, reparación,
eliminación/fusión de duplicados, historial, exportación, Drive ni nuevos objetos
de esquema. Las acciones conservan el contrato T01 para navegación contextual.

## Verificación

Todas las pruebas nuevas están en
`test/diagnostics/sqlite_diagnostic_executor_test.dart`. Solo utilizan memoria
SQLite o directorios temporales privados con datos sintéticos. Las corrupciones
se crean después de abrir una base de prueba validada; nunca se rebaja la
protección productiva. Los escenarios comparan todas las tablas y la revisión
antes/después de diagnosticar. Las únicas escrituras de carrera son inyectadas
expresamente desde fixtures de test.

| Criterio | Evidencia |
|---|---|
| Referencia inválida frente a categoría nula/archivada | FK de categoría y procedencia con IDs/campo/destino; nulo pendiente y archivada válida. |
| Conflicto con IDs/mes | Raíz/nieto históricos, cero y archivo; árbol cíclico sin recursión ilimitada. |
| SHA, ordinal y origen disponibles | Dos lotes con SHA repetida en esquema sintético; lotes antiguos sin originales; origen de destino borrado válido. |
| Coincidencia distinta de corrupción | Dos Café del mismo lote conservados sin aviso; entre lotes se conservan ambos pares como avisos. Regresión del preview EP-012. |
| Solo lectura y fotos manuales | Comparación integral de tablas/revisión; foto cero, alta/baja inclusivas, fichas futuras y mes independiente. |
| Indicador propietario | Proveedor/cálculo real, causa prioritaria y cero calculable; ausencia/fallo del comprobador no ejecutados. |
| Cancelación/error sin falso conforme | Cancelación previa/durante control, base no accesible y archivo ilegible conservado byte a byte. |
| Integridad fallida y recuperación | Violación CHECK sintética conserva evidencia y detiene dependientes con destino de recuperación. |
| Cambios/restauración | Edición, cambio de mes, marcador durante/después del snapshot y restauración real mediante copia local con igual dataset/revisión y nueva generación. |

Comprobaciones locales del 2026-10-16:

- Flutter 3.47.0 / Dart 3.13.0, `check-toolchain.ps1` y
  `flutter pub get --enforce-lockfile`: correctos; lockfile intacto.
  La consulta inicial a pub.dev falló bajo sandbox y se resolvió al habilitar
  acceso de red, sin actualizar SDK ni dependencias.
- Análisis estático completo, también tras incorporar la restauración real:
  sin incidencias. Formato final de los archivos propios: sin cambios.
- Diagnóstico, contrato y arquitectura: 50 pruebas correctas (19 nuevas del
  ejecutor, 29 de T01 y dos de arquitectura). La batería general incluye la
  variante final de restauración real mediante el servicio de copias existente.
- Regresión dirigida de importación, repositorios financieros e indicadores:
  174 pruebas existentes correctas. La cobertura nueva distingue bloqueo del
  escritor WAL de cambio de revisión durante/al cerrar el snapshot.
- `node docs/ep-001/verificar-casos.mjs`: correcto, 48 presupuestos y diez reales;
  contrato financiero y signos conservados.

- `scripts/check-quality.ps1`: formato de 469 archivos sin cambios, análisis
  sin incidencias y batería general con **1.947 pruebas correctas y cuatro
  fallos** en 15 min 05 s. Dos son los fallos previos de
  `pending_lifecycle_test.dart`, Windows/Android (`Bad state: No element`,
  `pending_lifecycle_journey.dart:144`), documentados antes de este ticket en
  [T01](contrato-diagnostico.md) y
  [proveedor EP-023](../ep-023/proveedor-entradas.md). Los otros dos afectan a
  `local_recovery_journey_test.dart`: timeout de 30 s y fallo posterior del
  canal/rollback tras ese timeout. No se modifican esos archivos.
- Repetición aislada secuencial de diagnóstico, contrato, arquitectura y todo
  `local_recovery_journey_test.dart`: **58 pruebas correctas** en 2 min 16 s
  (50 de diagnóstico/contrato/arquitectura y ocho de recuperación). Los dos
  fallos de recuperación de la batería general no se reproducen aislados;
  el script general conserva su resultado fallido y no se anuncia verde.
- El fallo general detiene APP_ENV; se comprueban sus cuatro variantes por
  separado: `development`, `test`, `production` e `invalid-synthetic`, una
  prueba correcta cada una.

No se ejecutan builds nativos: este ticket no modifica plataformas ni UI.
La integración de pantalla, sus enlaces y la aceptación visual siguen siendo
responsabilidad de T05/T06 y EP-026. Los tests de widgets de la batería no se
presentan como evidencias del runner nativo.

Se conservan fuera del commit README, sincronización y los artefactos
concurrentes encontrados al iniciar. Solo se incluyen los nueve archivos
propios de MA-TSK-198 en la rama configurada `ticket/ma-tsk-193`; el remoto
consultado coincide con el punto de partida `465a65e`. No se fuerza la subida.
