# MA-TSK-118 · Selección y diagnósticos CSV · v1

Propuesta del 2026-10-07, **pendiente de aprobación humana explícita**.
Artefacto autónomo: [mockup-csv.html](mockup-csv.html).
Publicación: <http://localhost:4310/mockups/autofinance-ma-tsk-118-v1.html>.
Requiere el servidor local de Epic Board activo. La publicación y las pruebas
no sustituyen la aprobación; no se finaliza este ticket ni se implementan
los tickets posteriores dependientes de esta propuesta.

Se consultaron MA-TSK-118 y MA-EPIC-115 mediante `GET /api/data`, tablero
**My autofinance**, y se comprobó el workspace. Fuentes: contrato y ejemplos
EP-001, sistema visual y flujo aprobado EP-002, contrato y mockup EP-012,
lector MA-TSK-116 y selector MA-TSK-117. No se modifica ninguna de esas fuentes.

## Propuesta

Suplemento delante de la revisión e historial de EP-012, cuyos controladores,
asignaciones, referencias, avisos, confirmación y navegación se reutilizan.
El generador toma ese artefacto retenido y añade la selección y los diagnósticos;
el HTML resultante contiene todo lo necesario para abrirlo sin recursos externos.
No se introduce otra vista financiera ni lector de XLS.

La entrada desde Gestión conserva origen Real y enero de 2026. La selección
única representa el selector nativo Windows / documentos Android. Cancelar,
Esc o Atrás conserva archivo y decisiones. Seleccionar un reemplazo exige
descartar la revisión vigente; cancelar ese descarte conserva la sesión.
El reemplazo inicia una revisión nueva, sin reutilizar asignaciones ni marcas.

Diagnósticos de lectura, acceso denegado, documento no disponible, UTF-8,
cabecera, comillas, columnas, filas vacías y validaciones de campos tienen
motivo y corrección. Se distinguen ordinal lógico (desde 2) y línea física;
el ejemplo multilínea falla en registro 3 y línea 5. UTF-8 informa byte y no
inventa registro o línea. La cabecera se identifica como registro 1 de cabecera.
Los fallos de formato o campos no presentan filas importables ni subtotales:
REAL/PRESUPUESTO y CSV/interno figuran como no disponibles. Confirmar está
bloqueado y el mensaje indica cero cambios. La corrección se hace fuera de la
app, en el original, y «Volver a cargar CSV» vuelve a validar todo. No hay editor.

El escenario válido incluye 3 reales y 2 presupuestos: REAL CSV e interno
−55,25 €, PRESUPUESTO CSV +400,00 € e interno −400,00 €, incluido cero explícito.
Los valores originales de importe usan punto y dos decimales, y las fechas
presupuestarias el día 1. Las sumas internas usan céntimos enteros; el mockup
simula el resultado del lector, no interpreta bytes. Solo presupuesto invierte
signo una vez. El fixture no es la plantilla anual completa de EP-001.

Se mantienen resolución de cuentas/categorías, marca expresa de nuevas raíces,
Sin clasificar para REAL, revisión de cada solapamiento y prohibición padre /
descendiente. El archivo renombrado ya confirmado presenta «Ya importado»,
cero altas y enlace al lote existente. Historial incluye únicamente confirmados;
la previsualización y las cargas fallidas/canceladas no lo modifican.

PC conserva tablas compactas; Android tarjetas etiquetadas, controles de 48 px,
cinco destinos y Gestión secundaria. Se conservan foco visible, diálogos con
título accesible, salto a contenido, alertas y texto además de color. Texto al
200 % pasa a tarjetas. El título recibe foco al cambiar contenido o cancelar
el selector; Esc/Atrás cancela el selector antes de abandonar el flujo.

## Guion para aprobación

1. Alternar PC, Android y texto 200 %. Revisar tablas/tarjetas a 320, 360,
   412, 1024 y 1440 px sin recorte de importes, cabecera ni diagnósticos.
2. Seleccionar archivo válido, resolver cuenta y categoría, comparar y marcar
   ambos solapamientos; revisar los dos totales CSV/internos por tipo.
3. Cambiar archivo y cancelar selector; comprobar las mismas asignaciones.
   Seleccionar otro y cancelar descarte; después aceptar descarte.
4. Probar lectura, permiso y disponibilidad; UTF-8, cabecera, comillas,
   campos y columnas. Ver registro/campo/línea cuando se conocen, confirmación
   bloqueada y la instrucción de corregir el original. Volver a cargar válido.
5. Probar lote vacío y conflicto presupuestario; confirmar válido, consultar
   historial/origen y cargar mismos bytes con otro nombre: cero altas.
6. Revisar teclado, Esc/Atrás, foco y retorno a Real enero. Aprobar expresamente
   MA-TSK-118 en Epic Board o solicitar cambios sobre este artefacto.

## Verificación y límites

- `node docs/ep-013/publicar-mockup.mjs`: genera HTML autónomo reproducible.
- `node docs/ep-013/verificar-mockup.mjs`: selección, cancelación, reemplazo,
  errores completos, signos, bloqueos, fallo de guardado, confirmación simulada,
  repetición y contexto correctos con DOM mínimo.
- `node docs/ep-012/verificar-mockup.mjs` y
  `node docs/ep-001/verificar-casos.mjs`: regresiones correctas.
- Publicación comprobada con HTTP 200 y comparación SHA-256 con el archivo
  retenido. No se almacena aprobación humana en el prototipo.
- Sin navegadores ni apps conectados en esta sesión: no se acredita inspección
  visual real, zoom/layout, teclado, lector de pantalla ni Android físico.
  Estos puntos permanecen en el guion de revisión humana.
- No se modifican Dart, plataformas, paquetes ni contratos compartidos.
  No se ejecutan análisis, pruebas o builds Flutter por ser un artefacto HTML.
  El lector real, selector nativo, SQLite, huella y atomicidad de producción
  no se prueban aquí; toda la simulación vive en memoria y se reinicia al recargar.
