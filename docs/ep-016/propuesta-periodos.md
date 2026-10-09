# MA-TSK-141 · Suplemento visual de periodos · v1

Propuesta del 2026-10-09, **pendiente de aprobación humana explícita**. Ticket
consultado en Epic Board, tablero My autofinance. No se completa el ticket ni
se implementan los consumidores posteriores mientras falte esa aprobación.

Mockup autónomo retenido: [mockup-periodos.html](mockup-periodos.html).
Publicado en `/mockups/autofinance-ma-tsk-141-v1.html` del servidor de Epic Board
(`http://localhost:4310`). No requiere fuentes, scripts ni servicios externos.

Fuentes: [entrega aprobada de EP-002](../ep-002/entrega-flutter.md),
[sistema visual](../ep-002/sistema-visual.md),
[contrato MA-TSK-140](periodo-sesion.md) y
[reglas financieras EP-001](../ep-001/especificacion.md). Esta propuesta añade
controles de periodo; no sustituye las pantallas funcionales entregadas.

## Recorrido para revisar

1. Abrir el mockup: Estado y mes actual Europe/Madrid. Elegir octubre 2026,
   diciembre y Siguiente para cruzar a enero. Cambiar año desde Estado conserva
   mes; pasar a Real mantiene el periodo.
2. En Real anual cambiar a un año nuevo: enero. Elegir otro mes, salir de ese
   año y regresar: se recupera el mes recordado. Presupuesto anual comparte ese
   foco. La consulta anual es un punto de integración, sin informe ni totales.
3. Pulsar Año vacío 2031. Abrir movimientos del mes: real cero sin movimientos.
   Ir a Presupuesto y abrir el mensual: Sin presupuesto. En octubre 2026,
   Alimentación tiene −250,00 € y Ocio tiene 0,00 € explícitamente registrado.
4. Patrimonio: febrero 2026 tiene foto incompleta, con Cartera familiar pendiente;
   octubre tiene foto completa y cero válido de cartera; 2031 no tiene foto.
   Ausencia y foto parcial muestran Sin dato. Ningún mes toma la última foto ni
   se suman saldos de distintos meses.
5. Desde presupuesto mensual, seleccionar un filtro y abrir una cifra. Editar
   el concepto y probar cambio de mes/destino, Cancelar, Volver y Atrás de
   Android (demo). Seguir editando o Escape mantienen el borrador; Descartar
   permite salir. El retorno conserva periodo, filtro, scroll y foco.
6. Cambiar fecha en detalle y Guardar (demo): vuelve al origen, informa del mes
   de guardado y ofrece Ver mes. Solo esa acción cambia al nuevo mes.
7. Simular carga y error: no aparecen cifras anteriores como actuales.
   Reintentar consulta el mismo periodo. Nueva sesión vuelve a Estado/mes
   actual y borra la memoria de años. Mes actual mantiene destino.
8. Revisar Tab/Mayús+Tab, Enter, Escape y Texto 200 %, también a 320 px.

## Controles y contexto

| Contexto | Controles | Cambio de año |
| --- | --- | --- |
| Estado, Patrimonio, Indicadores | Año, Mes, Ir al periodo, Mes anterior/siguiente, Mes actual | Conserva mes |
| Real y Presupuesto anual | Año, Mes enfocado, Ir al periodo, Año anterior/siguiente, Mes actual | Mes recordado de ese año o enero |
| Movimientos y presupuesto mensual existentes | Controles mensuales y retorno al contexto anual | Conserva mes |
| Detalle/edición | Origen rotulado, Volver, Cancelar, Guardar | Cambiar periodo/destino protege borrador |

Años válidos 0001–9999; pasos fuera de rango deshabilitados. Elección explícita
de mes prevalece sobre memoria. Cambiar destino conserva periodo; filtros
propios no se heredan entre destinos. La memoria dura únicamente la sesión.
PC conserva lateral y tablas compactas; Android usa barra inferior y tarjetas.
Etiquetas y signos no dependen del color. Los objetivos móviles son de 48 px.

Estado e Indicadores, junto a Real y Presupuesto anuales, son destinos técnicos
sin cifras de informes pendientes. Las cifras mensuales son muestras
sintéticas para revisar ausencias y retorno. No hay importación, nuevo año de
presupuesto, preferencias sincronizadas ni escrituras de datos reales.

## Verificación y límites

[verificar-mockup.mjs](verificar-mockup.mjs) se ejecutó con Playwright 1.56.1 y
Chrome instalado. Pasan sesión Madrid, cruce diciembre/enero, memoria anual,
mes mensual, conservación entre destinos, año vacío, cero real, presupuesto
ausente/cero, foto parcial, borrador y Escape, Atrás simulado, retorno con
filtro/foco, guardado fuera de periodo y Ver mes, carga/error/reintento,
límites de calendario y nueva sesión. Sin errores JavaScript ni desbordamiento
horizontal a 320/360/412/840/1024/1440 px y texto 200 % a 320 px.

Capturas retenidas y revisadas: [PC](pc-periodos.png),
[Android adaptable](android-periodos.png), [texto 200 %](texto-200-periodos.png).
Se corrigió el desbordamiento de etiquetas de meses con texto ampliado.
La copia publicada se comprueba por HTTP y SHA-256 frente al HTML retenido.

Para repetir, definir `PLAYWRIGHT_MODULE` con la ruta de instalación de
Playwright y `CHROME_PATH` si se utiliza Chrome instalado, y ejecutar:

```powershell
node docs/ep-016/verificar-mockup.mjs
```

`MOCKUP_URL` permite verificar la misma copia en otro servidor. Publicar
copiando el HTML a `public/mockups/autofinance-ma-tsk-141-v1.html` del proyecto
Epic Board. Las dependencias de verificación locales viven en `.tools`, ignorado.

No se verificaron lector de pantalla, interacción física, Android Back nativo
ni informes futuros. El filtro del mockup representa contexto de retorno;
no sustituye consultas filtradas reales. Guardado, carga y error son simulados.
No se ejecutaron análisis, tests ni builds Flutter: la entrega solo modifica
HTML, documentación, capturas y verificación del prototipo.

## Aprobación

Revisar esta versión y aceptar expresamente la propuesta en Epic Board o pedir
cambios. Registrar allí persona, fecha y URL/versión aceptada antes de completar
MA-TSK-141 y habilitar los tickets que necesitan estos controles aprobados.
La entrega se confirma y sube como propuesta revisable, manteniendo pendiente
esa puerta humana. Rama configurada: `ticket/ma-tsk-113`; remoto `origin`.
Solo se incluyen archivos propios de MA-TSK-141; el contrato MA-TSK-140 y las
modificaciones concurrentes de otras épicas quedan fuera.
