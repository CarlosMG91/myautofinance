param(
    [Parameter(Mandatory = $true)][string]$RuntimeCrtDirectory,
    [Parameter(Mandatory = $true)][string]$VisualStudioLicensePath,
    [string]$InnoDirectory = '.tools/inno-6.5.4',
    [string]$CMake = 'cmake'
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
Push-Location $taskRoot
try {
    if ($env:GITHUB_ACTIONS -eq 'true') { throw 'Produccion es solo local; CI utiliza exclusivamente el fixture.' }
    $status = @(& git status --porcelain --untracked-files=all)
    if ($LASTEXITCODE -ne 0 -or $status.Count) { throw 'Entrega bloqueada: se requiere un checkout limpio, sin cambios concurrentes.' }
    $commit = (& git rev-parse HEAD).Trim()
    if ($commit -notmatch '^[0-9a-f]{40}$') { throw 'Commit no verificable.' }
    if (Test-Path -LiteralPath build) { throw 'Usar checkout nuevo sin build; no se borra ninguna compilacion compartida.' }
    & flutter --version
    if ($LASTEXITCODE -ne 0) { throw 'Flutter no disponible.' }
    & ./scripts/check-toolchain.ps1
    & node scripts/check-google-oauth.mjs --require-configured
    if ($LASTEXITCODE -ne 0) { throw 'Produccion bloqueada: OAuth pendiente.' }
    $inno = (Resolve-Path -LiteralPath $InnoDirectory).Path
    # Quality runs on exactly HEAD in a separate source export. Flutter tests may
    # populate build/, which must never contaminate the production payload tree.
    $qualityRoot = Join-Path $taskRoot ('.tools/delivery-quality-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $qualityRoot | Out-Null
    $archive = Join-Path $qualityRoot 'source.tar'
    & git archive --format=tar ('--output=' + $archive) $commit
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron exportar las fuentes de calidad.' }
    & tar -xf $archive -C $qualityRoot
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron extraer las fuentes de calidad.' }
    & (Join-Path $qualityRoot 'scripts/check-quality.ps1')
    & node --test scripts/tests/windows-payload.test.mjs scripts/tests/windows-installer.test.mjs scripts/tests/windows-delivery.test.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas de empaquetado.' }
    & ./scripts/prepare-windows-payload.ps1 -RuntimeCrtDirectory $RuntimeCrtDirectory -VisualStudioLicensePath $VisualStudioLicensePath -InnoDirectory $inno
    $version = (Select-String -Path pubspec.yaml -Pattern '^version: (\S+)').Matches[0].Groups[1].Value
    $payloadRoot = Join-Path $taskRoot ('dist-private/windows/payload-' + $version + '-' + $commit.Substring(0,12))
    $payloadManifest = Join-Path $payloadRoot 'payload-manifest.json'
    & ./scripts/build-windows-installer.ps1 -PayloadDirectory (Join-Path $payloadRoot 'payload') -PayloadManifestPath $payloadManifest -InnoDirectory $inno -CMake $CMake
    $output = Join-Path $taskRoot ('dist-private/windows/installer-' + $version + '-' + $commit.Substring(0,12))
    $quality = @{ sourceCommit = $commit; status = 'passed'; command = 'scripts/check-quality.ps1'; lockfileSha256 = (Hash pubspec.lock); toolchainSha256 = (Hash toolchain.json) }
    $qualityPath = Join-Path $output 'quality.json'
    [IO.File]::WriteAllText($qualityPath, ($quality | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    $status = @(& git status --porcelain --untracked-files=all)
    if ($LASTEXITCODE -ne 0 -or $status.Count -or (& git rev-parse HEAD).Trim() -cne $commit) { throw 'Las fuentes cambiaron durante la generacion; entrega rechazada.' }
    & node scripts/windows-delivery.mjs (Join-Path $payloadRoot 'payload') $payloadManifest $output $qualityPath $commit
    if ($LASTEXITCODE -ne 0) { throw 'Manifiesto final rechazado. No transferir como entrega verificada.' }
    Write-Output ('Entrega privada: ' + (Join-Path $output 'delivery') + '. Compilacion verificada; aceptacion E2E T08 pendiente. Transferir manualmente; no publicar.')
}
finally { Pop-Location }
