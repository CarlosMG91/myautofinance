# MA-TSK-124 · Caracterización del extracto Openbank

**Estado: bloqueado por falta de muestra verificable del usuario.**
Este documento registra la evidencia disponible el 2026-10-08 y prepara la
caracterización; no define un formato bancario aceptado ni completa el ticket.

## Evidencia disponible

Se ha consultado `http://localhost:4310/api/data`, tablero **My autofinance**,
con workspace correspondiente a este repositorio. MA-TSK-124 y MA-EPIC-123
tienen sus listas de adjuntos vacías. El criterio del ticket exige:
«No completar sin muestra verificable aportada por el usuario».

La petición no incluye una ruta privada concreta. La búsqueda mediante
`git ls-files --cached --others --exclude-standard` no encuentra archivos
XLS/XLSX ni archivos identificados como Openbank en el checkout. Esta
comprobación no acredita la ausencia de un archivo en otras carpetas privadas
o ignoradas. Se ha solicitado al usuario la ruta local de la muestra.

No se han leído bytes de ningún extracto Openbank. No hay firma física,
hojas, cabeceras, filas, campos, conteos, importes ni resultados observados.
No se ha consultado ni trasladado código de MyFinance.

## Entrada necesaria para desbloquear

Se necesita un extracto exportado por Openbank, aportado por el usuario y
anonimizado conservando el contenedor y la estructura que interpreta el lector.
Debe estar disponible en una ruta privada accesible; no se debe subir el
extracto personal al repositorio.

La anonimización debe conservar hojas y su orden, posiciones de cabeceras y
filas, tipos de celda, formatos, separadores, codificación, campos vacíos,
filas informativas y reglas de fechas e importes. Sustituir identificadores
y textos personales por valores sintéticos; no volver a exportar a otro
formato como sustituto de la muestra original. Si no se puede comprobar que
la transformación conserva la estructura, registrar esa limitación y mantener
el bloqueo. Una tabla inventada o una captura por sí sola no demuestra el
formato físico del archivo.

Tras recibirla, registrar una identificación de evidencia sin ruta personal,
SHA-256 de los bytes de la muestra anonimizada, tamaño y método de inspección.
Conservar la muestra personal fuera de Git; versionar únicamente la descripción
estructural y evidencia revisada sin datos personales. Los fixtures sintéticos
fieles a esa estructura corresponden a MA-TSK-129.

## Caracterización pendiente

Todos los apartados siguientes están **sin determinar**. Ninguno puede
resolverse por la extensión `.xls` o por supuestos sobre otro banco.

| Aspecto | Evidencia y decisión que deben quedar documentadas |
|---|---|
| Formato físico | Firma de bytes, contenedor y versión reales; codificación si es texto; herramienta que permite verificarlos. |
| Hojas o unidades equivalentes | Nombres, orden, unidades con movimientos y regla de selección; presencia de hojas adicionales. |
| Cabeceras | Textos exactos, posiciones, repeticiones, celdas combinadas y marcadores que permiten reconocer la estructura. |
| Fechas | Campos existentes, tipo físico y representación; identificación demostrada de fecha de valor frente a otras fechas; calendario/sistema de fechas si procede. |
| Concepto | Campo o composición observada, espacios y saltos originales, campos vacíos y regla de conversión. |
| Importe | Campo o campos, tipo físico, precisión, separadores, moneda y regla demostrada de signo; conversión exacta a céntimos int64, sin `double`. |
| Identidad de cuenta | Ubicación y significado observado, si está presente; tratamiento anonimizado y relación con la confirmación explícita del destino. |
| Filas ajenas a movimientos | Posición y marcadores de títulos, saldos, totales, pies y blancos que realmente existan; criterio verificable para excluir cada una. |
| Localización | Hoja/unidad y fila física de cada registro y error; regla estable de correspondencia con el ordinal común, único desde 2. |
| Estructuras rechazadas | Variantes observadas que se admiten y cómo detectar estructura desconocida o errores sin aceptar parcialmente el lote. |

## Mapeo y resultados esperados pendientes

Tras inspeccionar la muestra, cada movimiento de la evidencia anonimizada debe
quedar vinculado a su hoja/unidad y fila física, campos originales ordenados,
ordinal único, fecha de valor civil, concepto, importe original y céntimos
firmados exactos. Documentar también las filas excluidas con su motivo.

Fijar el número de movimientos, total firmado exacto y resultados por fila;
anotar errores con su localización y justificar las conversiones con valores
observados. Cuando la muestra no cubra una variante, declararla no caracterizada
en lugar de presentarla como admitida. No hay actualmente valores esperados
ni un mapeo hoja/columna que puedan darse por verificados.

## Reglas ya acordadas, independientes del formato

Se mantienen [EP-001](../ep-001/especificacion.md), el
[contrato común de EP-012](../ep-012/contrato-importacion.md) y la
[guía para lectores](../ep-012/guia-lectores.md):

- Solo movimientos REAL, con entrada positiva y salida negativa, pendientes
  de categorizar; confirmar expresamente la cuenta de destino en cada carga.
- Un archivo por carga. Estructura desconocida o error bloquea todo el lote;
  ninguna alta parcial. No importar presupuestos ni actualizar fotos
  patrimoniales, aunque el archivo contenga saldos informativos.
- Huella SHA-256 sobre los bytes completos originales seleccionados: los
  mismos bytes, incluso renombrados, producen cero altas al repetirse.
- Reales legítimos iguales conservan ordinales distintos. Coincidencias con
  otro archivo requieren revisar los avisos; no se eliminan automáticamente.
- Fecha de valor determina el periodo; dinero exacto en céntimos. Los campos
  originales se conservan separados de los valores normalizados. El lector
  no escribe en SQLite ni resuelve por sí solo el destino de las referencias.

Estas reglas no identifican columnas, hojas, formatos de fecha o signos
concretos de Openbank: esa adaptación sigue pendiente de la muestra.

## Traspaso y límites de verificación

MA-TSK-125 (lector) y MA-TSK-129 (fixtures) dependen de esta caracterización
y no pueden cerrarse usando este registro del bloqueo como contrato observado.
MA-TSK-127 (selector) y MA-TSK-128 (propuesta visual) pueden avanzar dentro
de su alcance sin inventar campos bancarios.

Se han contrastado ticket, adjuntos, dependencias y contratos existentes.
No se ha verificado lectura de Openbank, mapeo, fechas/signos, localizaciones,
conteos ni resultados de un extracto. No se añade lector, fixture ni interfaz.
El ticket debe permanecer pendiente hasta recibir e inspeccionar la muestra
y completar la evidencia anterior.

Comprobaciones de esta entrega documental:

- Enlaces relativos del documento y `git diff --cached --check`: correctos.
- `node docs/ep-001/verificar-casos.mjs`: correcto; se mantienen los 48
  presupuestos, 10 reales y sus resultados financieros de referencia.
- Flutter 3.47.0 / Dart 3.13.0 y `scripts/check-toolchain.ps1`: correctos.
  Resolución con `--enforce-lockfile` correcta tras reintentar con acceso
  de red; no se modifica `pubspec.lock`.
- `scripts/check-quality.ps1`: formato sin cambios y análisis sin incidencias.
  La suite general registra un fallo por timeout de 45 segundos en
  `test/budget/budget_lifecycle_test.dart`, caso «EP-011 recorrido SQLite de
  archivo: windows», y el log incluye una base SQLite ya cerrada. No se
  acredita calidad completa ni las variantes de arranque posteriores al
  fallo. Esta entrega no modifica código de presupuesto ni de SQLite.
- No se ejecutan compilaciones ni pruebas nativas Windows/Android: no hay
  cambios de plataforma ni implementación del lector que puedan verificarse.

Logs locales ignorados: `.tools/ma-tsk-124-pub.log` y
`.tools/ma-tsk-124-quality.log`. Estos controles no sustituyen la muestra
ni verifican el formato Openbank.
