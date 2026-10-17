param(
    [Parameter(Mandatory = $true)][string]$RuntimeCrtDirectory,
    [Parameter(Mandatory = $true)][string]$VisualStudioLicensePath,
    [Parameter(Mandatory = $true)][string]$InnoDirectory
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pin = Get-Content (Join-Path $taskRoot 'packaging/windows/payload-toolchain.json') -Raw | ConvertFrom-Json
$contract = Get-Content (Join-Path $taskRoot 'packaging/windows/installation-contract.json') -Raw | ConvertFrom-Json
function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function NumericVersion([string]$Path) {
    $v = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    return ('{0}.{1}.{2}.{3}' -f $v.FileMajorPart, $v.FileMinorPart, $v.FileBuildPart, $v.FilePrivatePart)
}
function Inside([string]$Path, [string]$Parent) {
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Origen fuera del directorio oficial autorizado.' }
    $item = Get-Item -LiteralPath $full
    while ($item -and $item.FullName.Length -ge $root.TrimEnd('\').Length) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'No se admiten enlaces en los origenes.' }
        if ($item.PSIsContainer) { $item = $item.Parent } else { $item = $item.Directory }
        if (-not $item) { break }
    }
    return $full
}
Push-Location $taskRoot
$oldPayloadMode = $env:AUTOFINANCE_PRODUCTION_PAYLOAD
$oldGeneratorToolset = $env:CMAKE_GENERATOR_TOOLSET
try {
    & flutter --version
    if ($LASTEXITCODE -ne 0) { throw 'Flutter no disponible.' }
    & "$PSScriptRoot/check-toolchain.ps1"
    & "$PSScriptRoot/check-windows-installation-contract.ps1"
    $sourceStatus = @(& git status --porcelain --untracked-files=all)
    if ($LASTEXITCODE -ne 0 -or $sourceStatus.Count -ne 0) { throw 'Entrega bloqueada: checkout sucio. Usar checkout limpio del commit propio; no incluir trabajo concurrente.' }
    $commit = (& git rev-parse HEAD).Trim()
    if ($commit -notmatch '^[0-9a-f]{40}$') { throw 'Commit no verificable.' }
    & node scripts/check-google-oauth.mjs --require-configured
    if ($LASTEXITCODE -ne 0) { throw 'Produccion bloqueada: configuracion publica OAuth incompleta.' }
    $oauth = Get-Content config/google-oauth.public.json -Raw | ConvertFrom-Json
    if ($oauth.drive.scopes.Count -ne 1 -or $oauth.drive.scopes[0] -cne 'https://www.googleapis.com/auth/drive.file') {
        throw 'Scopes OAuth distintos del contrato existente.'
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $instances = @((& $vswhere -products '*' -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json) | ConvertFrom-Json)
    if ($instances.Count -ne 1) { throw 'Se requiere una instalacion inequivoca de Visual Studio 2022 con C++.' }
    $vs = $instances[0].installationPath
    $compiler = Join-Path $vs ('VC/Tools/MSVC/' + $pin.msvc + '/bin/Hostx64/x64/cl.exe')
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'Falta MSVC fijado; no se sustituye por Insiders/latest.' }
    $runtime = Inside (Resolve-Path -LiteralPath $RuntimeCrtDirectory).Path (Join-Path $vs 'VC/Redist/MSVC')
    if ($runtime -notmatch ('\\x64\\' + [regex]::Escape($pin.runtimeDirectory) + '$')) { throw 'El runtime debe proceder de CRT x64 redistribuible oficial.' }
    $license = Inside (Resolve-Path -LiteralPath $VisualStudioLicensePath).Path $vs
    if ((Get-Item -LiteralPath $license).Length -eq 0) { throw 'Licencia Visual Studio vacia.' }
    $runtimeFiles = @(Get-ChildItem -LiteralPath $runtime -File)
    if (Compare-Object @($pin.runtimeFiles | Sort-Object) @($runtimeFiles.Name | Sort-Object)) { throw 'Inventario del CRT distinto del fijado.' }
    foreach ($file in $runtimeFiles) {
        if ((NumericVersion $file.FullName) -cne $pin.runtimeFileVersion) { throw 'Version de runtime distinta de la fijada.' }
        $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation,') { throw 'Runtime sin firma Microsoft valida.' }
    }
    $inno = (Resolve-Path -LiteralPath $InnoDirectory).Path
    $iscc = Join-Path $inno 'ISCC.exe'
    & $iscc /O- packaging/windows/compiler-version.iss
    if ($LASTEXITCODE -ne 0) { throw 'Version Inno incorrecta o compilador no operativo.' }
    if ((Hash (Join-Path $inno 'verified-installer.exe')) -cne $pin.inno.sha256) { throw 'Falta procedencia Inno verificada por prepare-inno-setup.ps1.' }
    if (-not (Test-Path (Join-Path $inno 'license.txt') -PathType Leaf)) { throw 'Falta licencia Inno.' }
    $innoReceipt = Get-Content (Join-Path $inno 'provenance.json') -Raw | ConvertFrom-Json
    if ($innoReceipt.installerSha256 -cne $pin.inno.sha256 -or $innoReceipt.version -cne $pin.inno.version -or
        $innoReceipt.licenseSha256 -cne (Hash (Join-Path $inno 'license.txt'))) { throw 'Procedencia/licencia Inno no valida.' }
    foreach ($file in $innoReceipt.files) {
        if ($file.path -notmatch '^[a-zA-Z0-9_.-]+$' -or (Hash (Join-Path $inno $file.path)) -cne $file.sha256) { throw 'Contenido Inno alterado desde su preparacion.' }
    }
    # A fresh build tree prevents stale test assets, plugins or user files entering the payload.
    # Do not delete a shared build: stop and let the operator choose a clean checkout.
    $flutterSettingsRaw = & flutter config --machine
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar la configuracion Flutter.' }
    $flutterSettings = ($flutterSettingsRaw -join "`n") | ConvertFrom-Json
    $buildRelative = $flutterSettings.'build-dir'
    if (-not $buildRelative) { $buildRelative = 'build' }
    # The pinned Windows template sets PROJECT_BUILD_DIR/AOT_LIBRARY to build/.
    # A custom Flutter build-dir can silently install stale assets from build/.
    if ($buildRelative -cne 'build') { throw 'Payload exige build-dir=build en Flutter; no se cambia la configuracion global automaticamente.' }
    $buildRoot = [IO.Path]::GetFullPath((Join-Path $taskRoot $buildRelative))
    if (-not $buildRoot.StartsWith($taskRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'build-dir fuera del checkout.' }
    & git check-ignore --quiet -- $buildRelative
    if ($LASTEXITCODE -ne 0) { throw 'build-dir debe estar ignorado por Git.' }
    $windowsBuild = Join-Path $buildRoot 'windows/x64'
    if (Test-Path -LiteralPath $buildRoot) { throw 'build ya existe. Usar checkout limpio sin salidas de pruebas ni compilaciones anteriores.' }
    & flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Resolucion de lockfile fallida.' }
    $versionLine = Select-String -Path pubspec.yaml -Pattern '^version: (\d+)\.(\d+)\.(\d+)\+(\d+)\s*$'
    if ($versionLine.Matches.Count -ne 1) { throw 'Version de aplicacion no admitida.' }
    $parts = @($versionLine.Matches[0].Groups | Select-Object -Skip 1 | ForEach-Object { [int]$_.Value })
    if (@($parts | Where-Object { $_ -gt 65535 }).Count -or $parts[3] -lt 1) { throw 'Version fuera de rango.' }
    $appVersion = '{0}.{1}.{2}+{3}' -f $parts[0],$parts[1],$parts[2],$parts[3]
    $numericVersion = $parts -join '.'
    $output = Join-Path $taskRoot ('dist-private/windows/payload-' + $appVersion + '-' + $commit.Substring(0,12))
    if (Test-Path -LiteralPath $output) { throw 'Salida privada ya existe: no sobrescribir evidencia.' }
    $env:AUTOFINANCE_PRODUCTION_PAYLOAD = '1'
    $env:CMAKE_GENERATOR_TOOLSET = 'version=' + $pin.msvc
    & flutter build windows --release --no-pub --dart-define=APP_ENV=production "--dart-define=GOOGLE_WINDOWS_CLIENT_ID=$($oauth.windows.clientId)"
    if ($LASTEXITCODE -ne 0) { throw 'Build Windows production fallido.' }
    $cache = Get-Content (Join-Path $windowsBuild 'CMakeCache.txt') -Raw
    if ($cache -notmatch ('CMAKE_GENERATOR_TOOLSET:.*=version=' + [regex]::Escape($pin.msvc)) -or
        $cache -notmatch ('CMAKE_SYSTEM_VERSION:.*=' + [regex]::Escape($pin.windowsSdk))) { throw 'CMake no uso toolchain fijada.' }
    $compilerConfig = Get-Content (Join-Path $windowsBuild 'CMakeFiles/*/CMakeCXXCompiler.cmake') -Raw
    if ($compilerConfig -notmatch [regex]::Escape(('/VC/Tools/MSVC/' + $pin.msvc + '/'))) { throw 'Compilador efectivo incorrecto.' }
    $runner = Join-Path $windowsBuild 'runner/Release'
    & "$PSScriptRoot/check-windows-installation-contract.ps1" -ExecutablePath (Join-Path $runner $contract.executable)
    & node scripts/windows-payload.mjs official $runner (Join-Path $windowsBuild 'install_manifest.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Salida Flutter incompleta/no portable. No se empaqueta.' }
    $payload = Join-Path $output 'payload'
    New-Item -ItemType Directory -Path $output | Out-Null
    Copy-Item -LiteralPath $runner -Destination $payload -Recurse
    foreach ($file in $runtimeFiles) {
        $target = Join-Path $payload $file.Name
        if ((Test-Path -LiteralPath $target) -and (Hash $target) -cne (Hash $file.FullName)) { throw 'Colision entre runtime fijado y DLL de la salida oficial Flutter.' }
        Copy-Item -LiteralPath $file.FullName -Destination $payload
    }
    foreach ($file in Get-ChildItem -LiteralPath $payload -Recurse -File | Where-Object { $_.Extension -in @('.dll', '.exe') }) {
        if ([Diagnostics.FileVersionInfo]::GetVersionInfo($file.FullName).IsDebug) { throw 'Binario Debug no admitido.' }
    }
    $licenses = Join-Path $payload 'licenses'
    New-Item -ItemType Directory -Path $licenses | Out-Null
    Copy-Item -LiteralPath $license -Destination (Join-Path $licenses ('visual-studio-terms' + [IO.Path]::GetExtension($license)))
    Copy-Item -LiteralPath (Join-Path $inno 'license.txt') -Destination (Join-Path $licenses 'inno-setup.txt')
    $flutterBin = Split-Path (Get-Command flutter).Source
    Copy-Item -LiteralPath (Join-Path $flutterBin '../LICENSE') -Destination (Join-Path $licenses 'flutter.txt')
    Copy-Item -LiteralPath (Join-Path $flutterBin 'cache/pkg/sky_engine/LICENSE') -Destination (Join-Path $licenses 'flutter-engine-third-parties.txt')
    Copy-Item -LiteralPath assets/fonts/LICENSE-Roboto.txt -Destination (Join-Path $licenses 'roboto.txt')
    Copy-Item -LiteralPath packaging/windows/runtime-notice.txt -Destination $licenses
    & node scripts/windows-payload.mjs inventory $payload (Join-Path $output 'inventory.json')
    if ($LASTEXITCODE -ne 0) { throw 'Payload/dependencias/licencias no valido.' }
    $inventory = Get-Content (Join-Path $output 'inventory.json') -Raw | ConvertFrom-Json
    $finalStatus = @(& git status --porcelain --untracked-files=all)
    if ($finalStatus.Count -ne 0 -or (& git rev-parse HEAD).Trim() -cne $commit) { throw 'El checkout cambio durante el build; candidato rechazado.' }
    $effectiveFlutterRaw = & flutter --version --machine
    if ($LASTEXITCODE -ne 0) { throw 'Version Flutter efectiva no verificable.' }
    $effectiveFlutter = ($effectiveFlutterRaw -join "`n") | ConvertFrom-Json
    $manifest = [ordered]@{
        payloadManifestVersion = 1; installationContractVersion = $contract.contractVersion; appId = $contract.appId
        applicationVersion = $appVersion; windowsVersion = $numericVersion; architecture = 'x64'; appEnvironment = 'production'
        sourceCommit = $commit; sourceDirty = $false; builtAtUtc = [DateTime]::UtcNow.ToString('o')
        toolchain = @{
            flutter = (Get-Content toolchain.json -Raw | ConvertFrom-Json).flutter
            dart = (Get-Content toolchain.json -Raw | ConvertFrom-Json).dart
            flutterRevision = $effectiveFlutter.frameworkRevision; engineRevision = $effectiveFlutter.engineRevision
            msvc = $pin.msvc; compilerFileVersion = (NumericVersion $compiler); windowsSdk = $pin.windowsSdk
            inno = $pin.inno.version; innoCompilerSha256 = (Hash $iscc); innoInstallerSha256 = $pin.inno.sha256
            toolchainSha256 = (Hash 'toolchain.json'); lockfileSha256 = (Hash 'pubspec.lock')
            payloadToolchainSha256 = (Hash 'packaging/windows/payload-toolchain.json')
            compilerSha256 = (Hash $compiler); visualStudio = $instances[0].installationVersion
        }
        oauth = @{ status = $oauth.status; publicConfigSha256 = (Hash 'config/google-oauth.public.json'); scopes = @($oauth.drive.scopes) }
        payload = $inventory.payload; imports = $inventory.imports
        runtime = @{ version = $pin.runtimeFileVersion; source = $pin.runtimeSource; acquisition = $pin.runtimeAcquisition; sourceRelativeToVisualStudio = $runtime.Substring($vs.Length + 1).Replace('\','/'); files = @($inventory.payload | Where-Object { $pin.runtimeFiles -contains $_.path }) }
        licenses = @($inventory.payload | Where-Object { $_.path -like 'licenses/*' -or $_.path -like '*/NOTICES.Z' } | ForEach-Object {
            $component = switch -Wildcard ($_.path) {
                '*visual-studio*' { 'Microsoft Visual Studio / CRT'; break }
                '*runtime-notice*' { 'Microsoft Visual C++ app-local CRT'; break }
                '*inno*' { 'Inno Setup'; break }
                '*roboto*' { 'Roboto'; break }
                '*engine*' { 'Flutter engine and third parties'; break }
                '*NOTICES.Z' { 'Flutter package license registry'; break }
                default { 'Flutter' }
            }
            @{ path = $_.path; size = $_.size; sha256 = $_.sha256; component = $component }
        })
        signing = @{ installer = 'notBuilt'; binaries = @($inventory.payload | Where-Object { $_.path -match '\.(exe|dll)$' } | ForEach-Object { @{ path = $_.path; status = (Get-AuthenticodeSignature -LiteralPath (Join-Path $payload $_.path)).Status.ToString() } }) }
        verification = @{ status = 'candidate'; officialFlutterOutput = $true; cleanWindowsLaunch = 'pending'; osVersion = [Environment]::OSVersion.Version.ToString(); limitations = @('T05/T06 installer not built', 'T08 clean standard-user offline startup pending; PE imports do not prove dynamic loading') }
    }
    $json = $manifest | ConvertTo-Json -Depth 14
    [IO.File]::WriteAllText((Join-Path $output 'payload-manifest.json'), $json + "`n", (New-Object Text.UTF8Encoding($false)))
    & node scripts/windows-payload.mjs verify $payload (Join-Path $output 'payload-manifest.json')
    if ($LASTEXITCODE -ne 0) { throw 'Manifiesto de payload no valido.' }
    Write-Output 'Candidato privado preparado. No es instalador ni acredita arranque Windows limpio; ver T05/T06/T08.'
}
finally {
    $env:AUTOFINANCE_PRODUCTION_PAYLOAD = $oldPayloadMode
    $env:CMAKE_GENERATOR_TOOLSET = $oldGeneratorToolset
    Pop-Location
}
