param(
    [string]$CMake = 'cmake',
    [string]$InnoDirectory = '.tools/inno-6.5.4'
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
# Known folders are resolved by native APIs. APPDATA/LOCALAPPDATA overrides do
# not isolate HKCU or Credential Manager. Only a disposable hosted job may run.
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:RUNNER_OS -cne 'Windows') {
    throw 'Solo permitido en un runner Windows hospedado desechable; nunca en un perfil personal o self-hosted.'
}
$contract = Get-Content (Join-Path $taskRoot 'packaging/windows/installation-contract.json') -Raw | ConvertFrom-Json
$destination = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs/Autofinance'
$support = Join-Path ([Environment]::GetFolderPath('ApplicationData')) $contract.supportRelativePath
$uninstallKey = 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/' + $contract.appId + '_is1'
$driveKey = 'HKCU:/' + $contract.driveRegistryRoot
foreach ($path in @($destination, $support, $uninstallKey, $driveKey)) {
    if (Test-Path -LiteralPath $path) { throw 'El perfil no esta vacio; no se instala ni retira ninguna instalacion existente.' }
}
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function RunInstaller([string]$Exe, [bool]$Success) {
    $p = Start-Process -FilePath $Exe -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/LANG=spanish') -WindowStyle Hidden -Wait -PassThru
    if (($Success -and $p.ExitCode -ne 0) -or (-not $Success -and $p.ExitCode -eq 0)) { throw 'Resultado de instalacion sintetica inesperado.' }
}
function AssertInstalled([string]$Version, [string]$Source) {
    if ((Get-ItemProperty -LiteralPath $uninstallKey).DisplayVersion -cne $Version -or
        (Hash (Join-Path $destination 'myautofinance.exe')) -cne (Hash $Source) -or
        (Test-Path -LiteralPath (Join-Path $destination '.autofinance-pending'))) { throw 'Instalacion incompleta o version incorrecta.' }
    if (-not (Test-Path -LiteralPath (Join-Path ([Environment]::GetFolderPath('Programs')) 'Autofinance.lnk'))) { throw 'Falta acceso de Inicio.' }
    foreach ($line in (Get-Content -LiteralPath (Join-Path $destination '.autofinance-files') | Select-Object -Skip 1)) {
        $fields = $line.Split("`t")
        if ($fields.Count -ne 3 -or $fields[2] -match '(^/|\\|:|(^|/)\.\.(/|$))') { throw 'Inventario instalado no valido.' }
        $file = Join-Path $destination $fields[2]
        if ((Hash $file) -cne $fields[0] -or (Get-Item -LiteralPath $file).Length -ne [long]$fields[1]) { throw 'Archivo instalado distinto del inventario.' }
    }
}
Push-Location $taskRoot
try {
    & ./scripts/check-windows-installer.ps1 -CMake $CMake -InnoDirectory $InnoDirectory
    $bridge = Join-Path $taskRoot '.tools/ma-tsk-232-native/Release/autofinance_setup_bridge.dll'
    $build = Join-Path $taskRoot '.tools/ma-tsk-233-fixture-native'
    & $CMake -S scripts/tests/installer-fixture -B $build -G 'Visual Studio 17 2022' -A x64
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo configurar fixture x64.' }
    & $CMake --build $build --config Release
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar fixture x64.' }
    $fixtures = @{}
    foreach ($revision in @('1', '2')) {
        $fixtureRoot = Join-Path $taskRoot ('.tools/ma-tsk-233-fixture-' + $revision)
        $exe = Join-Path $build ('v' + $revision + '/Release/myautofinance.exe')
        & node scripts/tests/package-installation-fixture.mjs $bridge $exe $fixtureRoot $revision
        if ($LASTEXITCODE -ne 0) { throw 'Entrada de fixture rechazada.' }
        & (Join-Path $InnoDirectory 'ISCC.exe') ('/DPackageInclude=' + (Join-Path $fixtureRoot 'output/package.iss.inc')) packaging/windows/autofinance.iss
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar instalador sintetico.' }
        $fixtures[$revision] = Join-Path $fixtureRoot ('output/Autofinance-0.0.0+' + $revision + '-windows-x64-private.exe')
    }
    # Sentinels contain no financial records. They are never passed to SQLite.
    New-Item -ItemType Directory -Path $support | Out-Null
    $sentinel = Join-Path $support 'synthetic-preservation.txt'
    [IO.File]::WriteAllText($sentinel, 'SYNTHETIC PRESERVATION FIXTURE')
    $sentinelHash = Hash $sentinel
    RunInstaller $fixtures['1'] $true
    AssertInstalled '0.0.0+1' (Join-Path $build 'v1/Release/myautofinance.exe')
    $firstOwnership = Hash (Join-Path $destination '.autofinance-files')
    RunInstaller $fixtures['1'] $true
    if ((Hash (Join-Path $destination '.autofinance-files')) -cne $firstOwnership) { throw 'Reparacion altero inventario.' }
    AssertInstalled '0.0.0+1' (Join-Path $build 'v1/Release/myautofinance.exe')
    RunInstaller $fixtures['2'] $true
    AssertInstalled '0.0.0+2' (Join-Path $build 'v2/Release/myautofinance.exe')
    $upgradedOwnership = Hash (Join-Path $destination '.autofinance-files')
    RunInstaller $fixtures['1'] $false
    AssertInstalled '0.0.0+2' (Join-Path $build 'v2/Release/myautofinance.exe')
    if ((Hash (Join-Path $destination '.autofinance-files')) -cne $upgradedOwnership) { throw 'Downgrade altero inventario.' }
    RunInstaller (Join-Path $destination 'unins000.exe') $true
    if ((Test-Path -LiteralPath $uninstallKey) -or (Test-Path -LiteralPath (Join-Path $destination 'myautofinance.exe')) -or
        (Hash $sentinel) -cne $sentinelHash) { throw 'Desinstalacion o conservacion sintetica incorrecta.' }
    $report = @{ reportVersion = 1; sourceCommit = (& git rev-parse HEAD).Trim(); kind = 'syntheticFixtureOnly'; result = 'passed'; checks = @('native-tests', 'inno-compilation', 'fresh-install', 'same-version-repair', 'upgrade', 'downgrade-rejected', 'uninstall', 'support-sentinel-preserved'); productionInstaller = 'not-built'; realWindowsE2E = 'pending T08' }
    $reportRoot = Join-Path $taskRoot '.tools/installer-ci-report'
    New-Item -ItemType Directory -Path $reportRoot | Out-Null
    [IO.File]::WriteAllText((Join-Path $reportRoot 'report.json'), (($report | ConvertTo-Json) + "`n"), (New-Object Text.UTF8Encoding($false)))
    Write-Output 'Fixture instalado/verificado/retirado en perfil hospedado desechable. Informe sanitizado; no es aceptacion del paquete real.'
}
finally { Pop-Location }
