param(
    [Parameter(Mandatory = $true)][string]$PayloadDirectory,
    [Parameter(Mandatory = $true)][string]$PayloadManifestPath,
    [string]$InnoDirectory = '.tools/inno-6.5.4',
    [string]$CMake = 'cmake'
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
Push-Location $taskRoot
try {
    $pin = Get-Content packaging/windows/payload-toolchain.json -Raw | ConvertFrom-Json
    $contract = Get-Content packaging/windows/installation-contract.json -Raw | ConvertFrom-Json
    $sourceStatus = @(& git status --porcelain --untracked-files=all)
    if ($LASTEXITCODE -ne 0 -or $sourceStatus.Count -ne 0) { throw 'Instalador de produccion bloqueado: usar un checkout limpio; no incluir cambios concurrentes.' }
    $commit = (& git rev-parse HEAD).Trim()
    if ($commit -notmatch '^[0-9a-f]{40}$') { throw 'Commit no verificable.' }
    & flutter --version
    if ($LASTEXITCODE -ne 0) { throw 'Flutter no disponible.' }
    & ./scripts/check-toolchain.ps1
    & node scripts/check-google-oauth.mjs --require-configured
    if ($LASTEXITCODE -ne 0) { throw 'Produccion bloqueada: OAuth sin configurar.' }
    $payload = (Resolve-Path -LiteralPath $PayloadDirectory).Path
    $payloadManifest = (Resolve-Path -LiteralPath $PayloadManifestPath).Path
    & node scripts/windows-payload.mjs verify $payload $payloadManifest
    if ($LASTEXITCODE -ne 0) { throw 'Payload cerrado no valido.' }
    $candidate = Get-Content -LiteralPath $payloadManifest -Raw | ConvertFrom-Json
    if ($candidate.sourceCommit -cne $commit -or $candidate.sourceDirty -ne $false) { throw 'Payload y adaptador deben proceder del mismo commit limpio.' }
    $inno = (Resolve-Path -LiteralPath $InnoDirectory).Path
    $iscc = Join-Path $inno 'ISCC.exe'
    & $iscc /O- packaging/windows/compiler-version.iss
    if ($LASTEXITCODE -ne 0) { throw 'Inno distinto de 6.5.4.' }
    $receipt = Get-Content -LiteralPath (Join-Path $inno 'provenance.json') -Raw | ConvertFrom-Json
    if ((Hash (Join-Path $inno 'verified-installer.exe')) -cne $pin.inno.sha256 -or
        $receipt.installerSha256 -cne $pin.inno.sha256 -or $receipt.version -cne $pin.inno.version -or
        $receipt.licenseSha256 -cne (Hash (Join-Path $inno 'license.txt'))) { throw 'Procedencia Inno no verificable.' }
    foreach ($file in $receipt.files) {
        if ($file.path -notmatch '^[a-zA-Z0-9_.-]+$' -or (Hash (Join-Path $inno $file.path)) -cne $file.sha256) { throw 'Herramienta Inno alterada.' }
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $instances = @((& $vswhere -products '*' -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json) | ConvertFrom-Json)
    if ($instances.Count -ne 1) { throw 'Se requiere una instalacion inequivoca de VS2022.' }
    $vs = $instances[0].installationPath
    $compiler = Join-Path $vs ('VC/Tools/MSVC/' + $pin.msvc + '/bin/Hostx64/x86/cl.exe')
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'Falta compilador Win32 fijado para el host Inno.' }
    $build = Join-Path $taskRoot ('.tools/installer-bridge-' + $commit.Substring(0, 12))
    & $CMake -S packaging/windows/installer -B $build -G 'Visual Studio 17 2022' -A Win32 -T ('v143,version=' + $pin.msvc) ('-DCMAKE_SYSTEM_VERSION=' + $pin.windowsSdk) ('-DCMAKE_GENERATOR_INSTANCE=' + $vs)
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo configurar el adaptador /MT.' }
    & $CMake --build $build --config Release
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar el adaptador.' }
    $ctest = Join-Path (Split-Path (Get-Command $CMake).Source -Parent) 'ctest.exe'
    & $ctest --test-dir $build -C Release --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas del adaptador.' }
    $bridge = Join-Path $build 'Release/autofinance_setup_bridge.dll'
    $output = Join-Path $taskRoot ($contract.privateOutputDirectory + '/installer-' + $candidate.applicationVersion + '-' + $commit.Substring(0, 12))
    & node scripts/windows-installer.mjs prepare $payload $payloadManifest $bridge $output $commit
    if ($LASTEXITCODE -ne 0) { throw 'Entrada Inno rechazada.' }
    & $iscc ('/DPackageInclude=' + (Join-Path $output 'package.iss.inc')) packaging/windows/autofinance.iss
    if ($LASTEXITCODE -ne 0) { throw 'Compilacion Inno fallida; no distribuir.' }
    & node scripts/windows-payload.mjs verify $payload $payloadManifest
    if ($LASTEXITCODE -ne 0) { throw 'El payload cambio al compilar el instalador.' }
    $finalStatus = @(& git status --porcelain --untracked-files=all)
    if ($finalStatus.Count -ne 0 -or (& git rev-parse HEAD).Trim() -cne $commit) { throw 'El checkout cambio; instalador no verificado.' }
    $exe = Join-Path $output ('Autofinance-' + $candidate.applicationVersion + '-windows-x64-private.exe')
    $observedSigning = (Get-AuthenticodeSignature -LiteralPath $exe).Status.ToString()
    $result = [ordered]@{
        installerBuildVersion = 1; sourceCommit = $commit; sourceDirty = $false
        applicationVersion = $candidate.applicationVersion; windowsVersion = $candidate.windowsVersion
        appId = $contract.appId; builtAtUtc = [DateTime]::UtcNow.ToString('o')
        installer = @{ path = [IO.Path]::GetFileName($exe); size = (Get-Item -LiteralPath $exe).Length; sha256 = (Hash $exe); signing = $observedSigning }
        bridge = @{ architecture = 'x86-inprocess-host-for-inno6'; runtime = 'static'; sha256 = (Hash $bridge); compilerSha256 = (Hash $compiler); signing = (Get-AuthenticodeSignature -LiteralPath $bridge).Status.ToString() }
        inputs = @{ payloadManifestSha256 = (Hash $payloadManifest); ownershipManifestSha256 = (Hash (Join-Path $output '.autofinance-files')) }
        verification = @{ status = 'candidate'; cleanWindowsInstall = 'pending'; finalManifest = 'T06 pending'; e2e = 'T08 pending' }
    }
    [IO.File]::WriteAllText((Join-Path $output 'installer-build.json'), (($result | ConvertTo-Json -Depth 10) + "`n"), (New-Object Text.UTF8Encoding($false)))
    Write-Output 'EXE candidato privado generado. No publicar. El SHA256 no acredita autoria/confianza; faltan manifiesto final T06 y aceptacion T08.'
}
finally { Pop-Location }
