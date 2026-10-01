# MA-TSK-034 · Fichas y liquidez histórica

El esquema físico v3 añade `accounts` y `account_liquidity_periods` a Drift.
Los snapshots publicados v1/v2 se conservan. Las migraciones consecutivas
1 → 2 → 3 y 2 → 3 son transaccionales y preservan categorías, UUID de las
fichas, dataset_id y revision; el predecesor sintético 0 también llega a v3.
LocalDatabaseStore conserva el respaldo consistente previo a migrar.

`AccountRepository`, `AccountRecord`, `LiquidityPeriod`, `Month` y los enums
se publican desde wealth. `SqliteAccountRepository` recibe LocalDatabase por
constructor en app/data/sqlite, siguiendo el adaptador existente de categorías.
No se conecta a pantallas ni al arranque de los marcadores técnicos.

- Alta de cuenta/cartera exige clasificación inicial y crea su cobertura en
  la misma transacción. Deuda exige liquidez nula y no admite periodos.
- `listForMonth` devuelve únicamente fichas vigentes, alta/baja inclusivas,
  con clasificación efectiva de ese mes. `get` conserva la ficha tras baja;
  no presenta una clasificación actual como si fuera histórica.
- `changeLiquidity` divide el periodo que contiene el mes elegido y conserva
  todos los meses anteriores y los cambios posteriores ya programados.
- `correctHistoricalLiquidity` es una operación explícita sobre [from,until).
  Conserva las partes exteriores; until nulo alcanza el fin de vigencia.
  Los periodos sustituidos se retiran y sus fragmentos reciben identidad nueva;
  la identidad de la ficha y sus referencias no cambian.
- `close` recorta la cobertura al mes siguiente de la baja. No borra la ficha,
  movimientos ni valores; rechaza una baja que deje referencias fuera de
  vigencia. No permite reutilizar una ficha cerrada. Renombrar conserva UUID.
  El tipo es inmutable; no hay API de cambio de alta ni borrado físico.

Meses son texto civil YYYY-MM-01, con años 0001–9999. El mes siguiente a
9999-12 se representa mediante fin abierto, sin construir el año 10000.
CHECK/FK/UNIQUE y triggers protegen formato, tipos, límites y solapes incluso
ante INSERT/UPDATE directos. La cobertura contigua exacta se verifica antes
de guardar cambios y al abrir/validar una copia: se rechazan huecos y activos
sin clasificación. No se exige cobertura en cada sentencia SQL intermedia,
porque dividir un periodo necesita retirar e insertar dentro de la transacción.

Movimientos y fotos reales corresponden a otros tickets. Aquí se comprueban
sus referencias mediante fixtures sintéticos con FK y se prevé su consulta
cuando existan sus tablas; sus migraciones deberán incorporar también los
triggers de vigencia y protección de referencias del contrato compartido.
La revisión central por escritura de negocio sigue perteneciendo a su ticket;
la migración técnica conserva el valor existente.

## Verificación local (2026-10-01)

Flutter 3.47.0 / Dart 3.13.0 comprobados, dependencias resueltas con lockfile
obligatorio sin modificaciones. Generación Drift y snapshot v3 exportados.
`scripts/check-quality.ps1` completo: formato, an?lisis sin incidencias,
49 pruebas y las cuatro variantes de APP_ENV correctas. `git diff --check`
sin errores. Pruebas SQLite real: alta/baja inclusivas, activos/deuda, cambios programados,
corrección histórica acotada, límites de calendario, reapertura y nombres,
solapes INSERT/UPDATE, FK/CHECK, conservación de referencias, rechazo de huecos,
rollback de alta/división, migración v2 con categorías y revisión, rollback de
migración y comparación exacta del esquema migrado con snapshot v3.
EXPLAIN QUERY PLAN confirma uso de índice para cuenta/inicio de periodo.
Las pruebas anteriores mantienen migración desde v0/v1, respaldo con WAL y
conservación de metadatos. El comprobador EP-001 pasa sin alterar sus cifras.

La prueba de integración nativa incorpora cambio de liquidez, corrección,
baja y consultas históricas tras reapertura. No se ha ejecutado localmente en
Windows/Android ni se acredita un resultado remoto. No cambian plataformas,
SDK ni dependencias y no se repiten builds nativos en este ticket.
No se implementan fotos, informes, CSV, Drive ni pantallas.
Se utiliza el ticket íntegro proporcionado: no hay conector Epic Board
disponible para consultar o modificar su estado administrativo.
