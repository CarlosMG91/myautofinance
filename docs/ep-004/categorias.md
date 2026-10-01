# MA-TSK-033 · Categorías persistentes

La versión física 2 añade `categories`, índice de padre y triggers de inserción
y cambio de padre. Conserva el snapshot v1 publicado. La migración 1 → 2 es
transaccional, conserva dataset_id/revision y usa el respaldo previo del store;
el predecesor sintético 0 recorre también el paso inicial de metadatos.
La política reconoce los objetos exactos y rechaza árboles corruptos al abrir.

`CategoryRepository` y `CategoryNode` se exportan desde movements, propietario
de la clasificación de reales. El adaptador `SqliteCategoryRepository` vive en
app/data/sqlite para recibir LocalDatabase por constructor sin invertir las
fronteras entre módulos. Budget podrá consumir este contrato público cuando su
ticket revise la dependencia correspondiente; aquí no cambia el grafo.

Crear, consultar, editar y archivar/reactivar ramas son operaciones disponibles.
La marca persistida es obligatoria en raíces (por defecto salida al crear) y
nula en descendientes; las consultas devuelven la condición efectiva heredada.
Editar recibe nombre, padre y marca completos. Se validan todos los descendientes
al mover una rama, además de ciclos, padre inexistente y profundidad máxima tres.
SQLite protege también estas reglas ante escrituras directas. Nombres duplicados
son válidos; se conservan exactamente los nombres mostrados y los UUID.
Los errores de validación del repositorio tienen mensajes españoles.

Archivar/reactivar modifica toda la rama en una transacción. Consultar incluye
archivados por defecto; el filtro explícito sirve al selector de categorías.
Se rechaza crear bajo un padre archivado y reactivar bajo un padre todavía
archivado. No existe operación de borrado ni una fila especial Sin clasificar.
La clasificación pendiente seguirá siendo category_id nulo en movimientos.

Las tablas de movimientos y presupuesto todavía pertenecen a otros tickets.
Las pruebas usan tablas sintéticas con sus FK para demostrar conservación de
referencias al archivar. El adaptador impide cambiar padre o ingreso si esas
tablas contienen referencias a la rama. Al incorporar las tablas reales, sus
migraciones deberán añadir la protección SQL de historia y de nuevas asignaciones
a nodos archivados, conforme a modelo-datos.md. Este ticket no crea esas tablas
ni implementa sus repositorios. El incremento central de revisión por escritura
de negocio queda para su ticket de revisión local; migrar conserva la revisión.

## Verificación local del 2026-10-01

- SDK fijado Flutter 3.47.0 / Dart 3.13.0 y lockfile comprobados, sin cambios
  incidentales de dependencias. Generación Drift y snapshot v2 exportados.
- check-quality.ps1 completo: formato, análisis sin incidencias, 41 pruebas y
  las cuatro variantes de APP_ENV. Verificación posterior del módulo después
  de añadir rollback v1 → v2 y normalizar auditoría UTC a milisegundos.
- SQLite real: árbol válido/inválido, subárbol demasiado profundo, edición,
  ingreso heredado, nombres preservados, archivo/reactivación, reapertura,
  referencias históricas sintéticas, CHECK/FK/triggers, migración y respaldo,
  rollback con versión y datos intactos, esquema migrado igual al snapshot.
- Comprobador de referencia EP-001: OK, sin modificar las cifras del contrato.

La prueba de integración existente se amplía con categorías y será ejecutada
por los jobs nativos Windows/Android de CI. No se ha ejecutado localmente en
dispositivo ni se acredita un resultado remoto. No cambian los proyectos de
plataforma y no se repiten builds nativos; persisten las limitaciones de entorno
registradas por MA-TSK-032. No se implementan pantallas, CSV, informes ni Drive.
Se utiliza el ticket completo facilitado por el usuario: no hay conector Epic
Board disponible y no se modifica su estado administrativo.

Referencia técnica consultada: [migraciones Drift](https://drift.simonbinder.eu/migrations/api/).
