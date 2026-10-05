# MA-TSK-101 · Consulta del árbol y las partidas de un mes

`budget.dart` publica `MonthlyBudgetQuery`, `MonthlyBudget` y
`MonthlyBudgetRow`. `createMonthlyBudgetQuery` compone la lectura con los
repositorios SQLite existentes y la conexión abierta de la sesión. No cambia
esquema, signos, persistencia ni operaciones de escritura.

```dart
final query = createMonthlyBudgetQuery(
  database: database,
  invalidation: categoryInvalidation,
);
final result = await query.read(BudgetMonth(2026, 1));
```

`activeTree` contiene todos los nodos activos en preorden: padre antes de sus
hijos, hermanos ordenados por nombre y UUID como desempate. Cada fila incluye
UUID, padre, profundidad, nombre, ruta completa y marca de ingreso heredada
de la raíz actual. Nombres y rutas repetidos no identifican partidas.

`budget` contiene la partida original o `null` si no existe. `ownAmountCents`
es exclusivamente su importe firmado en céntimos, también si vale cero.
No se incluyen agregados: una partida de padre no rellena hijos y una partida
de hijo no rellena el importe propio del padre. Un mes vacío devuelve el mismo
árbol activo con partidas e importes propios nulos, sin escribir ceros.

`archivedBudgets` contiene exclusivamente las filas archivadas que tienen
partida en ese mes, con la jerarquía y ruta actuales, aunque sus ancestros
también estén archivados. Las filas conservan el `BudgetRecord` completo:
ID, concepto, discrecionalidad, fila de origen, lote y ordinal. El detalle
puede abrir el ID mediante `BudgetManagement.get` y corregirlo mediante
`edit`; mantener su categoría archivada está permitido por el contrato
existente, mientras que crear o cambiar a un destino archivado se rechaza.
Reactivar la categoría vuelve a colocar su partida en el árbol activo.

La consulta no almacena caché. Lee categorías y partidas dentro de la misma
unidad de trabajo, sin modificar datos ni revisión. Devuelve colecciones
inmutables y `categoryGeneration` de la invalidación compartida de EP-008.
El consumidor escucha `query.invalidation.changes` y vuelve a consultar su
mes tras renombrar, trasladar, archivar, reactivar o restaurar la base. Tras
guardar o eliminar una partida también debe volver a consultar. Una
instantánea anterior conserva sus valores; no se actualiza en el sitio.
Al reemplazar la conexión se recompone la consulta con la conexión nueva y
el mismo objeto de invalidación de la sesión. No hay suscripciones internas
ni recursos adicionales que cerrar. Los fallos técnicos se presentan como
`BudgetFailureCode.persistence` con mensaje español, sin detalles SQL.

## Dependencias e integración

Se amplía el permiso inicial de arquitectura con `budget → movements` para
consumir únicamente los contratos públicos de categorías de EP-008, que
pertenecen a ese módulo. No se leen ni consumen movimientos reales. El grafo
sigue siendo acíclico: `movements` no depende de `budget`; `monthly_status`,
`indicators` e `importing` mantienen sus permisos y entradas públicas.
`test/architecture_test.dart` verifica también las dependencias transitivas.
No se añaden pantallas ni rutas, selector duplicado, saldos, informes anuales
o propuestas; los consumidores visuales continúan sujetos a T01.

No hay conector Epic Board disponible en esta sesión. Se utiliza el ticket
completo facilitado por el usuario y no se cambia el estado del tablero.

## Verificación

Las seis pruebas nuevas usan SQLite en memoria y datos sintéticos. Cubren
tres niveles, nombres repetidos incluso entre hermanas, importes de signo
contrario al tipo categorial, cero registrado, ausencia, meses independientes,
límites civiles, revisión sin cambios, histórico CSV archivado corregible,
reactivación, rutas y tipo tras reorganizar, invalidación compartida,
inmutabilidad y mensaje ante un fallo SQLite provocado.

Las pruebas dirigidas incluyen gestión de partidas, repositorio de presupuesto,
lecturas consumidoras de EP-008, reorganización, casos financieros de referencia
y fronteras de arquitectura. No se ejecutan builds ni recorridos nativos: la
consulta no modifica plataformas ni pantallas.

Resultado local del 2026-10-05, con Flutter 3.47.0 / Dart 3.13.0:

- `check-toolchain.ps1` correcto y dependencias resueltas con
  `flutter pub get --enforce-lockfile`, sin cambios de SDK ni lockfile.
- 44 pruebas dirigidas correctas, incluidas las seis nuevas de lectura.
- `scripts/check-quality.ps1` correcto: formato sin cambios, análisis sin
  incidencias, 1.017 pruebas generales y las cuatro variantes de arranque
  `APP_ENV` correctas.
- `git diff --cached --check` sin errores en los cinco archivos del ticket.

La resolución de paquetes y la batería con SQLite de fichero se ejecutan fuera
del sandbox para permitir acceso a pub.dev y los bloqueos de fichero existentes.
