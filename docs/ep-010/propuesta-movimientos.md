# MA-TSK-091 · Búsqueda, selección y borrado · propuesta v1

Propuesta del 2026-10-04, **pendiente de aprobación humana explícita**.

Artefacto retenido: [mockup-movimientos.html](mockup-movimientos.html).
URL de revisión desde Epic Board:
<http://localhost:4310/mockups/autofinance-ma-tsk-091-v1.html>.
Disponible mientras el servidor local de Epic Board esté activo.
El servidor devuelve HTTP 200 y el HTML servido coincide byte a byte con
el artefacto retenido. SHA-256:
`3f48e8c2711dcb7b8e881c69c0165a0cf13c8c31df1b519440cccee21567bf4d`.

Se consultaron MA-EPIC-086 y MA-TSK-091 en `GET /api/data`, tablero
**My autofinance**. MA-TSK-087 consta `done`; MA-TSK-091 estaba `in-progress`.
No se modifica el estado administrativo ni se registra aceptación por agente.

## Fuentes y alcance

Reutiliza [entrega Flutter EP-002](../ep-002/entrega-flutter.md), paleta,
tipografía, cinco destinos, Gestión, rutas secundarias y correspondencia
tabla PC / tarjeta Android del mockup aprobado MA-TSK-019.
Aplica [contrato MA-TSK-087](contrato-movimientos.md), sus
[casos sintéticos](casos-referencia.md) y §2 de
[EP-001](../ep-001/especificacion.md).

El prototipo solo simula movimientos en memoria. No implementa Flutter,
repositorios, SQLite, importadores, presupuestos, fotos ni Drive.
Los nombres de categorías y cuentas son etiquetas ficticias para las
identidades simbólicas del fixture MA-TSK-087; no representan datos personales.
La procedencia ficticia se muestra en el detalle y se conserva al editar
o categorizar. La retención de filas/lotes tras borrado es un contrato visible,
no una implementación de auditoría en este HTML.

## Recorrido de revisión

1. Marzo: cuatro movimientos, recientes primero, m1 antes que m2 al empatar
   fecha. Página inicial m1/m2; subtotal global **+17,50 €**, aunque solo se
   vean dos movimientos. El tamaño de página reducido a dos sirve para
   revisar el alcance; producción usará cien según MA-TSK-087.
2. Buscar `CAFE`: tres coincidencias, subtotal **+20,50 €**. Buscar `arbol`
   devuelve m4; buscar `regalo` no busca en discrecionalidad.
3. Elegir Ocio / rama: m1/m2/m3; directos: solo m1. Combinar cuenta diaria
   y rama: m1/m2. Marzo Sin clasificar: vacío; abril Sin clasificar:
   m5, **−2,00 €**. Un periodo sin datos ofrece alta; una búsqueda sin
   coincidencias ofrece limpiar filtros. Desde posterior a hasta da error.
4. Elegir casillas individuales o «Seleccionar página visible (2)».
   Las identidades y el alcance se muestran. No hay selección implícita
   de todos los resultados. Cambiar página o aplicar filtros limpia
   selección con anuncio; abrir/cancelar detalle la conserva.
5. Asignar categoría y quitar categoría. Solo cambia ese campo; el detalle
   importado mantiene discrecionalidad y procedencia. Activar «Rechazar
   próxima escritura» y repetir: rechazo completo, selección conservada,
   posibilidad de reintento. El error de lectura conserva filtros/selección
   y retira el subtotal hasta reintentar.
6. Borrar desde la fila/tarjeta o detalle: confirmación de **1 movimiento**.
   Borrar seleccionados: confirmación del **número exacto**, UUID y alcance.
   Cancelar/Esc/Atrás conserva datos y selección. Confirmar borra solo los
   indicados; fallo simulado no borra ninguno.
7. Abrir m2 y editar discrecionalidad, incluida cadena vacía. Guardar
   conserva procedencia. Importe cero o inválido rechaza sin perder borrador.
   Activar el fallo y guardar: conserva campos para reintentar. Cambiar
   fecha fuera del periodo ofrece «Ver mes» después de guardar.
8. Volver desde detalle restaura filtros, periodo, página, selección,
   scroll y foco. Desde Gestión → Movimientos se usa el periodo seleccionado;
   los accesos de Estado/Real fijan categoría y alcance. Las otras vistas
   se representan como origen de regreso; su contenido completo está
   en MA-TSK-019. No introduce un sexto destino principal.
9. Salir de editor modificado por Cancelar, Volver, destino, Gestión,
   Esc o Atrás simulado pide «Seguir editando» / «Descartar cambios».
   La opción conservadora y Esc mantienen el borrador. Al cerrar/recargar
   el navegador con cambios se usa su aviso nativo `beforeunload`.

## Accesibilidad y adaptación

Windows: tabla compacta desde 840 px, lateral 200/216, márgenes 24/32.
Android/ventana estrecha: tarjetas, controles de 48, márgenes 16 y cinco
destinos con etiquetas visibles. «Android · 412 px» permite revisar la
composición en un navegador PC sin descartar estado. «Texto 200 %» amplía
contenido y diálogos; a esa escala la lista pasa a tarjetas para conservar
importes y acciones. No hay fuentes ni recursos externos.

Etiquetas persistentes, nombres accesibles con concepto/identidad, signos
además de color, foco visible, regiones de estado/error y enlace para saltar
al contenido. Diálogo HTML nativo modal: foco inicial en título, confinamiento
de Tab, Esc para cancelar y retorno al disparador si sigue presente.
La simulación de Atrás y el Back del navegador recorren la misma salida
que Volver; Android físico requiere verificación posterior en Flutter.
Estilos para alto contraste y movimiento reducido.

Revisión humana sugerida: 320/360/412 y 1024/1440 px, texto 200 %, Tab,
Mayús+Tab, Intro, Espacio, Esc y lector de pantalla. CUA devolvió cero
navegadores/superficies conectados; **layout real, teclado real, lector,
texto ampliado en navegador y Android físico no se han verificado**.
La previsualización no demuestra accesibilidad nativa ni persistencia.

## Comprobaciones realizadas y puerta de aprobación

- `node docs/ep-010/verificar-mockup.mjs`: correcto. Cubre casos de lectura,
  subtotal completo, página, confirmación previa, rechazo completo,
  preservación de campos/procedencia, edición, formato y borrador/contexto.
- `node docs/ep-001/verificar-casos.mjs`: correcto.
- `git diff --check` limitado a los archivos propios: correcto.
- Publicación HTTP 200 y comparación de bytes: correcto.
- `./scripts/check-quality.ps1`: bloqueado al comprobar la toolchain:
  **Flutter no está en PATH**. No se ejecutaron análisis, pruebas o builds
  Flutter. No se actualizó SDK ni lockfile; este ticket no cambia módulos Dart.

La aprobación previa MA-TSK-019 **no aprueba este complemento**. MA-TSK-091
no está completo. No implementar tickets de interfaz dependientes aunque
se ejecute la épica completa. Registrar aquí después de recibirla: persona,
fecha, versión/URL y evidencia humana exacta de Epic Board.

Commit/push quedan pendientes hasta cumplir la aceptación humana requerida
por el ticket. El checkout está en `ticket/ma-tsk-071` y contiene trabajo
concurrente; solo los tres archivos de esta propuesta pertenecen a MA-TSK-091.
No se incluyen el contrato/casos MA-TSK-087 ni cambios de otras épicas.
