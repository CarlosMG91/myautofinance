# MA-TSK-040 · Contrato de entrega de persistencia

EP-004 entrega persistencia local, sin pantallas, parsers, informes finales ni
conexión Drive. El contrato funcional aprobado sigue en
[EP-001](../ep-001/especificacion.md). Los datos de pruebas son sintéticos.

## Composición y API

App crea un único `LocalDatabaseStore`, espera `open()` e inyecta esa misma
`LocalDatabase` en todos los adaptadores `Sqlite*Repository` de
`lib/app/data/sqlite/`. Los consumidores reciben los puertos publicados por
las entradas de features; no dependen de Drift ni consultan SQL directamente.
El propietario cierra el store al terminar o antes de sustituir archivos.
Las instancias de repositorios se reconstruyen después de una reapertura.

| Puerto (feature) | Operaciones y contrato |
|---|---|
| `CategoryRepository` (movements) | Crear, editar, archivar y consultar árbol de tres niveles; ingreso marcado en raíz. Véase [categorías](categorias.md). |
| `AccountRepository` (wealth) | `create`, `get`, `listForMonth`, `history`, `rename`, `close`, `changeLiquidity`, `correctHistoricalLiquidity`; baja inclusiva, periodos sin huecos ni solapes. Véase [cuentas](cuentas-liquidez.md). |
| `MovementRepository` (movements) | Alta, edición, borrado, detalle y lecturas `readMonth`/`readYear`; cuenta obligatoria, categoría opcional, céntimos firmados no nulos. Véase [movimientos](movimientos-importacion.md). |
| `BudgetRepository` (budget) | `create`, `edit`, `delete`, `get`, `list`, `readYear`; cero explícito permitido, sin cuenta ni padre/descendiente simultáneos por mes. Véase [presupuestos](presupuestos.md). |
| `ImportBatchRepository` (importing) | `create` recibe filas interpretadas y referencias resueltas; `getByFingerprint` consulta SHA-256. Lote y registros se confirman juntos. |
| `WealthRepository` (wealth) | `setValue`, lectura mensual y `readYear`; estados ausente, incompleto y completo, con pendientes. Fotos manuales del día 1. Véase [fotos](fotos-patrimoniales.md). |
| `UnitOfWork` (core) | `run` agrupa llamadas esperadas y revierte datos y revisión al fallar; `readState` devuelve `datasetId` y `revision`. |
| `LocalBackupSource` (synchronization) | `createConsistentBackup` produce un archivo nuevo validado y su estado capturado, fuera de una transacción abierta. |

```dart
final store = LocalDatabaseStore();
final db = await store.open();
final movements = SqliteMovementRepository(db);
final budgets = SqliteBudgetRepository(db);
final batches = SqliteImportBatchRepository(db);
// Inyectar estos adaptadores y db como UnitOfWork en el coordinador.
// Esperar cada llamada dentro de db.run; no pedir decisiones al usuario allí.
final state = await db.readState();
final backup = await store.createConsistentBackup();
// backup.state identifica la copia; state puede cambiar por ediciones posteriores.
await store.close();
```

Este fragmento muestra composición, no un servicio de importación ni de Drive.
Cada repositorio valida sus entradas y ofrece errores de dominio; infraestructura
ofrece `DatabaseFailure`. No presentar SQL, rutas privadas ni excepciones nativas
al usuario. Consultar las declaraciones de los puertos para firmas completas.

## Límites para las épicas siguientes

- CSV: interpretar UTF-8 y entrecomillado, validar archivo completo y resolver
  referencias en previsualización sin escrituras. SHA-256 identifica los bytes
  originales; ordinal desde 2 distingue filas idénticas. Usar
  `BudgetInput.fromHistoricalCsv` una sola vez para invertir el signo, después
  pasar céntimos internos a `ImportedBudget`. Reconfirmar contra el estado vigente
  y agrupar referencias y lote en `run`. No deduplicar movimientos por parecido.
- Openbank: `ImportSource.bankXls` admite persistir filas interpretadas; el formato
  XLS concreto sigue pendiente de EP-014. No aplicar la inversión del CSV histórico
  a datos bancarios ni inventar reglas de conciliación.
- Informes: [lecturas](consultas-lectura.md) entrega registros, no totales finales.
  Agregar directos y descendientes una vez; total general suma raíces y sin
  clasificar. `incomeOnly` usa la raíz, no el signo. No repartir presupuesto padre
  entre hojas. Foto ausente/incompleta produce «sin dato»; cero explícito es válido.
  Colchón usa líquidos de la foto e ingresos anuales presupuestados / 12;
  verificar los doce meses y denominador positivo antes de dividir.
- Drive: [copias](transacciones-copias.md) entrega una imagen SQLite consistente
  con WAL incluido, conservada y validada. El consumidor gestiona retención.
  No copiar el archivo principal abierto ni llamar a backup dentro de `run`.
  Autenticación, transferencia, versión remota conocida, divergencia, confirmación
  de reemplazo, respaldo previo y recuperación siguen pendientes; no hay fusión
  automática ni sincronización en segundo plano.

## Traspaso a EP-008 · MA-TSK-079

Reutilizar `CategoryRepository`, `CategoryNode`, `SqliteCategoryRepository` y
`categories`; no crear otro catálogo ni regenerar UUID. Las reglas vigentes
están en [EP-001 §2.1](../ep-001/especificacion.md#21-gestión-del-árbol--ep-008--ma-tsk-079)
y los casos L–O en [casos de referencia](../ep-001/casos-referencia.md).
El [contrato EP-008](../ep-008/arbol-categorias.md) identifica las protecciones
de EP-004 que deberán adaptarse: bloqueo general de cambio de padre en el
repositorio y trigger de historia, validación de presupuestos contra el árbol
resultante y política de reconocimiento/migraciones. Esta entrega documental
no modifica el esquema v6, los snapshots ni el comportamiento del adaptador.

Las lecturas de MA-TSK-039 ya entregan UUID y árbol actual, y `incomeOnly` usa
la raíz sin filtrar por signo ni archivo. Al implementar traslados, verificar
que el histórico sale de la rama anterior y aparece una sola vez en la nueva;
los totales generales firmados y las fotos patrimoniales se conservan.
La revisión aumenta una vez por transacción de negocio efectiva y permanece
intacta ante rechazo o no-op. No alterar la fórmula del indicador.

## Esquema y migraciones

La versión física vigente es **6**, `application_id = 0x41464e43`. Los pasos son
0 sintética → 1 metadatos → 2 categorías → 3 cuentas/liquidez → 4 movimientos/lotes
→ 5 presupuestos → 6 fotos. La v0 nunca fue publicada y solo se reconoce su
estructura sintética exacta. Los snapshots versionados están en
`drift_schemas/autofinance/`; `schema_policy.dart` reconoce estructuras y valida
integridad, FK y relaciones financieras. La documentación de MA-TSK-032 describe
el estado inicial v1, no el estado completo actual.

Para cambiar esquema: incrementar versión, mantener snapshots publicados,
añadir pasos SQL consecutivos explícitos en la infraestructura y actualizar la
política de reconocimiento. Exportar con `dart run build_runner build` y
`dart run drift_dev make-migrations`. Probar creación limpia y cada versión
soportada, conservación de datos/linaje/revisión, copia previa y rollback del
fallo intermedio. El store valida antes de escribir y conserva un respaldo
`pre-v<destino>-<uuid>`; una migración técnica no aumenta revisión financiera.
No resetear una base incompatible ni abrir versiones futuras para escritura.

## Evidencia automatizada

`test/persistence/report_reads_test.dart`, caso **MA-TSK-040**, prepara una base
de fichero nueva mediante repositorios: jerarquía y cuentas, lote con diez reales
(dos Café legítimos), 48 presupuestos y foto completa de enero. Compara todas
las tablas antes/después de una unidad fallida que modifica referencias,
movimientos y foto y después intenta el presupuesto padre inválido. Conserva
datos y revisión. Cierra y crea un propietario nuevo, compara todo el contenido,
crea copia consistente y abre esa copia mediante Drift.

Sobre base reabierta y copia comprueba versión/formato, `foreign_key_check`,
`integrity_check`, linaje/revisión y consultas con los casos A–G: enero 122.975
céntimos, febrero 109.990, anual real 232.965, presupuesto anual 1.320.000,
líquidos 900.000, activos 1.900.000, neto 1.400.000 y colchón 3 meses. Febrero
permanece sin foto. Las pruebas vecinas cubren ramas, ingresos incompletos,
liquidez histórica y lectura sin mutación; las pruebas de infraestructura
cubren migraciones y fallos. Este recorrido se ejecuta en host con SQLite real;
no acredita ejecución nativa Android/Windows ni Drive.

```powershell
flutter test --no-pub test/persistence/report_reads_test.dart
./scripts/check-quality.ps1
node docs/ep-001/verificar-casos.mjs
```

Verificación local del 2026-10-01: Flutter 3.47.0 / Dart 3.13.0,
check-toolchain y resolución con enforce-lockfile correctos, sin cambios de
dependencias. check-quality completo: formato, análisis sin incidencias,
77 pruebas y cuatro variantes de APP_ENV. Comprobador de EP-001 y
`git diff --check` correctos. No se ejecutaron builds ni integración en
dispositivos: el cambio añade pruebas de host y documentación, sin modificar
código de plataforma. Epic Board no está disponible en esta sesión; se utilizó
el ticket completo proporcionado y no se cambió su estado administrativo.
