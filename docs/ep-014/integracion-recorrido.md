# MA-TSK-130 · Integración Openbank pendiente del lector

**Actualización 2026-10-22:** ruta `/importaciones/openbank` conectada con lector,
selector y confirmación comunes. La entrada de Gestión se habilita cuando
existen servicios de importación. Véase [formato observado](formato-observado.md)
y [verificación de habilitación](habilitacion-openbank.md). Registro histórico debajo.

**Estado: bloqueado; recorrido productivo no implementado.** Última comprobación:
2026-10-18. Este registro no completa los criterios del ticket ni cierra EP-014.

## Reapertura: comprobación del 2026-10-18

La reapertura autorizada del 2026-10-16 requiere conectar el lector/adaptador
real, no volver a cerrar con evidencia del núcleo sintético. Se ha consultado
`GET http://localhost:4310/api/data`, tablero **My autofinance**, con workspace
coincidente. MA-TSK-130 figura `in-progress`; MA-TSK-124/125/126 figuran `done`,
pero sus documentos y el código disponible siguen sin acreditar sus entregas.
Los adjuntos de la épica y de esos tickets están vacíos; no se facilita una
ruta privada concreta de muestra o implementación externa.

La [caracterización](caracterizacion-openbank.md), revisada el 2026-10-18,
continúa bloqueada por falta de muestra verificable. El
[lector](lector-openbank.md) y el [adaptador](adaptacion-nucleo.md) declaran que
no están implementados. En `lib/features/importing/data` solo están el lector
y adaptador CSV, los dos selectores y SHA-256. La búsqueda de archivos
versionados y no ignorados no encuentra XLS/XLSX/XLSB ni lector/adaptador
Openbank. No acredita ausencia fuera del checkout o en archivos ignorados;
no se ha leído ningún extracto ni inferido su estructura.

Los puntos de integración comprobados son:

- `lib/app/openbank_selector_factory.dart` conserva el selector entregado.
- `lib/app/navigation/app_router.dart` mantiene `Importar Openbank` deshabilitado
  (`enabled: false`); no existe una composición bancaria productiva.
- `lib/app/navigation/import_route.dart` compone CSV e historial; el lanzamiento
  con adaptador inyectado está reservado expresamente a pruebas.
- `ImportController` dispone de selección CSV y revisión/confirmación común,
  pero no de selección bancaria conectada. `createImportServices` aporta
  previsualización, confirmación e historial SQLite para reutilizar.

Se conservan MA-TSK-127/128 y todos sus artefactos. La implementación pendiente
debe aplicar `lib/ui/autofinance_ui.dart` y la navegación vigente de
[EP-026 v1 aprobada](../ep-026/prototipo/aprobacion.md), sin reabrir esa aprobación.
No se habilita el recorrido con un adaptador simulado. Los criterios de lectura,
cuenta explícita, revisión, persistencia y consulta posterior de Openbank siguen
sin cumplirse y MA-TSK-131 continúa sin recibir esa entrega.

Para retomar falta la muestra original anonimizada en una ruta privada accesible,
completar MA-TSK-124 y disponer del lector/adaptador reales MA-TSK-125/126 en esta
rama, con evidencia verificable. Se ha solicitado la ubicación de la muestra y
de las entregas si existen fuera del checkout. Este registro no cambia estados
en Epic Board ni constituye la entrega funcional del ticket.

### Verificación de la reapertura

- Flutter 3.47.0 / Dart 3.13.0 y `scripts/check-toolchain.ps1`: correctos.
- 56 pruebas existentes aprobadas con `--no-pub --concurrency=1`: selectores
  Openbank/CSV, controlador, contrato y arquitectura. Solo verifican esos
  componentes y el núcleo común, no un lector/adaptador Openbank.
- `node docs/ep-001/verificar-casos.mjs`: correcto; 48 presupuestos, 10 reales
  y resultados financieros de referencia conservados.
- `scripts/check-quality.ps1` se detiene en `flutter pub get --enforce-lockfile`
  por un error de socket al consultar `pub.dev/api/packages/http/advisories`.
  Resolución alternativa `flutter pub get --offline --enforce-lockfile`
  correcta, sin cambios en `pubspec.lock`. Formato correcto: 505 archivos,
  cero cambios; `flutter analyze --no-pub --fatal-infos --fatal-warnings`
  sin incidencias. No se acredita suite general ni variantes de arranque en esta
  revisión, pues el script no llega a ejecutarlas.
- Enlaces relativos y `git diff --check`: correctos. Único archivo propio:
  este registro. Los cambios concurrentes quedan fuera; los artefactos de
  MA-TSK-127/128 conservan su contenido.
- Logs locales ignorados: `.tools/ma-tsk-130-reapertura-2026-10-18-quality.log`,
  `.tools/ma-tsk-130-reapertura-2026-10-18-offline.log` y
  `.tools/ma-tsk-130-reapertura-2026-10-18-directed.log`.

No hay cambios Dart o de plataforma; no se compilan Windows/Android ni se
acredita recorrido nativo o accesibilidad Openbank con componentes inexistentes.

## Registro histórico del 2026-10-08

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
