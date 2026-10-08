# MA-TSK-126 · Conexión Openbank pendiente del lector

**Estado: bloqueado; adaptación no implementada.** Comprobación del 2026-10-08.

## Evidencia del bloqueo

Se ha consultado `http://localhost:4310/api/data`, tablero **My autofinance**,
workspace de este repositorio, épicas MA-EPIC-123 y MA-EPIC-106. MA-TSK-126
requiere la salida del lector de MA-TSK-125. Aunque el tablero marca
MA-TSK-124/125 como `done`, sus entregas versionadas documentan que faltan la
[caracterización verificable](caracterizacion-openbank.md) y el
[lector](lector-openbank.md). No existe salida del lector que adaptar.

Las listas de adjuntos de MA-EPIC-123 y MA-TSK-124/125/126 están vacías; la
petición no identifica una ruta local privada. La consulta de archivos
versionados y no ignorados (`git ls-files --cached --others --exclude-standard`)
solo encuentra documentación Openbank, sin XLS/XLSX ni código del lector.
Esto no demuestra que no haya una muestra o implementación fuera del checkout
o en archivos ignorados. Se ha solicitado al usuario su ubicación. No se ha
leído ningún extracto ni trasladado código de MyFinance.

El estado del tablero no acredita los criterios de los requisitos previos.
Este documento registra el bloqueo y los puntos de reutilización existentes;
no completa MA-TSK-126 ni define un formato Openbank aceptado.

## Traspaso al núcleo existente

La [guía de lectores](../ep-012/guia-lectores.md) y el
[contrato común v1](../ep-012/contrato-importacion.md) establecen estas fronteras:

| Responsabilidad | Integración pendiente con servicios existentes |
|---|---|
| Archivo | Crear `ImportFile.fromBytes` con `ImportSource.bankXls`, nombre sin ruta y `Sha256ImportFingerprint` sobre todos los bytes originales. No convertir el archivo ni normalizar bytes antes de calcular la huella. |
| Adaptador | Implementar `ImportAdapter` en `features/importing/data`, consumiendo la salida real de MA-TSK-125. Declarar `importContractVersion` (`1`) y una `formatVersion` específica, respaldada por la caracterización; esta última sigue sin determinar. Rechazar otro origen. |
| Filas REAL | Emitir únicamente `InterpretedMovement`, con `ImportAmount.economic` y fecha de valor comprobados por el lector, categoría nula, concepto y campos originales ordenados. Preservar ordinales únicos desde 2, también entre movimientos legítimamente idénticos, y localización de origen según el contrato observado. |
| Cuenta | Usar `ImportAccountReference.selectedAccount()` para mantener el destino pendiente en cada carga. La identidad detectada del extracto es informativa; no transformarla en una referencia nombrada que el resolutor pueda asignar automáticamente por coincidencia. Incorporar el UUID a `ImportReferenceBindings.accounts` solo tras elección y confirmación expresas del usuario. |
| Errores | Traducir diagnósticos del lector a `ImportIssue`, conservando hoja/fila/campo y motivo cuando estén disponibles. Cualquier error bloquea todo el lote mediante `ImportSession`; no descartar movimientos inválidos para aceptar el resto. Resolver ambigüedades conforme a la evidencia, sin inferir fechas, signos o destino. |
| Revisión | Reutilizar `ValidatingImportPreviewer` y `SqliteImportPreviewSource`, con las vinculaciones explícitas. Revisar todas las claves de `ImportOverlap`; ninguna coincidencia elimina filas. |
| Confirmación | Usar `ImportConfirmationRequest` y el confirmador entregado por `createImportServices`, respaldado por `SqliteImportBatchRepository.confirm`. Reutilizar revalidación, transacción, SHA global y resultado `ImportAlreadyImported` con cero altas. No llamar al `create` heredado ni construir un motor paralelo. |
| Historial | Reutilizar `SqliteImportHistoryRepository` para lote, versiones y originales, incluso tras editar o borrar destinos. No almacenar el archivo completo ni intentos fallidos. |

Los tipos públicos están en `lib/features/importing/importing.dart`; la
composición de servicios está en `lib/app/import_factory.dart`. El adaptador
no recibe SQLite ni catálogos. No se cambian contratos compartidos, esquema,
SDK, lockfile o rutas productivas. La integración de selector y pantalla se
coordina con los tickets correspondientes; no se habilita el lanzamiento de
prueba como importación Openbank productiva.

La importación no emite presupuestos ni actualiza fotos patrimoniales. El
núcleo ya rechaza `InterpretedBudget` para `bankXls`; los saldos informativos
solo podrán excluirse conforme a la estructura observada por MA-TSK-124/125.

## Condición para retomar y comprobar

Se requiere la muestra original anonimizada aportada por el usuario en una
ruta accesible, completar MA-TSK-124 e implementar/verificar MA-TSK-125. Si esas
entregas existen fuera de esta rama, deben estar disponibles con la evidencia
que las respalda. No se inventan un DTO del lector, hojas, columnas, formatos
de fecha, reglas de signo ni fixtures Openbank.

Con esas entregas, verificar el adaptador con fixtures sintéticos fieles al
formato caracterizado y SQLite real: fecha/signo/originales/ordinales, categoría
nula, cuenta pendiente y elección explícita, rechazo íntegro, dos reales
idénticos conservados, mismos bytes renombrados con cero altas, solapamientos
revisados sin eliminación, rollback, revalidación e historial tras reapertura
y edición/borrado. Comprobar que presupuestos y fotos permanecen intactos.
Reutilizar `test/support/import_lifecycle_journey.dart` y ejecutar las
verificaciones de calidad y plataforma que correspondan a la implementación.

## Verificación de esta entrega

- Ticket, requisitos, adjuntos, documentación de MA-TSK-124/125 y puntos de
  integración contrastados con el código de EP-012.
- Flutter 3.47.0 / Dart 3.13.0 y `scripts/check-toolchain.ps1`: correctos.
- Resolución con `--enforce-lockfile` correcta tras reintentar con acceso a
  pub.dev; `pubspec.lock` sin cambios. Formato: 270 archivos, cero cambios;
  análisis estático sin incidencias.
- `scripts/check-quality.ps1` no completa la suite general: ejecución
  interrumpida después de más de 19 minutos, con fallos y timeouts en pruebas
  de presupuesto, categorías y movimientos. No se acredita calidad completa
  ni se ejecutan las variantes de arranque posteriores a esa suite. No se
  modifica el código afectado por esos fallos.
- 76 pruebas dirigidas existentes aprobadas, ejecutadas con `--no-pub`
  y `--concurrency=1`: `import_contract_test.dart`, `import_preview_test.dart`,
  `sqlite_import_confirmation_test.dart` y `sqlite_import_history_test.dart`.
  Verifican el núcleo con datos sintéticos, incluidas cuenta pendiente,
  categoría nula, originales, ordinales, repetición, solapamientos, rollback
  e historial; no verifican un adaptador o archivo Openbank.
- `node docs/ep-001/verificar-casos.mjs`: correcto; 48 presupuestos, 10 reales
  y resultados financieros de referencia conservados. Enlaces relativos y
  `git diff --cached --check`: correctos.
- La entrega es documental. No acredita lectura, mapeo o importación de
  Openbank; no se han implementado ni probado sus criterios funcionales.
  No hay cambios de plataforma que compilar.

MA-TSK-126 permanece pendiente de sus requisitos reales. No se modifica el
estado de los tickets en Epic Board.

Logs de comprobación locales fuera de Git: `ma-tsk-126-quality.log`,
`ma-tsk-126-quality-network.log` y `ma-tsk-126-importing.log`, en el directorio
temporal de la sesión.
