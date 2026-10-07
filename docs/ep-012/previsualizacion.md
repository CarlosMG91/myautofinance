# MA-TSK-109 · Previsualización y asignaciones explícitas

Ticket y dependencia MA-TSK-107 contrastados el 2026-10-07 por lectura de
`http://localhost:4310/api/data`, tablero **My autofinance**. Se conservan las
reglas de [EP-001](../ep-001/especificacion.md), el
[contrato histórico](../ep-001/contrato-csv.md), los
[casos de referencia](../ep-001/casos-referencia.md) y los contratos entregados
de movimientos, presupuesto y catálogos. No se cambia el estado del tablero.

## Composición y lectura

`ValidatingImportPreviewer` implementa el puerto de MA-TSK-107. Recibe por
constructor `ImportPreviewSource`, que solo permite leer. El dominio consume
las entradas públicas de movements, budget y wealth; la dependencia adicional
con wealth proporciona `AccountRecord`, `Month` y `Liquidity`, sin crear un
catálogo paralelo ni modificar el esquema. Se conservan las fronteras de capas
y el grafo acíclico.

App aporta `SqliteImportPreviewSource`: consulta los catálogos completos,
incluidas categorías archivadas y cuentas con vigencia pasada/futura; la huella
del archivo; y todos los movimientos/partidas de los meses presentes en la
sesión. Las lecturas comparten una transacción SQLite de lectura. No se utiliza
`writeTransaction`, no se crean lotes, referencias, fotos ni intentos fallidos,
y no se incrementa la revisión local. No se limita la búsqueda de solapamientos
a la página visible de movimientos.

```dart
final previewer = ValidatingImportPreviewer(
  SqliteImportPreviewSource(database), // composición en app
);
final review = await previewer.preview(session, bindings: chosenBindings);
// Presentar issues, pendingReferences y overlaps antes de solicitar confirmar.
final request = ImportConfirmationRequest(
  review: review,
  reviewedOverlapKeys: explicitlyReviewedKeys,
);
```

## Resolución

Las referencias del contrato comparan nombres por `trim` y minúsculas, nivel
por nivel. No eliminan acentos, puntuación ni espacios interiores. La misma
referencia agrupa todos sus ordinales. Una coincidencia única se vincula a su
identidad existente; varias coincidencias devuelven candidatos y exigen una
elección expresa. No se filtra una categoría archivada para escoger otra
identidad silenciosamente. Las rutas completas distinguen ramas con nombres
iguales; las identidades siguen siendo UUID.

`ImportReferenceBindings.accounts/categories` permiten vincular expresamente
a otra identidad existente. `newAccounts/newCategories` contienen planes
inmutables en memoria. La decisión se aplica a todas las filas de la referencia
normalizada. Vincular y proponer un alta simultáneamente es un error. Se
rechazan planes sobrantes para evitar altas ajenas a las filas del lote.

Un plan de cuenta exige nombre, vigencia y liquidez; siempre crea conceptualmente
una ficha de tipo cuenta. Se valida el intervalo y que cada fecha de valor esté
dentro de su vigencia mensual inclusiva. Las cuentas existentes también se
validan por tipo y vigencia, sin alterar sus fotos.

`ImportCategoryTarget` distingue UUID existente de referencia a un plan, sin
inventar UUID. Un plan de categoría exige nombre y padre explícito si es hijo.
Solo una raíz nueva admite y exige `isIncome` elegido expresamente; un hijo
debe dejarlo nulo y hereda la marca. No se deduce del signo de ninguna fila.
Los antecesores propuestos se validan aunque no tengan filas directas: padre
existente activo, plan presente, ausencia de ciclos y máximo tres niveles.
Los errores del padre propuesto también señalan los ordinales de sus filas
descendientes afectadas.

REAL con categoría nula permanece Sin clasificar y no propone categorías.
REAL exige cuenta resuelta, incluida la referencia bancaria de selección
global. PRESUPUESTO exige categoría desde el tipo interpretado y nunca tiene
cuenta. Categorías desconocidas quedan pendientes; las archivadas no admiten
nuevas asignaciones. Los nombres duplicados siguen permitidos por los catálogos.

## Validación y revisión

Se recorre todo el lote y se mantienen los errores del lector y de la sesión:
versión, lote vacío, ordinales y convención de signos. La revisión no permite
solicitar confirmación con ningún error o referencia obligatoria pendiente.
Devuelve candidatos, ordinales afectados, campo/motivo, conteos por tipo y
totales firmados originales e internos con BigInt. Se conservan las filas,
campos originales, concepto y discrecionalidad; los presupuestos no se invierten
una segunda vez.

Los presupuestos se comparan después de resolver identidades, incluidos planes:
mismo nodo y mes o relación padre/descendiente en cualquiera de las dos
direcciones bloquean el lote. Se comparan todas las filas entre sí y con todas
las partidas guardadas del mes, incluidos ceros y categorías archivadas,
bajo el árbol actual. Hermanas y meses distintos son válidos. No se reemplazan,
reparten ni eliminan partidas para resolver un conflicto.

Un movimiento importado de otro lote genera un aviso si coinciden cuenta,
fecha civil de valor, céntimos firmados y concepto tras trim/minúsculas. No se
compara por categoría ni se aplican las reglas de búsqueda sin acentos de EP-010.
Los movimientos manuales no representan otro archivo y no generan este aviso.
Cada pareja ordinal/UUID existente tiene una clave; el contrato exige revisar
expresamente todas las claves antes de crear `ImportConfirmationRequest`.
Dos filas iguales con ordinal distinto permanecen en la sesión, los conteos y
los totales. Los avisos nunca eliminan filas.

Si la huella corresponde al mismo lote, sus registros propios no se consideran
otro archivo ni provocan conflictos contra sí mismos. Cambiar el nombre no
cambia esa identidad. El resultado definitivo de repetición segura, incluso
tras correcciones/borrados, corresponde al confirmador MA-TSK-110.

## Verificación y traspaso

Las pruebas sintéticas de dominio cubren resolución normalizada y ambigua,
asignación global, originales/signos/conteos, Sin clasificar, errores completos,
catálogos y vigencia, altas expresas, raíces sin inferencia por signo,
antecesores inválidos, tres niveles/ciclos, planes sobrantes, conflictos,
solapamientos y revisión de todas sus claves. Las pruebas SQLite comparan todas
las tablas y `local_mutation` antes/después de revisiones válidas, pendientes,
erróneas, repetidas y descartadas. Incluyen una coincidencia fuera de las
primeras 100 filas, un presupuesto cero archivado y los mismos bytes renombrados
tras editar/borrar datos.

La confirmación transaccional y conservación persistente de originales quedan
en MA-TSK-110; historial, UI y adaptador sintético integrado en sus tickets.
No se implementan lectores CSV/XLS ni se conecta el motor al arranque. No se
cambian plataformas, SDK ni lockfile; los builds y recorridos nativos no se
ejecutan en este ticket de dominio y lectura SQLite.

Resultados locales del 2026-10-07, Flutter 3.47.0 / Dart 3.13.0:

- `flutter --version` y `check-toolchain.ps1`: versiones fijadas correctas.
- Dependencias resueltas con `--enforce-lockfile`, sin modificar lockfile.
- 45 pruebas dirigidas de importación y arquitectura aprobadas, incluidas
  21 de dominio de previsualización y cinco de su fuente SQLite real.
- `scripts/check-quality.ps1` completo: formato sin cambios, análisis sin
  incidencias, 1.081 pruebas aprobadas y las cuatro variantes `APP_ENV` correctas.
- `node docs/ep-001/verificar-casos.mjs`: resultados de referencia conservados.

La resolución de dependencias requiere acceso a pub.dev y las pruebas generales
de recuperación SQLite requieren bloqueos de fichero: calidad ejecutada fuera
del sandbox. Los cambios concurrentes de Drive, README y diseño EP-008 quedan
fuera de la entrega de MA-TSK-109.
