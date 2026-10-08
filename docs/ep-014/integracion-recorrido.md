# MA-TSK-130 · Integración Openbank pendiente del lector

**Estado: bloqueado; recorrido productivo no implementado.** Comprobación del
2026-10-08. Este registro no completa los criterios del ticket ni cierra EP-014.

## Requisitos contrastados

Se consultó `GET http://localhost:4310/api/data`, tablero **My autofinance**,
con workspace coincidente, MA-EPIC-123, MA-EPIC-106 y sus tickets. Los adjuntos
de la épica y de MA-TSK-124/125/126/130 están vacíos; la petición no aporta una
ruta privada de muestra o implementación externa.

| Requisito | Evidencia disponible | Consecuencia |
|---|---|---|
| MA-TSK-124, caracterización | El resultado y la [entrega](caracterizacion-openbank.md) declaran falta de muestra verificable. | No hay formato físico ni mapeo observado que implementar. |
| MA-TSK-125, lector | El resultado y la [entrega](lector-openbank.md) declaran que no está implementado. | No se pueden interpretar bytes Openbank. |
| MA-TSK-126, adaptación | El resultado y la [entrega](adaptacion-nucleo.md) declaran que no está implementada. | Falta el `ImportAdapter` bancario que conectar. |
| MA-TSK-127, selector | [Selector binario compartido](selector-extractos.md) y `createOpenbankSelector()` implementados. | Disponible para integrar cuando exista el adaptador. |
| MA-TSK-128, aprobación | La conversación del tablero contiene una entrada de «Tú»: «Propuesta visual aceptada: http://localhost:4310/mockups/autofinance-ma-tsk-128-v1.html». | Aprobación explícita comprobada; ya no bloquea la interfaz. |
| EP-012, núcleo | Servicios, revisión, confirmación SQLite e historial implementados. | Reutilizar estos componentes, sin un motor paralelo. |

MA-TSK-124/125/126 figuran administrativamente como `done`, pero sus resultados
documentan bloqueos. Ese estado no acredita sus criterios ni entrega código.
La [propuesta visual](propuesta-openbank.md) conserva el estado previo a la
aprobación; la conversación posterior del tablero acredita su aceptación.

La búsqueda de archivos versionados y no ignorados no encuentra XLS/XLSX ni
lector/adaptador Openbank. En `features/importing/data` existen el lector y
adaptador CSV histórico, selectores nativos y el proveedor SHA-256. La consulta
de árboles de las ramas locales y referencias de `origin` disponibles tampoco
encuentra un lector/adaptador bancario. No se ha actualizado el inventario remoto
con `fetch`; no se acredita ausencia en ramas remotas nuevas, archivos ignorados
o carpetas privadas externas. No se ha leído ningún extracto ni usado MyFinance.

## Punto de integración pendiente

La [guía EP-012](../ep-012/guia-lectores.md) y la
[adaptación pendiente](adaptacion-nucleo.md) fijan el contrato a reutilizar:

- Conectar `createOpenbankSelector()` con el adaptador real de MA-TSK-126;
  construir `ImportFile` con `bankXls` y SHA-256 de todos los bytes originales.
  La orientación XLS del selector no valida el contenido.
- Componer mediante `createImportServices` y el controlador/pantalla comunes,
  manteniendo selección, revisión y decisiones en memoria. El controlador
  actual incorpora selección CSV; su integración bancaria y los textos
  Openbank deberán adaptarse al diseño aprobado, con regresión del flujo CSV.
- Exigir elección y confirmación expresa de cuenta en cada carga y revisión
  de todos los solapamientos. Mantener las filas legítimas idénticas por ordinal,
  categoría nula y enlaces existentes a Real y al editor para categorizar.
- Cambiar archivo invalida sesión y decisiones anteriores tras aceptar el
  descarte; cancelar el selector conserva la revisión. Impedir acciones dobles
  durante confirmación. Errores bloquean el lote completo y fallos de escritura
  conservan revisión sin altas parciales.
- Consultar resultado, lote y procedencia mediante el historial SQLite común,
  incluida repetición exacta con cero altas tras editar o borrar destinos.
  No modificar presupuestos, fotos, saldos ni sincronización.

No se conecta el adaptador sintético de pruebas al producto ni se añade una
ruta productiva que aparente importar Openbank. La aprobación visual permite
implementar la interfaz, pero no proporciona los componentes necesarios para
completar el recorrido asignado.

## Condición para retomar

Se ha solicitado la ruta local de la muestra original anonimizada y, si existen
fuera del checkout, la ubicación o rama de caracterización, lector y adaptador.
La muestra permanece fuera de Git. Completar MA-TSK-124/125/126 antes de habilitar
el recorrido; no inventar formatos ni fixtures bancarios.

Con esas entregas, verificar el recorrido completo PC/Android sobre SQLite,
cuenta pendiente, errores de estructura/datos, cambio de archivo, doble envío,
rollback/reintento, revalidación, repetición renombrada, ordinales y solapamientos,
historial tras reapertura y categorización posterior. Comprobar que las fotos
permanecen intactas, ejecutar calidad y builds fijados y registrar límites
de verificación nativa y accesibilidad.

## Verificación de este registro

- Flutter 3.47.0 / Dart 3.13.0 y `scripts/check-toolchain.ps1`: correctos.
- 56 pruebas dirigidas existentes correctas, con `--no-pub --concurrency=1`:
  selectores Openbank/CSV, controlador común, contrato y arquitectura.
- `node docs/ep-014/verificar-mockup.mjs`: correcto; verifica el prototipo
  mediante DOM simulado, no un lector ni una pantalla Flutter Openbank.
- `node docs/ep-001/verificar-casos.mjs`: correcto; resultados financieros
  de referencia conservados.
- `scripts/check-quality.ps1` completo: 1.301 pruebas aprobadas y cuatro
  variantes de arranque (`development`, `test`, `production`,
  `invalid-synthetic`) correctas. La ejecución inicial falló al consultar
  pub.dev; el reintento con acceso autorizado resolvió las dependencias fijadas,
  sin cambios en `pubspec.lock`. Formato: 274 archivos, cero cambios;
  análisis estático sin incidencias.
- Enlaces relativos y `git diff --cached --check` correctos.
  Esta entrega solo añade este documento;
  los cambios concurrentes de Drive, README, EP-008 y fixtures CSV quedan fuera.
- No se ejecutan builds ni recorridos nativos Windows/Android: no hay cambios
  Dart o de plataforma y falta el lector/adaptador que integrar. No se acredita
  importación Openbank, accesibilidad nativa ni cierre de la épica.

Logs locales ignorados: `.tools/ma-tsk-130-directed.log`,
`.tools/ma-tsk-130-quality.log` y `.tools/ma-tsk-130-quality-network.log`.
Las comprobaciones usan contratos y datos sintéticos existentes; no verifican
lectura, adaptación ni recorrido productivo Openbank. No se modifica el estado
administrativo de los tickets en Epic Board.
