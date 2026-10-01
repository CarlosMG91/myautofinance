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

## Dudas de cálculo y asuntos diferidos

No quedan dudas abiertas que cambien los cálculos del contrato aprobado. El signo de reales y presupuestos, la agregación por ramas, la diferencia `real − previsto`, el redondeo de la propuesta anual, el patrimonio neto y el colchón están definidos en la [especificación](especificacion.md) y comprobados con los [casos de referencia](casos-referencia.md). Una revisión futura que cambie cualquiera de estas reglas requiere actualizar también los resultados esperados de esos casos.

El formato concreto del XLS de Openbank sigue pendiente de una muestra real y se resolverá en EP-014. Esa decisión afecta al adaptador de importación bancaria, no a los cálculos ni al contrato CSV histórico de EP-001. Las fotos patrimoniales antiguas quedan fuera de la migración aprobada.

## Entregas y dependencias

T01–T09 están representados en la especificación, el contrato CSV y los casos numéricos. El usuario aprobó el conjunto el 2026-10-01 y satisfizo la revisión funcional de T10. Los artefactos de la épica **MA-EPIC-001** están entregados en Git; el estado administrativo de sus tickets se gestiona en el tablero «My autofinance». EP-002 (propuesta visual) y EP-003 (base Flutter) pueden usar ya este contrato. La épica Openbank de MyFinance es un antecedente conceptual, sin código compartido ni dependencia de ejecución.

El repositorio Git y el remoto `origin` están configurados. Los artefactos de EP-001 se confirmaron y subieron a `origin/main` sin cambios ajenos ni subida forzada.
