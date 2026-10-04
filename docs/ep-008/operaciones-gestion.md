# MA-TSK-081 · Operaciones de gestión de categorías

`CategoryManagement`, exportado por la entrada pública de `movements`, expone
`create`, `rename`, `edit`, `move`, `get`, `list`, `archive` y `reactivate`.
Reutiliza `CategoryRepository`; no añade tablas, migraciones ni persistencia.
`createCategoryManagement(database: database)` compone el adaptador existente
`SqliteCategoryRepository` y la unidad de trabajo sobre la misma conexión de
la sesión. La fábrica es pasiva: no abre otra base ni ejecuta operaciones.

Las mutaciones y la lectura de su resultado comparten una unidad de trabajo.
`CategoryDetails` contiene el nodo (UUID, padre, profundidad, archivo y tipo
efectivo) y su ruta actual. Trasladar o promover devuelve esos valores después
del cambio; no escribe movimientos ni presupuestos y conserva sus signos.
Se mantienen las reglas de [MA-TSK-080](reorganizacion-atomica.md), incluidos
solapamientos de cualquier mes, promoción y bloqueo de tipo de raíces usadas.

`list` y `get` incluyen archivadas; `assignmentOptions` devuelve solo activas,
con sus rutas completas. Un selector abierto antes del archivo no puede eludir
la validación persistente de nuevas asignaciones de movimientos y presupuestos.
Archivo y reactivación actúan sobre toda la rama sin borrar registros.
Reactivar bajo padre archivado se rechaza. Una modificación efectiva incrementa
la revisión una vez; lecturas, no-op y rechazos no la incrementan.

El formulario recorta espacios exteriores del nombre, rechaza un nombre vacío,
un padre vacío y la edición de tipo en hijos. La edición de una raíz existente
requiere elegir Ingreso/Salida; al crear se conserva el valor por defecto Salida
del repositorio, y al promover se admite `null` para conservar el tipo heredado.
`CategoryFormFailure.fields` devuelve mensajes españoles por campo (`name`,
`parentId`, `isIncome`), sin modificar el borrador del consumidor. Los errores
de negocio conservan `CategoryFailure`, sus mensajes y los conflictos con
mes, UUID y rutas propuestas. La composición traduce `DatabaseFailure` a su
mensaje público; otros fallos técnicos reciben un mensaje español controlado
sin SQL ni rutas privadas.

El dominio depende solo de Dart y `UnitOfWork`, sin importar Flutter, SQLite
ni `app`. La composición reside en `app`; no cambia el grafo EP-003. La futura
presentación Windows/Android consume la entrada pública de `movements`. Este
ticket no incorpora pantallas ni rutas Gestión y no modifica EP-009.

## Verificación local

Las pruebas `test/persistence/category_management_test.dart` usan SQLite real
y datos sintéticos: persistencia y reapertura, rutas y tipo efectivo, signos y
referencias históricas, revisión y no-op, validación sin escrituras, archivo y
reactivación completos, selector activo, rechazo de nuevas asignaciones y
reactivación bajo padre archivado, solapamiento con detalle y rollback. Un
trigger temporal provoca fallos durante archivo y reactivación para comprobar
que se conservan todos los nodos y la revisión. También se comprueba la
traducción de errores de restauración y de conexión cerrada.

Resultado del 2026-10-04: Flutter 3.47.0 / Dart 3.13.0 comprobados;
`check-quality.ps1` completo, formato sin cambios, análisis sin incidencias,
811 pruebas correctas y las cuatro variantes de `APP_ENV` correctas.
Comprobador numérico EP-001 y EP-008 L/M correcto; `git diff --check` correcto.
No se cambian SDK, lockfile ni esquema SQL. La suite completa incluye el
trabajo concurrente presente en el checkout, que queda fuera del commit.

La ejecución restringida no pudo resolver pub.dev ni acceder correctamente a
los temporales nativos. La ejecución con acceso autorizado completó todas las
comprobaciones. No se ejecutaron builds ni recorridos en dispositivos Windows
o Android: este ticket cambia casos de uso y composición Dart compartidos,
sin modificar plataformas ni implementar pantallas.

Se consulta el ticket íntegro facilitado por el usuario; no hay conector Epic
Board disponible y no se modifica el estado administrativo del tablero. Los
cambios concurrentes de Drive y del mockup de categorías quedan fuera de la
entrega de este ticket.
