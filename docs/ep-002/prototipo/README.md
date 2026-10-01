# MA-TSK-017 · Prototipo navegable

Abrir `index.html` directamente en un navegador moderno, con JavaScript. No necesita instalación, servidor, backend, red ni Flutter. Todos los datos son sintéticos, tomados del CSV y los casos aprobados de EP-001. Los cambios viven en memoria: recargar o «Restablecer referencia» los descarta. No seleccionar ni cargar archivos personales.

La navegación tiene cinco destinos y conserva año y mes. Gestión abre importación CSV simulada, categorías y Drive simulado. PC usa tablas compactas desde 840 px; Android usa tarjetas y cinco destinos inferiores. Las matrices presentan doce meses y total; Patrimonio permite consultar doce fotos sin sumarlas. Abrir cifras distingue reales de partidas; expandir ramas presenta hasta tres niveles sin doble conteo.

## Recorridos de revisión

1. Referencia inicial, enero 2026: Estado real +1.229,75 €, previsto +1.100,00 €, diferencia +129,75 €. Abrir Ocio: dos Café de −10,00 €. Presupuesto anual +13.200,00 €; Real anual +2.329,65 €. Indicadores: 3,00 meses.
2. Cambiar a febrero: Estado +1.099,90 €, diferencia −0,10 €. Patrimonio e Indicadores sin dato. Registrar foto: principal 6200.00 y deuda 4800.00, otros vacíos. Guardar muestra pendientes. Completar ahorro 0.00 y cartera 10500.00: neto 11.900,00 € y colchón 2,07 meses. Corregir principal a 6300.00: neto 12.000,00 €; enero conserva 14.000,00 €.
3. Escenarios → Base vacía → Gestión → Importar CSV → previsualizar ejemplo → confirmar: 48 partidas y 10 reales. Repetir: 0 altas. Seleccionar fecha inválida, referencias pendientes o solapamiento: confirmación bloqueada, base intacta. Son escenarios predefinidos; no es un importador arbitrario. La creación de referencias del ejemplo está preaprobada en el escenario válido. XLS permanece pendiente de EP-014.
4. Restablecer → cargar pendientes del caso J: enero +1.224,75 €, sin clasificar +4,00 €. Abrir Abono pendiente y editar categoría: cambia su atribución, conserva el total, cuenta, discrecionalidad y fotos. Cancelar conserva registro.
5. Presupuesto 2026 → preparar año siguiente: enero Alimentación −360,00 €, febrero −430,00 €, marzo cero explícito. Editar enero a −370.00; activar desglose para retirar padre y guardar en Supermercado. Confirmar guarda 2027 sin cambiar 2026. Desde una cifra de Vivienda 2026, crear partida padre: conflicto con Alquiler, sin cambios. Cancelar propuesta no guarda.
6. Drive → elegir escenario → pulsar subir/descargar. Probar éxito, divergencia, versión desconocida, cambio durante publicación, respuesta perdida, conexión, autenticación, descarga sin copia, archivo inválido, respaldo y apertura fallidos. Cancelar descarga conserva datos. Confirmar descarga normal conserva respaldo; «Recuperar respaldo» permite volver al estado previo. Las fechas/versiones son sintéticas, no hay acceso a Google ni SQLite real.
7. Revisar a 360×800, 412×915, 1024×768 y 1440×900; 320 px y zoom/texto ampliado. Comprobar tabla/tarjetas, cifras completas, desplazamiento interno anual, etiquetas, foco con Tab/Mayús+Tab, activación con Intro/Espacio y cancelación con Esc. Las rutas secundarias se abren en diálogo y vuelven a la vista y periodo de origen.

## Verificación realizada

Desde la raíz:

```text
node docs/ep-001/verificar-casos.mjs
node docs/ep-002/prototipo/verificar.mjs
node docs/ep-002/prototipo/verificar-integral.mjs
node --check docs/ep-002/prototipo/app.js
git diff --check
```

Resultados: OK el 2026-10-01. El comprobador del prototipo ejecuta el modelo y los manejadores de interacción con DOM simulado: cifras, cinco rutas, fotos parcial/cero/completa, conflicto, propuesta, categorización, importación vacía/error/repetida y Drive divergencia/cancelación/fallos/respaldo. No demuestra renderizado, tacto, lector de pantalla, transferencia real ni persistencia. No había navegador conectado disponible (inventario vacío), por lo que queda pendiente la revisión visual interactiva en los tamaños indicados y en un dispositivo Android real. No existe módulo Flutter que analizar.

Se aplica el ticket proporcionado en la conversación; no hay herramienta Epic Board para consultarlo o actualizarlo. Los contratos y wireframes anteriores permanecen como fuentes de verdad. La aprobación humana del mockup pertenece a **MA-TSK-019 y sigue pendiente**. Este prototipo no autoriza implementar pantallas Flutter.

La revisión de MA-TSK-018, las correcciones, las pruebas ampliadas y la matriz visual pendiente están en [verificacion-integral.md](../verificacion-integral.md). La aceptación integral sigue pendiente de disponer de navegador para ejecutar PC/Android; las pruebas con DOM simulado no sustituyen esa revisión.
