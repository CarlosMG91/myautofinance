# MA-TSK-205 · Verificación y traspaso

## Criterios y evidencia

| Criterio | Entrega comprobable |
| --- | --- |
| Cinco informes y flujos accesibles | Catálogo de 40 destinos; prueba de conectividad desde ambas proyecciones. Las agrupaciones no crean módulos financieros. |
| Real anual e Indicadores en dos acciones | Prueba de distancia mínima desde navegación principal; Más tiene accesos directos a ambos. |
| Periodo visible y coherencia mes/año | Slot obligatorio del shell y contrato anual/mes enfocado; pruebas de NavigationSession y navegación histórica. |
| Categoría/filtros/scroll/foco y borradores | Contrato de capturas por principal para T06; pruebas del origen/guard existente. La nueva memoria entre principales aún la implementará T06. |
| Importar, categorizar y registrar foto | Entradas contextuales del catálogo, comprobadas por pruebas. Openbank distingue integración pendiente. |
| Rutas, Back, teclado y recuperación | Todas las constantes actuales AppRoutes tienen cobertura; selección adaptable comprobada; adaptación segura, pila/guards/teclado/recuperación especificados para T06. |
| Foto día 1 distinta de flujos | Jerarquía de Inicio y regla de catálogo. EP-001 permanece fuente financiera. |
| Resumen y detalle íntegro | Seis relaciones resumen→detalle verificadas con igual módulo/periodo. |
| API para trabajo independiente | Firmas normativas de AfShell/AfPageSlots y propiedad kit/app/features. Implementación posterior a aprobación T04. |

Las pruebas nuevas validan el artefacto de diseño y los puertos existentes;
no demuestran una UI rediseñada ni accesos nativos a las rutas nuevas. El
catálogo se marca explícitamente como diseño pendiente de MA-TSK-207. Las
rutas nuevas y slots no se han conectado a AppRouter ni AutofinanceApp.

## Comprobaciones locales del 2026-10-12

- Flutter 3.47.0 / Dart 3.13.0: `flutter --version` y
  `./scripts/check-toolchain.ps1` correctos.
- Resolución inicial de dependencias: fallo de socket al consultar pub.dev
  dentro del sandbox. Reintentada con acceso de red en el script de calidad;
  `flutter pub get --enforce-lockfile` correcto, SDK/lockfile sin cambios.
- `dart format test/redesign_navigation_contract_test.dart`: aplicado.
- Verificación final de formato y análisis del test modificado: correctos,
  sin incidencias.
- Batería dirigida: **61 pruebas correctas**, incluidas las siete nuevas,
  NavigationSession, rutas, contrato histórico y arquitectura.
- `./scripts/check-quality.ps1`: correcto; formato de 376 archivos sin
  cambios, análisis sin incidencias, **1.640 pruebas correctas** y las cuatro
  variantes de arranque development/test/production/invalid-synthetic correctas.
- `git diff --check` sobre archivos propios (índice y árbol): sin errores.

Logs ignorados en `.tools/ma-tsk-205-directed-final.log` y
`.tools/ma-tsk-205-quality-review.log`. La batería dirigida usa cuatro procesos de pruebas,
sin cambiar los scripts compartidos.

No se ejecutan builds Windows/Android: no cambia producción, plataforma ni
widgets; esta entrega añade documentación, catálogo de diseño y pruebas.
No se han capturado pantallas ni simulado datos reales. T04/T06/T14 verificarán
el nuevo prototipo/shell y recorridos reales; no se afirma evidencia visual
o nativa a partir del código leído.

## Casos exigidos al prototipo y a la integración

Reutilizar [EP-001](../ep-001/casos-referencia.md), sin implementar otro
calculador: caso B, enero +1.229,75 real / +1.100,00 presupuesto /
+129,75 diferencia; casos E/F, anual +13.200,00 previsto y +2.329,65 real;
casos D/G, foto enero neto 14.000,00 y líquidos 9.000,00, colchón 3,00 meses,
febrero sin dato. No llamar disponible a ninguna de esas cifras.

| Recorrido sintético para T04/T06/T14 | Resultado que debe conservarse |
| --- | --- |
| Enero 2026 → Análisis/Más → Real anual → Indicadores → Inicio | Enero enfocado sigue elegido, anual lee doce meses, foto se refiere al día 1. |
| Presupuesto con rama/filtros/expansiones → Movimientos → volver | Mismo periodo de trabajo y captura propia del presupuesto; filtros de movimiento independientes. |
| Estado → real/partidas → editor → selector → Back | Origen completo y foco; cancelar borrador no escribe ni cambia mes. |
| Guardar movimiento con fecha fuera del mes | Aviso y Ver mes explícito; guardar no desplaza el periodo automáticamente. |
| Foto incompleta → completar dato cero → volver | Cero distinto de ausencia, ninguna actualización de movimientos. |
| Importar CSV → revisar → cancelar/confirmar → lote → categorizar | Confirmación atómica existente; filtros de lote y retorno a resultado conservados. |
| Openbank no conectado / errores de fila | Motivo real de disponibilidad/error, sin resultado ficticio. |
| Cifra anual o neto cero → Ver detalle → registros | Conjunto íntegro y UUID originales, incluido Sin clasificar y presupuesto explícito cero. |
| Sin base → copias → confirmar restauración → reapertura | Recuperación independiente y respaldo/validación; no informe escondido bajo la ruta de recuperación. |
| Gestión → Drive / copias / diagnóstico | Operaciones solo con acción explícita; diagnóstico sigue en su épica propietaria. |
| PC 1024×768/1440×900; Android 360×800/412×915; 320/840 px y texto 200 % | Periodo visible, destinos alcanzables, teclado/Back, guard y retorno accesibles. |
| URL antigua / parámetros duplicados / UUID inválido | Significado anterior conservado o rechazo sin consultas y retorno seguro. |

## Estado y publicación

Solo se entregan `docs/ep-026/catalogo-navegacion.json`,
`navegacion-jerarquia.md`, `contrato-shell-contexto.md`,
`verificacion-navegacion.md` y `test/redesign_navigation_contract_test.dart`.
Rama configurada: `ticket/ma-tsk-113`; remoto `origin`.

README, APIs/archivos de subida Drive, prototipos y fixtures de otros tickets
estaban modificados/sin seguimiento al iniciar. Se excluyen del commit. Las
pruebas usan el checkout compartido, incluidos esos adaptadores concurrentes;
no acreditan una clonación limpia con todas sus entregas pendientes.
T01 figura terminado en Board sin inventario entregado, según su actividad;
T04/T14 deben resolver esa carencia de evidencia. No se cambia estado ni se
envían mensajes en Epic Board desde este ticket.

La publicación utiliza un commit exclusivo de los cinco archivos y push a
`origin/ticket/ma-tsk-113`, sin force. El hash y el resultado se registran en
el cierre del ticket para no introducir una autorreferencia en el commit.
El acceso remoto se comprobó correctamente. Git requirió una excepción
`safe.directory` limitada a cada comando y a este checkout, por distinta
propiedad entre la cuenta del sandbox y la cuenta que publica; no se cambia
la configuración global.
