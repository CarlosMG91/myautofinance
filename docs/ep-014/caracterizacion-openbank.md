# MA-TSK-124 · Caracterización del extracto Openbank

**Estado: bloqueado por falta de muestra verificable del usuario.**

## Reapertura: comprobación del 2026-10-18

La reapertura autorizada del 2026-10-16 exige una muestra verificable y una
caracterización contrastada antes de volver a cerrar MA-TSK-124. Este registro
no entrega la caracterización ni desbloquea MA-TSK-125 o MA-TSK-129.

Se ha vuelto a consultar `http://localhost:4310/api/data`, tablero
**My autofinance**, comprobando que su workspace corresponde a este checkout.
Las listas de adjuntos de MA-EPIC-123 y MA-TSK-124 siguen vacías. La petición
indica que los adjuntos son locales privados, pero no proporciona ninguna
ruta concreta. El ticket figura administrativamente `in-progress` durante
esta ejecución; eso no acredita que se haya resuelto el bloqueo.

La consulta `git ls-files --cached --others --exclude-standard`, filtrada por
nombres Openbank, adjuntos y extensiones XLS/XLSX/XLSB/ODS, no encuentra una
muestra. Los resultados Openbank son documentación, prototipo y código del
selector. Esta búsqueda no inspecciona carpetas privadas externas ni demuestra
la ausencia de una muestra en ubicaciones ignoradas. No se han leído bytes de
ningún extracto ni se ha deducido su formato por la extensión.

**Falta exactamente:** una ruta local privada accesible al agente que contenga
la muestra original anonimizada aportada por el usuario, conservando contenedor,
estructura y tipos, y evidencia de que la anonimización no los ha alterado.
Se ha solicitado esa ubicación. Se mantienen pendientes todos los apartados
de caracterización y el mapeo con resultados por hoja/fila descritos más abajo.
La muestra permanecerá fuera de Git; no se publica ningún extracto personal.

No se modifican MA-TSK-127/128 ni sus artefactos. No se implementa un lector
sin evidencia, ni se cambia el estado del ticket a entregado.

### Comprobaciones de esta revisión

- `node docs/ep-001/verificar-casos.mjs`: correcto; 48 presupuestos y 10 reales,
  con los resultados financieros de referencia conservados.
- Flutter 3.47.0 / Dart 3.13.0 y `scripts/check-toolchain.ps1`: correctos.
- Enlaces relativos y `git diff --check`: correctos. Los artefactos de
  MA-TSK-127/128 conservan su contenido.
- `scripts/check-quality.ps1`: el primer intento se detuvo al consultar
  `pub.dev` por restricciones de red. El reintento con acceso de red resolvió
  las dependencias con `--enforce-lockfile`, sin modificar `pubspec.lock`.
  Formato correcto (505 archivos, cero cambios) y análisis sin incidencias.
  La suite termina con **2.005 pruebas aprobadas y ocho fallidas**:
  un caso de `test/budget/budget_lifecycle_test.dart` (Windows), uno de
  `test/drilldowns/report_drilldown_journey_test.dart` (Windows), dos de
  `test/movements/pending_lifecycle_test.dart` (Windows/Android) y cuatro de
  `test/synchronization/local_recovery_journey_test.dart` (dos manuales y
  recuperación; fallo de disco tras instalar; cuarta fallida y retención;
  candidata truncada). El primer fallo incluye timeout de 45 segundos y un
  error de base ya cerrada, también descritos en el registro histórico.
  No se acredita calidad global; el script se detiene antes de las variantes
  de arranque con `APP_ENV`. Estos módulos no se modifican en este ticket.
- Logs locales ignorados: `.tools/ma-tsk-124-reapertura-2026-10-18-quality.log`
  y `.tools/ma-tsk-124-reapertura-2026-10-18-quality-network.log`.
- La revisión solo añade este registro documental; no verifica lectura,
  fechas, signos, localizaciones o resultados de Openbank. No hay cambios de
  plataforma que requieran builds Windows/Android.

## Registro histórico del 2026-10-08

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
  La suite general termina con 1.285 pruebas aprobadas y tres fallidas.
  Registra fallos por timeout de 45 segundos en
  `test/budget/budget_lifecycle_test.dart`, casos «EP-011 recorrido SQLite de
  archivo: windows» y «android»; el log incluye una base SQLite ya cerrada.
  También falla el caso «EP-001: dos manuales, restauración y recuperación
  de la anterior tras reinicios» de
  `test/synchronization/local_recovery_journey_test.dart`, con timeout de
  30 segundos y resultado `rejected` frente a `restored`. No se acredita
  calidad completa; no se ejecutan las variantes de arranque posteriores al fallo.
  Esta entrega no modifica código de presupuesto, recuperación ni SQLite.
- No se ejecutan compilaciones ni pruebas nativas Windows/Android: no hay
  cambios de plataforma ni implementación del lector que puedan verificarse.

Logs locales ignorados: `.tools/ma-tsk-124-pub.log` y
`.tools/ma-tsk-124-quality.log`. Estos controles no sustituyen la muestra
ni verifican el formato Openbank.
