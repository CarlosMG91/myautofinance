# MA-TSK-087 · Contrato de movimientos reales

Este contrato concreta EP-010 sobre la persistencia común de EP-004. Es la referencia para las operaciones de movimiento; no implementa repositorios, pantallas ni cambios SQLite. Las reglas financieras base siguen siendo las de [EP-001](../ep-001/especificacion.md). Los casos sintéticos están en [casos de referencia](casos-referencia.md).

## Registro y escritura

- Un movimiento real tiene UUID canónico estable, cuenta de tipo `account`, fecha civil de valor, concepto no vacío, importe firmado INTEGER en céntimos, categoría directa opcional, discrecionalidad opcional y procedencia opcional. El importe no puede ser cero. Entrada/salida se expresa solo por el signo; nunca se infiere por categoría, concepto ni transferencia.
- La fecha de valor determina el periodo. La cuenta debe estar vigente en ese mes. Se conservan concepto, fecha civil y céntimos sin redondeo. Duplicados con UUID diferente son legítimos, aunque sus campos visibles coincidan.
- Categoría es el UUID de un nodo directo a cualquier profundidad (raíz, nivel 2 o nivel 3), o NULL para «Sin clasificar». No se materializan categorías heredadas en el registro. Una categoría archivada existente se puede conservar al editar; no se ofrece para nuevas asignaciones.
- Discrecionalidad es texto opcional editable, normalizado como NULL si queda vacío tras trim. No altera signo, subtotal ni elegibilidad de listados.
- Editar actualiza solo los campos expresamente editados. Conservar UUID, `import_row_id`/lote de origen y todo campo no editado, incluida la discrecionalidad al editar otros campos. Editar discrecionalidad cambia solo ese campo. Borrar explícitamente conserva fila y lote como procedencia histórica; no permite reimportar para resucitar el movimiento.
- Toda escritura usa los repositorios EP-004 y su `UnitOfWork` compartido. Validar UUID, cuenta/tipo/vigencia, fecha gregoriana, concepto, importe entero no cero en rango int64 y categoría existente/asignable antes de confirmar. Toda operación individual incrementa revisión una vez si cambia datos; no-op o error no la incrementa.

## Lectura, búsqueda y agregados

La consulta admite periodo civil obligatorio `[desde, hasta)` y filtros opcionales combinables de cuenta y categoría. El periodo puede ser mes o rango de meses y usa fecha de valor. El filtro de categoría tiene tres modos: `direct` devuelve solo el UUID; `branch` devuelve ese nodo y descendientes; `unclassified` devuelve únicamente category_id NULL. Sin filtro de categoría se incluyen todas las categorías y los no clasificados. Sin filtro de cuenta se incluyen todas las cuentas.

La búsqueda se aplica únicamente al concepto. Se compara por subcadena tras Unicode NFD, eliminación de marcas diacríticas y case-fold Unicode; por tanto «CAFÉ» coincide con «cafe» y «ÁRBOL» con «arbol». No se eliminan signos de puntuación ni espacios internos. Cadena vacía tras trim equivale a búsqueda ausente. No se busca por discrecionalidad, nombre de cuenta ni categoría.

El orden es fecha de valor descendente y, en empate, UUID ascendente como desempate estable. El cursor exclusivo usa `(value_date,id)` en ese orden. La página predeterminada contiene 100 filas y admite hasta 500. El subtotal es la suma algebraica en céntimos de todos los resultados que cumplen periodo, cuenta, categoría y concepto, sin limitarse a la página visible. La suma debe detectar overflow int64 y fallar explícitamente; nunca degradar a punto flotante.

## Selección y operaciones por lote

Una acción por lote recibe una de dos selecciones explícitas: un conjunto no vacío de UUID concretos seleccionados, o el conjunto exacto de UUID que forma la página actualmente visible. La selección de página captura sus UUID en el momento de la acción; no significa «todos los resultados filtrados» ni «todos los registros». No existe valor por defecto que amplíe la selección. Se eliminan UUID repetidos y se rechaza lote vacío.

Categorizar asigna una categoría a cada seleccionado; quitar categoría pone category_id a NULL. Borrar solicita confirmación de cantidad y alcance antes de invocar el repositorio. En toda acción, revalidar que cada UUID existe y que la categoría destino es válida/asignable. Ejecutar todo el lote dentro de una unidad de trabajo: cualquier UUID ausente, referencia inválida, fallo de restricción o borrado fallido revierte todos los cambios y la revisión. El éxito preserva cuenta, fecha, concepto, importe, discrecionalidad, UUID y procedencia; solo cambia categoría o elimina los movimientos indicados. El lote incrementa la revisión una vez, no una vez por registro.

## Fuera de alcance

Importadores, reglas automáticas, presupuestos, fotos patrimoniales y sincronización. La procedencia preexistente se lee y conserva, pero esta funcionalidad no importa ni sincroniza datos.

## Relación con EP-004

Reutilizar `MovementRepository`, `MovementInput`, `MovementRecord`, `UnitOfWork`, el adaptador SQLite, `import_row_id` y revisión local. EP-004 ya define CRUD, filtros por fecha/cuenta/categoría exacta, lecturas completas por rama y transacciones. Para EP-010 se amplía lectura paginada con búsqueda por concepto, modo de rama/directo/no clasificado y subtotal global filtrado; se añaden operaciones de selección/lote en el dominio propietario. No recrear tabla, conexión, esquema ni repositorio. Las reglas pueden componerse sobre consultas existentes solo si preservan paginación, subtotal y orden determinista.

MA-TSK-087 entrega contrato y casos sintéticos. La UI requiere el mockup complementario aprobado; la base visual de EP-002 consta en [entrega Flutter](../ep-002/entrega-flutter.md). Este documento por sí solo no autoriza cambiar pantallas.
