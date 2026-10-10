# MA-TSK-153 · Suplemento visual de propuesta presupuestaria

Versión 1, 2026-10-09. Aprobada explícitamente en Epic Board el 2026-10-10 a las 05:20:42.977 UTC: MA-TSK-153 figura completado y la conversación registra «Propuesta visual aceptada: http://localhost:4310/mockups/autofinance-ma-tsk-153-v1.html». Evidencia consultada mediante GET /api/data durante MA-TSK-154; habilita su implementación.

Mockup: http://localhost:4310/mockups/autofinance-ma-tsk-153-v1.html

Artefacto autónomo: `mockup-propuesta.html`. Se publica como copia idéntica en `epic-board/public/mockups/autofinance-ma-tsk-153-v1.html`; Epic Board lo sirve por HTTP. Publicación local, sin Sites ni un alojamiento externo.

Se conserva el sistema visual y el retorno fuente/destino aprobado de EP-002 (`entrega-flutter.md`, `sistema-visual.md`). Contrato financiero: EP-001 §3 y caso H. Ticket consultado mediante GET /api/data: motor MA-TSK-150, edición MA-TSK-151 y guardado MA-TSK-152 entregados; MA-TSK-153 en curso, implementación MA-TSK-154 pendiente. Solo se añaden archivos de este suplemento, sin modificar contratos ni Flutter.

## Recorrido para aprobar

1. Caso H: fuente 2026, destino 2027. PC: tabla raíz × doce meses, real/propuesto/revisión y acción de desglose. Móvil: tarjetas con total anual y doce meses desplegables. Mes vacío: cero explícito editable. Total inicial firmado +2.310,00 EUR.
2. Editar Alimentación enero a −370,00 y aplicar; volver a desglosar en Supermercado. El padre desaparece únicamente de enero. También puede demostrarse nivel 3, dos hermanas y cambio de total con confirmación explícita; destinos activos con rutas completas.
3. Comparar: todas las altas/correcciones/retiradas y sin cambio, con anterior/nuevo por mes/ruta. En el recorrido anterior: 60 nuevas partidas más dos retiradas, 62 filas; no hay truncamiento ni paginación. Sustituir solo después de marcar confirmación. Destino vacío usa Guardar propuesta.
4. Cancelar diálogo mantiene borrador. Cancelar propuesta vuelve al año fuente con protección; Ver año destino existente exige descartar antes de salir. Éxito retorna a presupuesto mensual del destino, enero, sin añadir matriz de informes.
5. Escenarios: signo atípico exige revisión y edición la invalida; conflicto padre/descendiente rechaza guardar; cambio concurrente exige revalidar y revisar comparación de nuevo; error de guardado conserva borrador y destino, con reintento; fallo de lectura evita falsos ceros. Exclusiones Sin clasificar/raíz archivada son visibles y no bloqueantes; histórico archivado bajo raíz activa se incluye en el real agregado.

Todos los datos, errores y operaciones son simulaciones en memoria. No hay SQLite, persistencia de borrador, guardado real, edición de movimientos, Drive, inflación ni nuevas reglas automáticas. Los ejemplos de fuente 2025 reutilizan valores sintéticos para revisar el cambio de periodo, no constituyen otro histórico de referencia.

## Evidencia y límites

`verificar-mockup.mjs` ejecutado con Playwright y Chrome headless. Pasan caso H, cero editable, edición −370, desglose hasta nivel 3/cambio explícito de total, comparación completa, cancelación y confirmación, signos e invalidación, conflicto, cambio concurrente/revalidación, errores y reintento, Escape y devolución de foco. Sin errores JavaScript. Sin desbordamiento de página en 320/360/412/1024/1440 px y a 320 px con texto 200 %. Tablas solo desplazan su contenedor interno. Diálogo nativo modal, título enfocado, confirmación conservadora y Escape cancela; foco vuelve al control de edición.

Capturas revisadas: `pc.png`, `android.png`, `texto-200.png`, `comparacion.png`, `desglose.png`. Paleta EP-002, importes firmados y etiquetas además de color; controles móviles ≥48 px, alto contraste y reducción de movimiento. No se ha validado con lector de pantalla ni Android físico. No se ejecutan builds o pruebas Flutter: el cambio es exclusivamente HTML/documentación del mockup.

Para repetir, instalar/disponer de Playwright fuera de los archivos versionados, indicar `PLAYWRIGHT_MODULE` si no se resuelve por defecto y `CHROME_PATH` si se usa Chrome instalado; `MOCKUP_URL` admite otra ubicación. Ejecutar `node docs/ep-018/verificar-mockup.mjs`. La prueba actualiza las capturas. La aprobación humana no se automatiza ni se registra como concedida desde este artefacto.
