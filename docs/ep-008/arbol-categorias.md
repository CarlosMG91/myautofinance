# MA-TSK-079 · Reglas y traspaso del árbol de categorías

Contrato documental de EP-008 / MA-EPIC-078, conforme al ticket facilitado
por el usuario el 2026-10-03. Autoridad financiera: [EP-001 §2.1](../ep-001/especificacion.md).
Resultados esperados: [casos L–O](../ep-001/casos-referencia.md). Todos los
ejemplos son sintéticos. Este ticket no implementa pantallas ni modifica SQL.

## Operaciones y referencias

| Operación | Regla y efecto sobre la historia |
|---|---|
| Crear o renombrar | Nombre no vacío; duplicados permitidos. Identidad por UUID, nunca por nombre/ruta. Máximo tres niveles. |
| Cambiar tipo de raíz | Ingreso/Salida solo editable si no hay movimientos ni partidas en la raíz o sus descendientes, incluidos archivados e históricos. Con datos se rechaza sin cambios. |
| Trasladar una rama | Conserva todos sus UUID y referencias; el histórico entero sigue la rama actual y hereda la marca de su nueva raíz, incluso si cambia de tipo. |
| Convertir en raíz | Conserva la marca efectiva inmediatamente anterior en el nodo promovido; sus descendientes siguen heredándola. No permite elegir otro tipo en la promoción. |
| Archivar/reactivar | Actualiza todos los descendientes en la misma transacción; no elimina referencias ni excluye historia de informes. Reactivar requiere padre activo. |
| Sin clasificar | `movements.category_id = NULL`; grupo de informe, sin fila de categoría ni operaciones de árbol. |

Un traslado no escribe sobre movimientos ni partidas: conserva identidad,
importe firmado en céntimos, fecha de valor/mes, cuenta, concepto,
discrecionalidad y procedencia de importación. El tipo no normaliza ni invierte
signos. No se versiona el árbol por mes: consultar años anteriores usa la
clasificación actual. Cambian los agregados de las ramas afectadas, pero los
totales generales de real y presupuesto permanecen. Las fotos manuales no
cambian. El colchón consume los ingresos presupuestados de las raíces actuales
con la fórmula y motivos existentes; no se añade ni rediseña un indicador.

## Validación atómica del árbol propuesto

Validar existencia y estado activo del padre, ausencia de ciclos y de padre
propio y profundidad de todo el subárbol (no solo del nodo trasladado).
Rechazar creación/traslado bajo padre archivado; trasladar no reactiva nodos.
Archivo impide nuevas asignaciones pero admite correcciones de registros ya
referenciados, conforme a EP-004. Reactivar una rama reactiva también los
descendientes que estuvieran archivados previamente.

Validar partidas existentes contra las relaciones de ancestros del **árbol
resultante**, en todos los meses/años, incluidas partidas archivadas y de cero.
Si dos partidas del mismo mes quedarían en padre y descendiente, rechazar la
operación completa. Hermanas y meses distintos son válidos. No borrar, fusionar,
prorratear ni cambiar importes para hacer posible el traslado. El error debe
identificar mes y categorías en conflicto por UUID y ruta visible para distinguir
nombres duplicados.

La validación y la escritura se ejecutan sobre el mismo estado en transacción,
también ante escritura SQL directa. Un rechazo conserva padres, marcas,
archivo, UUID, registros, procedencia y revisión. Una modificación de negocio
efectiva incrementa revisión una vez, según EP-004; un no-op no la incrementa.

## Diferencia respecto de EP-004 y trabajo posterior

EP-004 entregó `CategoryRepository` y `CategoryNode` en movements y
`SqliteCategoryRepository` en app/data/sqlite. `categories` ya persiste UUID,
padre, nombre, marca exclusiva de raíz y archivo. Reutilizar ese catálogo y
los puertos de presupuesto/movimientos; no recrear tablas ni importar código
o decisiones de MyFinance.

La entrega EP-004 bloquea **todo cambio de padre o marca en ramas usadas**.
EP-008 permite el cambio de padre con historia, condicionado al árbol válido
y a la ausencia de presupuestos solapados. Mantiene el bloqueo del cambio
directo de tipo en raíces usadas. MA-TSK-079 actualiza el contrato y el
[traspaso de persistencia](../ep-004/guia-integracion.md), sin afirmar que esas
operaciones estén ya implementadas.

La implementación posterior deberá adaptar conjuntamente:

- La validación de historia de `SqliteCategoryRepository._validate` y la
  promoción en `edit`; no basta eliminar el bloqueo de padre.
- El trigger `categories_budget_history` de `schema.drift`, sus definiciones
  versionadas en `schema_policy.dart` y los triggers de presupuestos. Proteger
  también traslados que creen solapamientos, sin depender solo de INSERT/UPDATE
  de partidas.
- La migración y reconocimiento de esquema al cambiar objetos SQL: conservar
  snapshots publicados, tablas, UUID, FK, datos, linaje y respaldo previo.
  Este documento no incrementa la versión física 6 ni edita código generado.
- Las pruebas de repositorio, SQL directo, migración, rollback/revisión,
  reapertura/copia y lecturas históricas usando los casos L–O. Las pruebas
  antiguas de bloqueo general describen EP-004 y deberán actualizarse al
  implementar la nueva regla, conservando las de cambio directo de tipo.

## Dependencias y navegación

EP-002 MA-TSK-019/020 y EP-004 MA-TSK-033/036/038/039/040 constan terminadas
en el encargo. [Entrega visual EP-002](../ep-002/entrega-flutter.md) registra
la aprobación y fija tablas compactas Windows y tarjetas Android. EP-003
aporta composición, rutas e inyección; respetar sus fronteras y grafo acíclico.
Estas dependencias se documentan aquí, sin asumir que el tablero las imponga.

Categorías usa Gestión → Categorías y las secundarias `/categorias`,
`/categorias/nueva` y `/categorias/:id`, con retorno al origen o selector,
según EP-002. Compartir el punto de entrada Gestión con EP-009 (Fichas),
conservando los cinco destinos, contexto de retorno y selección pendiente.
No modificar EP-009 ni implementar su navegación en este ticket.

## Alcance de verificación

`node docs/ep-001/verificar-casos.mjs` comprueba los números originales y los
agregados firmados de L/M. No demuestra traslados, bloqueos, atomicidad SQL,
migraciones ni interfaz Windows/Android del contrato nuevo; L–O son el guion
exigible a la implementación posterior. No hay conector Epic Board disponible
en esta sesión; se consulta el ticket íntegro proporcionado y no se modifica
el estado administrativo del tablero.

Verificación local del 2026-10-03: Flutter 3.47.0 / Dart 3.13.0 comprobados;
`check-quality.ps1` completo con lockfile exigido, formato sin cambios, análisis
sin incidencias, 789 pruebas y cuatro variantes de `APP_ENV` correctas.
La primera ejecución se detuvo por acceso restringido a pub.dev; la repetición
con acceso autorizado completó la resolución sin cambiar SDK ni lockfile.
Comprobador EP-001 ampliado correcto, sintaxis JavaScript válida, 40 enlaces
locales existentes, codificación UTF-8 y casos A–O en orden; `git diff --check`
correcto. La suite se ejecutó sobre el checkout con trabajo concurrente de
sincronización, que queda fuera del commit de este ticket. No se ejecutaron
builds ni pruebas en dispositivos: no cambian código Flutter ni plataformas.
