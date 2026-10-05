# MA-TSK-099 · Presupuesto mensual · Propuesta v1

Fecha: 2026-10-05. **Pendiente de aprobación humana explícita.**

Artefacto retenido: [mockup-presupuesto.html](mockup-presupuesto.html).
Revisión desde Epic Board:
<http://localhost:4310/mockups/autofinance-ma-tsk-099-v1.html>.
El enlace requiere que el servidor local de Epic Board esté activo.

Se consultaron MA-EPIC-097 y MA-TSK-099 en `GET /api/data` del tablero
**My autofinance**, cuyo workspace coincide con este repositorio. El ticket
estaba `in-progress`. No se registra aprobación, no se completa el ticket y
no se implementan MA-TSK-102/103 ni otras pantallas dependientes.

## Alcance y fuentes

Amplía [entrega Flutter EP-002](../ep-002/entrega-flutter.md), aprobada mediante
MA-TSK-019, con captura mensual. Mantiene paleta, fuentes del sistema, cinco
destinos, Gestión, detalles como rutas secundarias y composición adaptable.
Aplica §3 y las reglas de categorías de
[EP-001](../ep-001/especificacion.md),
[contrato CSV](../ep-001/contrato-csv.md) y
[casos de referencia](../ep-001/casos-referencia.md).
Se revisó [entrega EP-010](../ep-010/entrega.md) para coordinar la navegación
y el selector: mismos destinos, periodo conservado y categorías por identidad
estable con ruta completa. No se modifica código compartido de EP-010/EP-008.
Los IDs breves del HTML son identidades estables del fixture sintético,
no UUID de producción ni nombres utilizados como claves.

El prototipo opera exclusivamente en memoria; recargar lo restablece.
No contiene datos personales, credenciales, SQLite ni servicios reales.
La matriz anual, la propuesta de año nuevo, los reales y Drive quedan fuera.
Los otros destinos muestran solo un contexto navegable, no su contenido.

## Propuesta de interacción

- PC: árbol activo completo sin colapsar, importe propio editable y subtotal
  de rama de solo lectura. Pulsar el importe abre un campo; Intro o
  «Confirmar celda» guarda solo esa partida. Perder foco no guarda.
- Menos de 840 px, también Windows estrecho: tarjetas con ruta completa y
  captura mediante formulario. El botón «Vista Android» permite revisar esta
  composición en una columna de 412 px desde PC. Cambiar tamaño conserva
  ruta y entradas. Texto ampliado, signos y rutas pueden envolver.
- Mes de trabajo mediante selector año/mes. Se propone como ampliación la
  ruta mensual `/presupuesto?a&m`; no implementa ni sustituye la matriz anual
  prevista en EP-002. Detalles: `/presupuesto/partidas/nueva` o `/:id`.
- Sin partida: «Sin presupuesto». Cero: «0,00 € (registrado)».
  Vaciar el campo da error; solo «Eliminar partida» elimina, tras confirmación.
- Detalle: año/mes → categoría con ruta y tipo heredado → importe firmado.
  Signo independiente del tipo; coma o punto, dos decimales, cero válido.
  Cambiar mes vuelve al origen y ofrece «Ver mes». Metadatos históricos,
  ID, concepto, discrecionalidad y lote/fila CSV son de solo lectura y se
  conservan al editar los tres campos.
- Histórico archivado separado del árbol activo, incluido en el total;
  permite corregir partida existente y conservar su categoría archivada.
  El selector de altas solo ofrece categorías activas.
- Conflictos de padre/descendiente en ambos sentidos muestran mes y dos rutas,
  explican que las partidas previas y el borrador se conservan. No sustituyen,
  redistribuyen ni borran nada. Hermanas y meses distintos son válidos.
- Fallo simulado de lectura retira tabla y totales y ofrece Reintentar.
  Cargando no muestra ceros. Fallo de escritura conserva el borrador y los
  datos previos; falla una vez para poder revisar el reintento sin duplicar.
- Cancelar, Volver, cambiar mes, destino o editor con cambios pregunta
  «Hay cambios sin guardar»: «Seguir editando» o «Descartar cambios».
  Esc y cancelar el diálogo conservan el borrador. Recarga/cierre usa el
  aviso nativo del navegador cuando hay cambios. Retorno conserva mes,
  desplazamiento y foco del control de origen. No se guarda un mes en bloque.
- Etiquetas persistentes, regiones de estado/error, anillo de foco,
  confirmación mediante diálogo nativo modal, Esc conservador y objetivos
  de 48 px en móvil. Gestión enumera los cuatro flujos aprobados de EP-002
  como contexto; no añade un sexto destino.

## Recorrido de aprobación

1. Octubre: comprobar árbol completo, los dos Café con rutas distintas,
   tercer nivel Impuestos, Alquiler −700 €, Supermercado −320 €, Mercado
   −80 €, Ocio cero registrado y Ahorro −150 €. Total +1.200 € incluye
   Viajes antiguos −50 €. Ingresos agrega +2.500 € desde Salario sin
   asignarlo ficticiamente a la raíz. El Impuesto −200 € está en septiembre,
   evitando solapamiento con Salario de octubre.
2. Editar Supermercado a −333,25 €; confirmar solo esa celda. Ver el
   subtotal Alimentación −413,25 € y total +1.186,75 €. Cancelar una nueva
   edición y comprobar que no cambia lo guardado.
3. Crear importe en Hogar de octubre: conflicto con Hogar / Alquiler.
   Noviembre tiene Alimentación −400 € en el padre: intentar crear
   Alimentación / Supermercado, incluso a cero. Se conserva el borrador y
   todas las partidas. Hermanas no producen este conflicto.
4. Abrir Supermercado importado, cambiar mes a diciembre, categoría e
   importe a cero; guardar y usar Ver mes. ID y todos los metadatos permanecen.
   Abrir el histórico archivado y corregirlo sin crear nuevas asignaciones.
5. Eliminar Ocio: cancelar primero; confirmar después. Cero pasa a ausencia,
   sin afectar otras partidas. Activar fallo de escritura antes del borrado
   y comprobar conservación y reintento.
6. Fallar próxima escritura, editar y guardar; comprobar error con entrada
   conservada y reintentar. Vacío o tres decimales rechaza sin eliminar.
7. Cambiar destino o mes con borrador; seguir editando, luego descartar.
   Volver desde detalle restaura el origen. Probar Esc y Atrás del navegador.
8. Diciembre inicialmente no tiene partidas: conserva todo el árbol y
   muestra Sin presupuesto. Probar Cargando y Error de lectura / Reintentar.
9. Revisar PC 1024/1440, Android 360/412 y ancho 320, texto 200 %, teclado,
   orden de lectura y diálogo con foco. Estas comprobaciones visuales/manuales
   quedan pendientes de una superficie de navegador disponible.

## Evidencia y límites

- `"C:\Program Files\nodejs\node.exe" docs/ep-011/verificar-mockup.mjs`: OK.
  Verifica fixture válido, céntimos, signos, cero/ausencia, sumas sin doble
  conteo, tres niveles y nombres repetidos, conflictos en ambos sentidos,
  hermanas/meses distintos, histórico archivado, cambio de mes/categoría,
  metadatos, confirmación, cancelación, fallos/reintento y borrado.
  Ejecuta modelo y controladores en un DOM simulado; no acredita layout,
  eventos de un navegador real, lector de pantalla ni persistencia.
- `"C:\Program Files\nodejs\node.exe" docs/ep-001/verificar-casos.mjs`: OK,
  conserva las cifras y los contratos de referencia.
- Publicación: HTTP 200; el HTML servido coincide exactamente con el retenido.
  SHA-256 `70ecf6bb7cd3c5879b9d1a14d7b6bb0ce09d026d9621330fd33eac989819c2b0`.
- Se intentó abrir el enlace mediante Browser Use: `iab` no disponible y
  el inventario de navegadores devolvió `[]`. Revisión visual real,
  teclado, zoom, alto contraste y Android físico **sin verificar**.
- No se ejecuta check-quality Flutter ni builds: los únicos cambios del
  ticket son el HTML, su comprobador y esta propuesta; no cambia el módulo Flutter.

## Aprobación humana

**Pendiente.** No hay evidencia de aceptación de esta versión. La ejecución
automatizada y las pruebas no la sustituyen. La persona usuaria debe revisar
el enlace y aprobar explícitamente MA-TSK-099 en Epic Board, o indicar cambios.
Conservar allí la aprobación y la URL/versionado antes de habilitar
implementación de las pantallas dependientes.
