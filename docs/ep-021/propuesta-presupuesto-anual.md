# MA-TSK-167 · Presupuesto anual · Suplemento visual v1

Propuesta del 2026-10-11. **Pendiente de aprobación humana explícita.**
MA-TSK-167 y MA-EPIC-165 se consultaron mediante `GET /api/data` de Epic Board,
tablero My autofinance. El ticket está en curso, sin aprobación registrada.
No se completa ni se implementan tickets posteriores.

Mockup retenido: [mockup-presupuesto-anual.html](mockup-presupuesto-anual.html).
Revisión: <http://localhost:4310/mockups/autofinance-ma-tsk-167-v1.html>.
Requiere el servidor local de Epic Board activo; el HTML es autónomo, sin
fuentes externas, cuentas, SQLite ni servicios reales. Los cambios de la demo
viven en memoria; recargar restablece los datos sintéticos.

Fuentes revisadas: EP-001 especificación §3/§5.3 y casos de referencia;
EP-002 sistema visual y entrega aprobada MA-TSK-019;
EP-011 propuesta mensual y formulario Android entregado;
EP-016 periodos/retorno; EP-019 enlaces de partidas;
EP-021 consulta anual MA-TSK-166. Se conserva su distinción entre partida
propia nullable y agregado con presencia, incluso si suma cero.

## Recorrido de revisión

1. Abrir Presupuesto anual 2026: raíces contraídas, categoría persistente,
   enero–diciembre y total anual. Desplazar la matriz dentro de su región:
   foco con Tab y flechas, o rueda/arrastre. Cabeceras y categorías fijas.
2. Expandir Alimentación y Supermercado hasta Compra semanal. Octubre tiene
   −320,00 € en Compra semanal y −80,00 € en Mercado; noviembre tiene
   −400,00 € propio en Alimentación. Sus hijos no reciben reparto del padre.
3. Editar Compra semanal octubre: campo dentro de la celda. Intro o
   Confirmar celda guarda solo esa partida. Perder foco no guarda.
   Subtotales y columna anual solo abren fuentes. Las ausencias pueden crear
   una partida salvo conflicto o categoría archivada.
4. Ocio enero suma cero desde Café −50,00 € y Reembolso +50,00 €:
   abrir el subtotal conserva ambos IDs. Ocio octubre es cero propio registrado.
   Vaciar el campo da error; Eliminar partida requiere otra confirmación.
5. Intentar alta en Compra semanal noviembre: conflicto con Alimentación.
   En formulario Android cambiar la categoría y el mes para probar conflicto
   al guardar: se muestran mes y ambas rutas y se conserva el borrador.
   No hay sustitución, desglose, copia masiva ni propuesta nueva de presupuesto.
6. Expandir Viajes: rama archivada y antecesor conservados por la partida
   anual de Viajes antiguos. Corregir partida existente mediante formulario;
   no permitir altas en archivadas. Árbol activo completo, incluso Salud vacía.
7. Abrir herramientas de revisión: Fallar próxima escritura conserva importe
   y datos previos; confirmar de nuevo reintenta. Carga y error ocultan cifras;
   Reintentar usa el mismo año. Año vacío 2031 conserva el árbol activo.
8. En Android o Vista Android: tarjetas por categoría, total anual,
   mes enfocado y Los doce meses desplegables. Captura/corrección usa la
   representación del formulario EP-011 con año, mes, ruta e importe firmado;
   conserva ID/procedencia sintética. Los totales abren la lista de origen.
9. Captura mensual es secundaria. Volver conserva año, mes enfocado,
   expansiones, scroll de matriz y foco. Memoria de mes por año en sesión.
   Guardar en otro periodo vuelve al origen y ofrece Ver mes explícito.
10. Con borrador, Cancelar, Escape, Atrás de Android (demo), cambiar periodo
    o destino pide Seguir editando / Descartar cambios. Escape en esa
    confirmación conserva el borrador. Cerrar/recargar usa aviso del navegador.
    Revisar Tab, Intro, Escape, ancho 320 px y Texto 200 %.

El total inicial del fixture visual es **+16.250,00 € (43 partidas)**:
Ingresos +27.300,00 €, Hogar −8.400,00 €, Alimentación −800,00 €,
Ahorro −1.800,00 €, Ocio neto cero y Viajes −50,00 €.
Son ejemplos complementarios sintéticos, no una sustitución del caso E
EP-001 (+13.200,00 €). La demo calcula en céntimos; suma mensual solo raíces
y anual doce meses, sin sumar otra vez padres e hijos.

## Integración posterior

Reutilizar AnnualBudgetQuery, BudgetManagement, formularios EP-011,
NavigationContext/periodo EP-016 y los enlaces de partidas coordinados en
MA-TSK-170 sobre EP-019. Este HTML representa sus interacciones; no añade
servicios ni puertos de producción. Las rutas principales continúan siendo
las cinco de EP-002; Captura mensual y partidas son rutas secundarias.
Los otros destinos en la demo muestran únicamente el contexto de retorno.
EP-018 no bloquea esta matriz ni se modifica su propuesta o sus tickets.

## Verificación

`node docs/ep-021/verificar-mockup.mjs` pasa con Chrome y Playwright:
14 columnas, raíces contraídas, tres niveles, fuentes del neto cero,
edición por celda/Intro, errores de escritura y reintento, conflictos,
cero/vacío/borrado confirmado, borrador/Escape/Back simulado,
memoria por año, archivo histórico, lectura vacía/carga/error,
tarjetas con doce meses, captura mensual y retorno con scroll conservado.
Anchos 320/360/412/840/1024/1440 sin desbordamiento de página;
texto 200 % en 320 y 1440 y formulario de 320 sin pérdida de contenido.
Sin errores JavaScript. Capturas conservadas y revisadas visualmente:
[PC](pc-anual.png), [Android](android-anual.png),
[texto 200 %](texto-200-anual.png), [formulario](formulario-200.png).

`node docs/ep-001/verificar-casos.mjs`: OK; mantiene 48 presupuestos,
10 reales y presupuesto anual de referencia +13.200,00 €.
Publicación HTTP comprobada con igualdad exacta frente al HTML retenido.

Repetir las pruebas con `PLAYWRIGHT_MODULE` apuntando al módulo Playwright,
`CHROME_PATH` al navegador instalado y, opcionalmente, `MOCKUP_URL` al
HTML publicado para comprobar también su identidad. Valores locales por
omisión en el comprobador; dependencias ignoradas en `.tools`.

No se verificaron Android físico/Back nativo, lector de pantalla o persistencia.
Back Android es una simulación revisable, no evidencia nativa. No se ejecutaron
análisis, tests o builds Flutter porque esta entrega solo cambia el prototipo
HTML, documentación, capturas y su verificación; no modifica módulos Flutter.

## Aprobación y entrega

Revisar el enlace y aprobar expresamente **MA-TSK-167 v1** en Epic Board,
o indicar cambios. Registrar persona, fecha y URL/versión aceptada antes
de completar el ticket y habilitar MA-TSK-168/169. Esta aprobación debe
provenir de la persona usuaria; no la conceden las pruebas ni la ejecución.

Commit/push a la rama configurada `ticket/ma-tsk-113`, remoto `origin`,
solo de archivos propios de MA-TSK-167. No se incluyen consulta anual
MA-TSK-166 ni cambios concurrentes de sincronización u otras épicas.
