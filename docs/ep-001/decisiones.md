# EP-001 · Registro de decisiones

**Estado:** contrato completo aprobado expresamente por el usuario el 2026-10-01; artefactos de EP-001 confirmados y subidos a `origin/main`. La tabla conserva cuáles reglas procedían directamente de sus respuestas y cuáles fueron propuestas aceptadas en esa aprobación final.

| Tema | Decisión | Origen |
|---|---|---|
| Proyecto | Nuevo e independiente de MyFinance. | Usuario |
| Plataformas | Aplicación completa en Windows y Android, Flutter, instaladores privados. | Usuario |
| Datos | SQLite local; una sola persona usuaria; Google Drive con botones explícitos de subir y descargar. | Usuario |
| Drive | Archivo en carpeta visible, sin contraseña ni cifrado adicional. | Usuario |
| Divisa | Solo EUR. | Usuario |
| Histórico | Migrar reales y presupuestos mediante un CSV nuevo; no migrar fotos patrimoniales. | Usuario |
| Formato antiguo | El ejemplo del Excel es orientativo, no el contrato CSV de la app. | Usuario |
| Categorías | Hasta tres niveles; presupuesto permitido en cualquier nivel, sin padre y descendiente a la vez para un mismo mes. | Usuario |
| Ingresos | Se identifican mediante marca explícita de categoría, no por signo. | Usuario |
| Ahorro y transferencias | Se tratan como categorías ordinarias y suman por el signo del movimiento. | Usuario |
| Discrecionalidad | Se conserva, sin filtros en la primera versión. | Usuario |
| Inversiones | Foto mensual del valor total por cuenta o cartera; sin posiciones individuales. | Usuario |
| Nuevo presupuesto | Propuesta basada en cada mes equivalente del año anterior, para ingresos y salidas; redondeo de la magnitud a la decena superior o igual. | Usuario; interpretación de múltiplo exacto propuesta |
| Fotos ausentes | Mostrar «sin dato»; no trasladar automáticamente el último valor. | Usuario |
| Indicadores | Estructura extensible; inicialmente solo colchón = activos líquidos / (ingresos anuales presupuestados / 12). | Usuario |
| Primer banco | Openbank XLS, definido en EP-014 cuando haya muestra. | Usuario |
| Fuente de EP-001 | Entrevistas y datos sintéticos; rediseño libre; una sola aprobación al final. | Usuario |
| Presupuesto interno | Entidad distinta de real; ambos usan signo económico uniforme. El CSV de presupuesto invierte el signo. | Propuesta aceptada en T10 |
| Propuesta anual | Agrupar reales por raíz antes de sugerir importes para evitar presupuestos solapados; meses sin reales se proponen como cero editable. | Propuesta aceptada en T10 |
| Foto completa | Exigir un valor para cada ficha activa del mes; deuda registrada como magnitud positiva y restada del patrimonio. | Propuesta aceptada en T10 |
| Indicador incompleto | Requerir presupuesto explícito de ingresos en los doce meses y foto completa; si no, «sin dato». | Propuesta aceptada en T10 |
| CSV v1 | UTF-8, `;`, fecha ISO, decimal con punto, columnas y validaciones de [contrato-csv.md](contrato-csv.md). | Propuesta aceptada en T10 |
| Importación | Previsualización, asignación confirmada de referencias, atomicidad e idempotencia por contenido del archivo. | Propuesta aceptada en T10 |
| Sincronización | Copia SQLite consistente, comprobación de versión, respaldo local antes de descargar y ninguna fusión automática. | Propuesta aceptada en T10 |
| Archivo activo e historial Drive | Un único `autofinance.sqlite`, actualizado sobre el mismo ID, con historial nativo sujeto a purga; sin retención indefinida. | Usuario, MA-EPIC-060/MA-TSK-061, 2026-10-02 |
| Carrera entre subidas | Detener divergencias observables antes de subir. Si Drive v3 permite condición atómica binaria comprobada, usarla obligatoriamente; si no la ofrece, aceptar que dos escritores basados en la misma versión completen y la última escritura quede activa. La comparación previa no garantiza exclusión atómica. | Excepción expresamente aprobada por el usuario en MA-EPIC-060/MA-TSK-061, 2026-10-02 |

## Evolución aprobada del árbol · EP-008 / MA-TSK-079 · 2026-10-03

Origen: criterios del ticket y de MA-EPIC-078 facilitados por el usuario.
Se mantiene máximo tres niveles, ingreso heredado de raíz, nombres duplicados
permitidos y Sin clasificar como categoría nula. El histórico sigue el UUID
y la rama actual al trasladar, incluso entre raíces Ingreso/Salida; conserva
signos, importes, fechas, meses, cuentas, discrecionalidad y procedencia.
Promover a raíz conserva la marca efectiva anterior. Cambiar directamente el
tipo de una raíz usada (referencias en ella o su descendencia) sigue bloqueado.
Archivo/reactivación afecta la rama completa y conserva referencias.

Se sustituye expresamente el bloqueo de cualquier traslado con historia que
EP-004 había concretado como protección conservadora. Los traslados válidos
se permiten con datos; los que creen presupuestos padre/descendiente en un
mismo mes se rechazan atómicamente, sin cambiar árbol, datos ni revisión.
No se modifica el indicador: consume la clasificación actual con la misma
fórmula y estados. Véanse [especificación §2.1](especificacion.md),
[casos L–O](casos-referencia.md) y [traspaso EP-008](../ep-008/arbol-categorias.md).
MA-TSK-079 registra el contrato; la adaptación del código y sus migraciones
pertenece a la implementación posterior de EP-008.

## Dudas de cálculo y asuntos diferidos

**MA-TSK-061 · 2026-10-02:** se corrige §7.1 para eliminar la promesa incondicional de bloqueo atómico entre consulta y guardado. El [informe EP-007](../ep-007/control-versiones-drive.md) registra las fuentes oficiales, peticiones del ensayo con dos escritores, clasificación y bloqueo real por falta de OAuth. No se ha demostrado que Drive ignore `If-Match` ni que lo aplique al contenido binario; las pruebas con servidor falso verifican el ejecutor, no Google. La decisión técnica provisional es no atribuir protección atómica a `version`, `headRevisionId`, una marca de operación o una consulta previa, y exigir la condición si el ensayo real la acredita en el commit de la modalidad utilizada. MA-TSK-063/064/066/069 deben consumir este resultado; MA-TSK-062 conserva versiones conocidas fuera de SQLite sin interpretarlas como un bloqueo remoto. El caso I sigue exigiendo detener la divergencia secuencial. No cambian las reglas financieras ni las garantías de descarga, respaldo y recuperación.

**MA-TSK-031 · 2026-10-01:** el requisito del usuario de liquidez histórica se concreta en periodos mensuales sin solapes y con cobertura de la vigencia del activo. Un cambio desde un mes conserva los anteriores; una corrección histórica explícita recalcula los meses afectados sin cambiar sus valoraciones. Las deudas no tienen liquidez. Véanse la especificación y el [modelo EP-004](../ep-004/modelo-datos.md). No se modifican las demás reglas aprobadas.

No quedan dudas abiertas que cambien los cálculos del contrato aprobado. El signo de reales y presupuestos, la agregación por ramas, la diferencia `real − previsto`, el redondeo de la propuesta anual, el patrimonio neto y el colchón están definidos en la [especificación](especificacion.md) y comprobados con los [casos de referencia](casos-referencia.md). Una revisión futura que cambie cualquiera de estas reglas requiere actualizar también los resultados esperados de esos casos.

El formato concreto del XLS de Openbank sigue pendiente de una muestra real y se resolverá en EP-014. Esa decisión afecta al adaptador de importación bancaria, no a los cálculos ni al contrato CSV histórico de EP-001. Las fotos patrimoniales antiguas quedan fuera de la migración aprobada.

## Entregas y dependencias

T01–T09 están representados en la especificación, el contrato CSV y los casos numéricos. El usuario aprobó el conjunto el 2026-10-01 y satisfizo la revisión funcional de T10. Los artefactos de la épica **MA-EPIC-001** están entregados en Git; el estado administrativo de sus tickets se gestiona en el tablero «My autofinance». EP-002 (propuesta visual) y EP-003 (base Flutter) pueden usar ya este contrato. La épica Openbank de MyFinance es un antecedente conceptual, sin código compartido ni dependencia de ejecución.

El repositorio Git y el remoto `origin` están configurados. Los artefactos de EP-001 se confirmaron y subieron a `origin/main` sin cambios ajenos ni subida forzada.
