param(
    [Parameter(Mandatory = $true)][string]$Zip,
    [Parameter(Mandatory = $true)][string]$Destination,
    [string]$Sqlite = 'sqlite3'
)
$ErrorActionPreference = 'Stop'

# Ejecuta el bloque de validación/extracción publicado, sin mantener una segunda
# implementación. Solo cambian las dos rutas de ejemplo. No abre Autofinance.
$guidePath = Join-Path $PSScriptRoot '../docs/ep-027/recuperacion-sqlite.md'
$guide = Get-Content -LiteralPath $guidePath -Raw -Encoding UTF8
$block = [regex]::Match($guide, '(?s)```powershell\r?\n(.*?)```').Groups[1].Value
$lines = $block -split '\r?\n'
if ($lines[0] -notmatch '^\$zip = ' -or $lines[1] -notmatch '^\$dest = ') {
    throw 'El ejemplo T07 ha cambiado: revisar este recorrido antes de ejecutarlo.'
}
$zip = (Resolve-Path -LiteralPath $Zip).Path
$dest = [IO.Path]::GetFullPath($Destination)
$originalHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
& ([scriptblock]::Create(($lines | Select-Object -Skip 2) -join "`n"))
if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -cne $originalHash) {
    throw 'La validación alteró el ZIP original.'
}
$db = Join-Path $dest 'autofinance.sqlite'
$databaseHash = (Get-FileHash -LiteralPath $db -Algorithm SHA256).Hash
$manifest = Get-Content -LiteralPath (Join-Path $dest 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
function Read-Sqlite([string]$Query) {
    # El CLI interpreta un argumento que empieza por -- como opción. Un salto
    # inicial permite ejecutar literalmente los bloques que abren con comentario.
    $answer = & $Sqlite -readonly $db ("`n" + $Query)
    if ($LASTEXITCODE -ne 0) { throw 'La consulta SQLite de T07 ha fallado.' }
    return $answer
}
if ((Read-Sqlite 'PRAGMA integrity_check;') -cne 'ok') { throw 'Integridad incorrecta.' }
if (Read-Sqlite 'PRAGMA foreign_key_check;') { throw 'Referencias incorrectas.' }
foreach ($pair in @(@('application_id', 'applicationId'), @('user_version', 'schemaVersion'))) {
    if ([string](Read-Sqlite "PRAGMA $($pair[0]);") -cne [string]$manifest.($pair[1])) {
        throw 'El esquema o application_id no coincide con el manifiesto.'
    }
}
$identity = Read-Sqlite "SELECT dataset_id || '|' || CAST(revision AS TEXT) FROM database_state WHERE singleton=1;"
if ($identity -cne "$($manifest.datasetId)|$($manifest.revision)") { throw 'Identidad/revisión distinta.' }
foreach ($table in $manifest.databaseTables) {
    if ($table.name -notmatch '^[a-z_]+$') { throw 'Nombre de tabla inesperado.' }
    if ([string](Read-Sqlite "SELECT count(*) FROM $($table.name);") -cne [string]$table.rowCount) {
        throw 'Conteo de tabla distinto.'
    }
}
$blocks = [regex]::Matches($guide, '(?s)```sql\r?\n(.*?)```')
foreach ($sql in $blocks) {
    # Se conserva salida para inspección del caso base, sin reescribir consultas.
    Read-Sqlite $sql.Groups[1].Value
}
if ((Get-FileHash -LiteralPath $db -Algorithm SHA256).Hash -cne $databaseHash) { throw 'SQLite modificada.' }
Write-Output 'OK: bloque T07, identidad, esquema, referencias, conteos y consultas SQLite; original y base extraída intactos.'
