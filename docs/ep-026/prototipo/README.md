# MA-TSK-207 · Prototipo integral v1

Artefacto del **2026-10-12**, pendiente de aprobación humana explícita.
El ticket, sus requisitos T02/T03 y los criterios de MA-TSK-175/185/191/199
se consultaron mediante `GET http://localhost:4310/api/data`, tablero
**My autofinance**. No se han implementado tickets posteriores.

## Abrir y revisar

- Artefacto autónomo: [autofinance-v1.html](autofinance-v1.html).
- Ruta publicada de revisión: `/mockups/autofinance-integral-v1.html` en Epic Board.
- Fuentes: [plantilla](plantilla.html), [estilos](prototipo.css),
  [interacciones](prototipo.js) y [generador](generar.mjs).
- [Traspaso y cobertura de suplementos](traspaso.md).
- [Verificación y capturas](verificacion.md).
- [Registro de aprobación pendiente](aprobacion.md).

El HTML incluye los tres pesos Roboto de T03, sus tokens y SVG originales.
No necesita red, dependencias, servidor de aplicación ni datos personales.
La licencia y los hashes de las fuentes permanecen en
[`../identidad/assets/`](../identidad/assets/README.md). Las operaciones son
simulaciones en memoria. Recargar o Restablecer muestra devuelve las fixtures.
No es un motor financiero reutilizable, una base SQLite ni una conexión Drive.

## Recorrido recomendado de aprobación

1. **Inicio:** distinguir resultado real, presupuestado y diferencia de la
   foto manual. Enero: +1.229,75 €, +1.100,00 €, +129,75 €; patrimonio neto
   14.000,00 €. Abrir Estado y Ocio: se ven los dos Café. Cambiar a febrero:
   foto Sin dato; ningún arrastre de enero.
2. **Presupuesto:** resumen anual, Captura mensual, matriz completa con
   doce meses/total, expansión independiente de cifras y origen de partidas.
   Intentar añadir Vivienda en enero: conflicto con Alquiler. Preparar 2027,
   editar/desglosar Alimentación y revisar la confirmación de sustitución.
3. **Movimientos:** registrar/editar/eliminar con signo y cuenta, discrecionalidad
   y procedencia. Cambiar de destino con borrador: Seguir editando / Descartar.
   Escenario Con pendientes: asignación individual/lote y fallo íntegro al
   seleccionar Datos cambiaron. Ver lote conserva ámbito de importación.
4. **Patrimonio:** foto, todas las fichas y navegación entre fotos. Escenario
   Foto incompleta: registrar ahorro 0 y cartera 10.500; neto de febrero
   11.900 y colchón 2,07. Editor de periodos de Cartera: Líquida desde febrero,
   entonces líquidos 16.700 y colchón 5,57; enero conserva 9.000 y 3,00.
5. **Análisis / Más:** Real anual (todo el año, aunque el mes enfocado cambie),
   resumen, matriz y tarjetas desplegables de doce meses, Sin clasificar,
   real directo y rama completa. Variante Transferencia con neto cero: la
   celda Ahorro enero abre los dos registros. Colchón con cinco ausencias
   seleccionables y cero válido; completar ingresos abre el mes pendiente.
6. **Gestión:** CSV válido repetido, errores, archivo nuevo, referencias por
   resolver, posibles duplicados y Openbank sintético con cuenta explícita.
   Revisar → confirmar → resultado → pendientes/procedencia → repetición.
   Ninguna previsualización modifica datos ni fotos.
7. **Drive / recuperación:** subida manual, divergencia, descarga confirmada,
   fallo de validación/respaldo y copia previa recuperable. Escenario Sin base
   activa: solo recuperación hasta restaurar. No existe fusión automática.
8. **Diagnóstico:** ejecutar/cancelar; sin hallazgos, pendientes válidos según
   foto del mes, posible duplicado, regla no ejecutada, error de lectura y
   resultado obsoleto. Abrir origen informa el destino; después de una edición
   se repite explícitamente. Nunca se repara desde el resumen.
9. Abrir la franja **Prototipo v1** para estados carga/vacío/error, errores de
   operación y Texto 200 %. Revisar a 1024×768/1440×900, 360×800/412×915 y
   320 px. Navegar con Tab/Enter/Escape/Alt+Izquierda y Volver. Desplazar
   horizontalmente las matrices completas; el resto debe refluir.

## Reproducir

Desde la raíz, con Node y una instalación existente de Playwright/Chromium:

```powershell
node docs/ep-026/prototipo/generar.mjs
node docs/ep-026/prototipo/generar.mjs --check
node docs/ep-026/prototipo/verificar.mjs
node docs/ep-001/verificar-casos.mjs
```

`PLAYWRIGHT_MODULE` y `CHROME_PATH` permiten usar herramientas ya instaladas;
no se añaden dependencias a Flutter. El comprobador usa loopback en un puerto
efímero, bloquea recursos externos y cierra navegador/servidor al terminar.

La aprobación debe citar **MA-TSK-207 · v1**, la ruta y el alcance de cinco
vistas y flujos de esta guía. Los cambios solicitados se aplican antes de
cerrar T04. No se reutiliza la aprobación anterior de MA-TSK-019.
