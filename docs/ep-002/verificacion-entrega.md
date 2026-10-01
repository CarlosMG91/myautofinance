# MA-TSK-020 · Verificación de entrega

Fecha: 2026-10-01. Paquete: [entrega-flutter.md](entrega-flutter.md). Solo documentación; no se modifican el mockup aceptado, los contratos, el prototipo ni archivos de otros tickets.

## Evidencia de aprobación

Consulta a `http://localhost:4310/api/data`, tablero My autofinance, épica MA-EPIC-012: MA-TSK-019 está `done` y contiene la discusión humana «Propuesta visual aceptada: http://localhost:4310/mockups/autofinance-ma-tsk-019-v1.html». MA-TSK-020 estaba `in-progress`. Se conserva el artefacto del commit `711843d`; no se afirma haber repetido la revisión visual humana ni la matriz de dispositivos de MA-TSK-018.

## Revisión documental

- Las cinco rutas principales y todas las secundarias del mapa tienen contenido, entradas y retorno; se concretan rutas de alta de fichas/categorías, alcance directo/rama y origen interno.
- Los cortes 600, 840 y 1200, márgenes, ancho de navegación, columnas, tipografía, formularios, diálogos y objetivos táctiles tienen medidas lógicas explícitas. Detalles por ruta, sin panel opcional; anual móvil con doce meses accesibles.
- Cada pantalla tiene correspondencia con secciones EP-001 y casos sintéticos. Se conservan signo, agregación, separación real/presupuesto, foto manual completa y orden de motivos del colchón.
- Se fijan los flujos no completos del prototipo: Gestión con retorno, altas y vigencia, referencias CSV y revisión de solapamientos, tabla PC de propuesta y confirmación de sustitución, progreso y recuperación de Drive.
- Estados de carga, vacío, error, ausencia, cero, conflicto y confirmación tienen contenido y acciones. Teclado, foco, texto ampliado y cancelación están especificados como criterios futuros.
- Los enlaces locales del paquete se comprueban desde PowerShell y `git diff --check` revisa formato. La revisión de contenido es documental; no es una prueba de layout ni de implementación.

## Comprobaciones ejecutadas

Los tres comandos finalizaron correctamente:

```text
node docs/ep-001/verificar-casos.mjs
node docs/ep-002/prototipo/verificar.mjs
node docs/ep-002/prototipo/verificar-integral.mjs
```

EP-001: 48 partidas y 10 reales; enero +1.229,75 €, real anual +2.329,65 €, presupuesto anual +13.200,00 €. Los comprobadores del prototipo verifican cálculos y manejadores con DOM simulado, incluidas fotos, propuesta, conflicto, CSV y Drive simulados. No prueban importación o Drive reales.

No existe proyecto Flutter: análisis, widgets, renderizado Windows/Android, teclado real, lector de pantalla, tacto físico, persistencia SQLite y Drive entre instalaciones quedan sin verificar. La entrega proporciona los criterios para esas verificaciones en las épicas de implementación; no cambia retrospectivamente el informe MA-TSK-018.

## Alcance de Git

Solo `docs/ep-002/entrega-flutter.md` y este informe pertenecen al ticket. `AGENTS.md` y `README.md` ya estaban sin seguimiento al inicio y quedan excluidos. La entrega se confirma y sube a la rama configurada `main`, sin force-push; el resultado de subida se comunica al terminar.
