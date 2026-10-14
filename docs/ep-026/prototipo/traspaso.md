# Traspaso de MA-TSK-207 a EP-026 y suplementos

Estado: **v1 aceptada explícitamente**, con evidencia reconciliada en
[`aprobacion.md`](aprobacion.md). El artefacto publicado coincide por SHA-256
con el conservado en el repositorio. Esta aprobación permite la implementación;
no sustituye la aceptación visual final de T14 ni cierra la épica.

## Fuentes y precedencia

1. EP-001 conserva íntegros especificación, CSV y casos de referencia.
2. T02 [`../navegacion-jerarquia.md`](../navegacion-jerarquia.md), catálogo y
   contrato de shell/contexto fijan destinos, contexto y propietarios.
3. T03 [`../identidad-visual.md`](../identidad-visual.md) y tokens fijan
   tema claro, Roboto, paleta y estados financieros accesibles.
4. **Después de aprobar explícitamente T04**, este prototipo y su alcance
   aprobado sustituyen la apariencia/navegación EP-002. No sustituyen sus
   reglas financieras ni las validaciones de sus propietarios.

`aprobacion.md` registra evidencia textual, versión, artefacto/hash y alcance.
La fecha procede del campo `approvedAt` del tablero, comprobado el 2026-10-14.
Los cambios pedidos requieren una versión revisable y nueva
evidencia antes del cierre. La validación nativa vigente y sus límites se
registran en [`../validacion-integral.md`](../validacion-integral.md).

## Distribución de implementación

- **T05:** kit en `lib/ui/autofinance_ui.dart`, fuentes/licencia, iconos,
  tokens, tarjetas, controles, matrices, estados, gráficos y accesibilidad.
  Consume cifras/estados/callbacks; nunca datos ni motores desde UI.
- **T06:** shell, cinco destinos, Gestión, selector visible y capturas de
  origen. Mantiene rutas y parsers existentes, borradores, contexto, Back,
  foco/scroll y recuperación sin base. Usa el contrato de shell de T02.
- **T07–T13:** componen presentación con el kit y puertos existentes. No
  copian las funciones JS de esta simulación como servicios reales. Las
  operaciones SQLite, importadores y Drive mantienen propietario.
- **T14:** integra interfaces entregadas, pruebas y recorridos, capturas
  nativas reales Windows/Android y builds. Las épicas funcionales no esperan
  T14 para entregar sus interfaces/cálculos.

PC usa lateral y matrices en Ver detalle; Android usa barra inferior, tarjetas
y meses desplegables, con matriz íntegra opcional. A 200 % se permite una
proyección de navegación con reflujo para mantener todos los controles.
La aprobación HTML no acredita TalkBack/Narrador, Back nativo, teclado nativo,
escalado nativo, SQLite o Drive; se verifican al implementar e integrar.

## Coordinación con EP-022/023/024/025

Estados consultados el 2026-10-14: MA-TSK-174 terminado; 175–180 bloqueados;
EP-023/024/025 en backlog. Esta entrega solo coordina su representación.

| Suplemento | Referencia de v1 | Condición de reutilización de aprobación |
| --- | --- | --- |
| EP-022 / MA-TSK-175 | Real anual resumen/gráfico, matriz doce meses/total, raíces contraídas y expansión separada, tres niveles, histórico archivado, Sin clasificar, tarjetas/meses, cifras y real directo, cero con datos/lista vacía, alta, carga/error/retorno. | Comparar contra todos sus criterios y la evidencia aprobada. Completar específicamente cabeceras persistentes, expansión y retorno nativos; cualquier variante no cubierta exige suplemento y aprobación específica. |
| EP-023 / MA-TSK-185 | Colchón: numerador, anual/12 y promedio, 3,00 y 0,00; cinco motivos, fichas/meses pendientes; acciones hacia foto y mes pendiente, carga/error separado. | Reutilizar solo si la aprobación global incluye estos estados y acciones; motor/catálogo/cálculo siguen en EP-023. |
| EP-024 / MA-TSK-191 | Cifras abren partidas/reales con periodo, rama/directos, cuenta solo en reales, contador/subtotal completo, filtros restaurables, registro→lista→informe con contexto. | El suplemento verifica parsers, ámbito y cambios de datos reales. Este prototipo no promete una instantánea financiera inmutable ni una consulta SQLite. |
| EP-025 / MA-TSK-199 | Acceso manual, ejecutar/cancelar, severidad, detalle/origen, sin hallazgos/pendiente/duplicado/no ejecutada/error/obsoleto/recuperación. | Los hallazgos son demostraciones de presentación, no implementación de reglas. Completar suplemento exige interfaces del propietario y T04 aprobado; no autoriza autocorrecciones. |

No se marca ningún suplemento como aprobado, terminado ni dependiente de T14
por esta entrega. Sus criterios pueden exigir pruebas nativas, enlaces o
variantes adicionales. La autorización de coordinación no permite duplicar
motores, inventar indicadores, umbrales, puntuaciones o métodos financieros.

## Límites de la simulación

CSV/XLS, huellas, transacciones, copias SQLite, autenticación y transferencias
se representan con fixtures y resultados en memoria. Las revisiones de
importación no leen archivos bancarios. La descarga simulada sustituye el
dataset completo y conserva una copia local completa; no demuestra seguridad
de instalación ni control remoto atómico. Diagnóstico no escribe ni limpia
la marca de cambios locales. Los intervalos de liquidez ejemplifican división
y corrección fechadas; los rechazos persistentes y concurrencia pertenecen
a sus pruebas financieras. No ampliar los contratos compartidos desde el HTML.
