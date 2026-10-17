# Recuperar una copia portable para consulta

Guía T07 de EP-027. Sirve para cualquier ZIP `autofinance.portableBackup` v1,
incluidos los creados desde Android. Es una lectura independiente: no abre la
base activa ni inicia Autofinance, Flutter, Drive o una sesión.

## Herramientas

- Windows 10/11 y PowerShell 5.1 o posterior (`Get-FileHash`, `Expand-Archive`).
- Un lector ZIP estándar. Los ejemplos usan `Expand-Archive` de Windows.
- SQLite 3 con CLI `sqlite3.exe` en el `PATH`; la opción `-readonly` debe estar
  disponible. T03 comprobó una copia ZIP real con SQLite 3.50.4. No requiere
  extensiones de Autofinance.
- Editor de texto para `manifest.json` y este LEEME. No se requieren SDK Flutter,
  credenciales, Internet ni acceso al teléfono por root/adb/run-as. Android no
  promete acceso a su almacenamiento privado mediante esas herramientas.

El ZIP incluye su propio `LEEME.md`, manifiesto y base. Esta guía, también
publicada en el repositorio, amplía consultas y resultados de referencia. La
definición efectiva de columnas, restricciones, índices y relaciones está en
`sqlite_schema` dentro de la propia base exportada; se consulta allí y no se
deduce de snapshots Drift antiguos. La versión de esquema se obtiene del
manifiesto y `PRAGMA user_version` de esa copia (la revisión vigente de esta
guía es v8; siempre se compara el valor real, no se fuerza una migración).

## Validar y extraer a una carpeta nueva

Conserve el ZIP original. Sustituya únicamente `$zip` por su ruta. Las comillas
permiten espacios y tildes; cree un directorio nuevo y vacío que no pertenezca
a Autofinance:

```powershell
$zip = 'C:\Users\Carlo\Documents\Copia familiar\autofinance.zip'
$dest = 'C:\Users\Carlo\Documents\Consulta nueva\Copia financiera'
if (Test-Path -LiteralPath $dest) { throw 'El destino debe ser nuevo e inexistente.' }
New-Item -ItemType Directory -Path $dest | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
  $names = @($archive.Entries | ForEach-Object FullName)
  $expected = @('LEEME.md', 'autofinance.sqlite', 'manifest.json')
  $actualSet = ($names | Sort-Object -CaseSensitive) -join "`n"
  $expectedSet = ($expected | Sort-Object -CaseSensitive) -join "`n"
  if ($actualSet -cne $expectedSet) {
    throw 'Inventario ZIP inesperado; no extraer.'
  }
  foreach ($entry in $archive.Entries) {
    if ($entry.FullName -match '(^|[/\\])\.\.([/\\]|$)|^[/\\]|:|\\') { throw "Ruta ZIP no permitida: $($entry.FullName)" }
    if ($entry.Length -le 0 -or $entry.Length -gt 1GB) { throw 'Tamaño ZIP inválido o superior al límite local de 1 GiB.' }
  }
  $manifestEntry = $archive.GetEntry('manifest.json')
  $reader = [System.IO.StreamReader]::new($manifestEntry.Open(), [System.Text.Encoding]::UTF8, $true)
  try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
  if ($manifest.kind -cne 'autofinance.portableBackup' -or $manifest.formatVersion -ne 1 -or $manifest.currency -cne 'EUR' -or $null -ne $manifest.filter -or $null -ne $manifest.dictionary) { throw 'Tipo, versión o metadatos inesperados.' }
  $manifestFiles = ($manifest.files.path | Sort-Object -CaseSensitive) -join "`n"
  $expectedFiles = (@('LEEME.md','autofinance.sqlite') | Sort-Object -CaseSensitive) -join "`n"
  if ($manifestFiles -cne $expectedFiles) { throw 'Lista files inesperada.' }
  foreach ($f in $manifest.files) {
    $entry = $archive.GetEntry([string]$f.path)
    if ($null -eq $entry -or [string]$entry.Length -cne [string]$f.sizeBytes) { throw "Tamaño distinto: $($f.path)" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = $entry.Open()
    try { $actualHash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
    finally { $stream.Dispose(); $sha.Dispose() }
    if ($actualHash -cne $f.sha256) { throw "SHA-256 distinto: $($f.path)" }
  }
} finally { $archive.Dispose() }
Expand-Archive -LiteralPath $zip -DestinationPath $dest
```

Si el inventario, versión o hash no coincide, deténgase y conserve el original.
`SHA-256` detecta cambios de bytes, pero no autentica quién creó el ZIP. El
manifiesto público no está firmado. Los tamaños del manifiesto son cadenas
decimales exactas; no los convierta a coma flotante. El ejemplo limita cada
entrada a 1 GiB; el ZIP v1 de la aplicación también tiene un límite de tamaño.

La extracción no reemplaza una instalación. Nunca copie `autofinance.sqlite`
sobre la base activa ni copie junto a ella `-wal`, `-shm` o `-journal`. El ZIP
portable válido contiene solo `LEEME.md`, `autofinance.sqlite` y `manifest.json`.

## Abrir en solo lectura y verificar esquema

Desde PowerShell, use la ruta completa entre comillas. La opción `-readonly`
evita que SQLite modifique el archivo:

```powershell
$db = Join-Path $dest 'autofinance.sqlite'
sqlite3 -readonly "$db" "PRAGMA integrity_check; PRAGMA foreign_key_check; PRAGMA application_id; PRAGMA user_version; SELECT dataset_id, revision FROM database_state WHERE singleton=1;"
```

Resultados esperados: `integrity_check` devuelve `ok`; `foreign_key_check` no
devuelve filas; `application_id`, `user_version`, `dataset_id` y `revision`
coinciden exactamente con `applicationId`, `schemaVersion`, `datasetId` y
`revision` del manifiesto. `revision` puede ser int64 grande: trátelo como texto.
Compruebe conteos del manifiesto con, por ejemplo,
`sqlite3 -readonly "$db" "SELECT count(*) FROM movements;"` y repita para cada
nombre de `databaseTables`. No continúe si hay discrepancias.

Consultar esquema y claves externas reales:

```powershell
sqlite3 -readonly "$db" "SELECT type,name,sql FROM sqlite_schema WHERE name NOT GLOB 'sqlite_*' ORDER BY type,name;"
sqlite3 -readonly "$db" "PRAGMA table_info(movements); PRAGMA foreign_key_list(movements);"
```

El esquema actual incluye `database_state`, `categories`, `accounts`,
`account_liquidity_periods`, `movements`, `budgets`, `wealth_snapshots`,
`wealth_values` y tablas de procedencia de importación. La base exportada es
completa. No aplica el filtro temporal de CSV.

## Céntimos, categorías y flujos

Todos los importes financieros se almacenan como `INTEGER` en céntimos EUR.
Consérvelos como enteros, sin `REAL`, `double` ni redondeo. `amount_cents` de
movimientos y presupuestos conserva el signo de Autofinance: ingresos suelen
ser positivos y gastos negativos, pero el signo no determina la categoría de
ingreso. Los presupuestos son entidades distintas, admiten cero y no invierten
el signo como el CSV histórico EP-013. Los valores de foto son magnitudes
positivas; la deuda se resta al calcular patrimonio neto.

```sql
-- Movimientos reales. Categoría NULL significa sin clasificar.
SELECT m.id, m.value_date, m.concept, m.amount_cents,
       m.category_id, c.name AS categoria, a.name AS cuenta
FROM movements AS m
JOIN accounts AS a ON a.id=m.account_id
LEFT JOIN categories AS c ON c.id=m.category_id
ORDER BY m.value_date, m.id;

-- Presupuestos firmados, separados de los movimientos reales.
WITH RECURSIVE roots(id,root_id,is_income) AS (
  SELECT id,id,is_income FROM categories WHERE parent_id IS NULL
  UNION ALL
  SELECT c.id,r.root_id,r.is_income FROM categories AS c
  JOIN roots AS r ON c.parent_id=r.id
)
SELECT b.month, b.amount_cents, b.concept, c.name AS categoria,
       root.name AS raiz, r.is_income AS ingreso_raiz
FROM budgets AS b
JOIN categories AS c ON c.id=b.category_id
JOIN roots AS r ON r.id=c.id
JOIN categories AS root ON root.id=r.root_id
ORDER BY b.month, b.id;

-- La ruta recursiva permite ver raíz y antecesores sin duplicar importes.
WITH RECURSIVE tree(id,parent_id,name,is_income,depth,path) AS (
  SELECT id,parent_id,name,is_income,1,name FROM categories WHERE parent_id IS NULL
  UNION ALL
  SELECT c.id,c.parent_id,c.name,t.is_income,t.depth+1,t.path || ' / ' || c.name
  FROM categories AS c JOIN tree AS t ON c.parent_id=t.id
)
SELECT id,parent_id,path,depth,is_income FROM tree ORDER BY path,id;
```

La categoría de ingreso es una marca de la raíz (`is_income`); sus
descendientes tienen `NULL`. Una categoría real nula no crea una categoría ni
implica ingreso. Presupuesto y real se agregan por separado, y cada registro se
cuenta una vez; no sume simultáneamente padre e hijo.

## Fotos manuales, liquidez y meses sin dato

Cada `wealth_snapshots.month` es una foto manual del día 1. No se calcula desde
movimientos ni se arrastra al mes siguiente. Una cabecera sin valores es
`absent`; si existen valores pero falta una cuenta vigente, es `incomplete`; si
todas las cuentas vigentes tienen valor, es `complete`. Cero registrado es un
valor real y distinto de ausencia. La liquidez es histórica en
`account_liquidity_periods`: `from_month` inclusivo y `until_month` exclusivo;
`NULL` significa sin límite. Las deudas no tienen periodo de liquidez.

```sql
WITH expected AS (
  SELECT s.id AS snapshot_id, s.month, a.id AS account_id, a.name, a.kind,
         p.liquidity
  FROM wealth_snapshots AS s
  JOIN accounts AS a ON a.active_from<=s.month
       AND (a.active_through IS NULL OR a.active_through>=s.month)
  LEFT JOIN account_liquidity_periods AS p ON p.account_id=a.id
       AND p.from_month<=s.month
       AND (p.until_month IS NULL OR s.month<p.until_month)
), status AS (
  SELECT s.id,s.month,count(e.account_id) AS expected,
         count(v.id) AS registered,
         CASE WHEN count(v.id)=0 THEN 'absent'
              WHEN count(v.id)<count(e.account_id) THEN 'incomplete'
              ELSE 'complete' END AS state
  FROM wealth_snapshots AS s
  LEFT JOIN expected AS e ON e.snapshot_id=s.id
  LEFT JOIN wealth_values AS v ON v.snapshot_id=s.id AND v.account_id=e.account_id
  GROUP BY s.id,s.month
)
SELECT * FROM status ORDER BY month;

-- Detalle de valores, cuenta y clasificación de liquidez del mes.
SELECT s.month,a.name,a.kind,p.liquidity,v.amount_cents
FROM wealth_snapshots AS s
JOIN wealth_values AS v ON v.snapshot_id=s.id
JOIN accounts AS a ON a.id=v.account_id
LEFT JOIN account_liquidity_periods AS p ON p.account_id=a.id
     AND p.from_month<=s.month
     AND (p.until_month IS NULL OR s.month<p.until_month)
ORDER BY s.month,a.id;

-- Cuentas vigentes sin valor: lista qué falta en una foto parcial.
SELECT s.month,a.id,a.name,a.kind
FROM wealth_snapshots AS s
JOIN accounts AS a ON a.active_from<=s.month
     AND (a.active_through IS NULL OR a.active_through>=s.month)
LEFT JOIN wealth_values AS v ON v.snapshot_id=s.id AND v.account_id=a.id
WHERE v.id IS NULL ORDER BY s.month,a.id;

-- Subtotales únicamente cuando la foto está completa (no usar suma parcial).
WITH expected AS (
  SELECT s.id snapshot_id,s.month,a.id account_id,a.kind,p.liquidity
  FROM wealth_snapshots AS s JOIN accounts AS a ON a.active_from<=s.month
  AND (a.active_through IS NULL OR a.active_through>=s.month)
  LEFT JOIN account_liquidity_periods AS p ON p.account_id=a.id
  AND p.from_month<=s.month AND (p.until_month IS NULL OR s.month<p.until_month)
), complete AS (
  SELECT e.snapshot_id,e.month,count(e.account_id) expected,
         count(v.id) registered
  FROM expected e LEFT JOIN wealth_values v
       ON v.snapshot_id=e.snapshot_id AND v.account_id=e.account_id
  GROUP BY e.snapshot_id,e.month HAVING count(e.account_id)=count(v.id)
)
SELECT c.month,
       sum(CASE WHEN e.kind<>'debt' THEN v.amount_cents ELSE 0 END) assets_cents,
       sum(CASE WHEN e.kind='debt' THEN v.amount_cents ELSE 0 END) debt_cents,
       sum(CASE WHEN e.kind<>'debt' AND e.liquidity='liquid'
                THEN v.amount_cents ELSE 0 END) liquid_assets_cents
FROM complete c JOIN expected e ON e.snapshot_id=c.snapshot_id
JOIN wealth_values v ON v.snapshot_id=e.snapshot_id AND v.account_id=e.account_id
GROUP BY c.month ORDER BY c.month;

-- Meses sin siquiera cabecera de foto: no hay fila ni equivale a cero.
WITH RECURSIVE months(month) AS (
  SELECT '2026-01-01'
  UNION ALL SELECT date(month,'+1 month') FROM months WHERE month<'2026-12-01'
)
SELECT m.month FROM months AS m
LEFT JOIN wealth_snapshots AS s ON s.month=m.month
WHERE s.id IS NULL ORDER BY m.month;
```

Para meses sin cabecera se genera un calendario acorde al periodo que se
consulta, como arriba. No se convierta la suma parcial de una foto incompleta
en patrimonio. Las fichas esperadas se determinan por vigencia inclusiva; las
fotos no completas equivalen a «sin dato» en la app. Los subtotales son INTEGER
céntimos; no calcule en SQLite `REAL` ni asuma que los acumulados arbitrariamente
grandes caben en int64. Si el total puede excederlo, lea los valores y sume con
aritmética entera de precisión arbitraria fuera de SQLite.

## Contraste con los casos EP-001

Los casos de referencia usan el CSV histórico sintético importado y las fotos
indicadas en `docs/ep-001/casos-referencia.md`. La consulta de los dos «Café»
de enero recupera **dos filas distintas** (no deduplicar por texto):

```sql
SELECT m.id,m.value_date,m.amount_cents,m.concept,c.name AS categoria
FROM movements AS m
LEFT JOIN categories AS c ON c.id=m.category_id
WHERE m.value_date>='2026-01-01' AND m.value_date<'2026-02-01'
  AND m.concept='Café'
ORDER BY m.value_date,m.id;

-- Totales firmados separados; aplicados a los datos base EP-001.
SELECT sum(amount_cents) AS real_enero_cents FROM movements
WHERE value_date>='2026-01-01' AND value_date<'2026-02-01';
SELECT sum(amount_cents) AS real_2026_cents FROM movements
WHERE value_date>='2026-01-01' AND value_date<'2027-01-01';
SELECT sum(amount_cents) AS presupuesto_2026_cents FROM budgets
WHERE month>='2026-01-01' AND month<'2027-01-01';

-- Activos líquidos y patrimonio neto de la foto completa de enero.
SELECT sum(CASE WHEN a.kind<>'debt' AND p.liquidity='liquid'
                THEN v.amount_cents ELSE 0 END) activos_liquidos_cents,
       sum(CASE WHEN a.kind<>'debt' THEN v.amount_cents ELSE 0 END)
         -sum(CASE WHEN a.kind='debt' THEN v.amount_cents ELSE 0 END)
         patrimonio_neto_cents
FROM wealth_snapshots s JOIN wealth_values v ON v.snapshot_id=s.id
JOIN accounts a ON a.id=v.account_id
LEFT JOIN account_liquidity_periods p ON p.account_id=a.id
  AND p.from_month<=s.month AND (p.until_month IS NULL OR s.month<p.until_month)
WHERE s.month='2026-01-01';
```

En esos datos las dos filas suman `-2000` céntimos (`-20,00 EUR`).
Agregaciones firmadas esperadas del caso base:

| Consulta | Céntimos | EUR |
|---|---:|---:|
| Real enero | 122975 | +1.229,75 |
| Real anual 2026 | 232965 | +2.329,65 |
| Presupuesto anual 2026 | 1320000 | +13.200,00 |
| Dos movimientos «Café» de enero | -2000 | -20,00 |
| Activos líquidos de la foto completa enero | 900000 | 9.000,00 |
| Patrimonio neto de la foto completa enero | 1400000 | 14.000,00 |

En la base de referencia, febrero no tiene foto y devuelve «sin dato»; no se
repite enero. La variante de febrero parcialmente completada también devuelve
«sin dato» y señala cuentas pendientes. Tras añadir los valores faltantes,
incluido `0` céntimos válido para Cuenta de ahorro, la foto es completa:
activos líquidos `620000` céntimos, activos totales `1670000`, deuda `480000` y
patrimonio neto `1190000`. La prueba contractual adicional de categoría, signos
y estados de foto está en `docs/ep-001/casos-referencia.md`; no se afirme que
esta base exportada contiene esas cifras si se trata de otros datos.

Para reproducir el verificador aritmético de los datos históricos sintéticos,
desde la raíz del repositorio:

```powershell
node docs/ep-001/verificar-casos.mjs
```

Esto verifica la fixture CSV de referencia; no altera ni importa la copia
SQLite. Los comandos SQLite de arriba consultan exclusivamente la base extraída.

## Alcance de recuperación

Esta lectura no sustituye ni restaura una instalación Autofinance. La
restauración de instalaciones sigue los mecanismos de copia/restauración de la
app. No reconstruya ni importe estos CSV/SQLite como CSV histórico EP-013, no
intente fusionarlos y no reemplace manualmente la base activa. La exportación
CSV tiene otro esquema y signos deliberadamente explícitos; tampoco promete
reimportación ni reconstrucción desde CSV.
