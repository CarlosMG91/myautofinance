param(
    [Parameter(Mandatory = $true)][string] $Jdk,
    [Parameter(Mandatory = $true)][string] $AndroidSdk,
    [string] $MaterialDirectory = '',
    [switch] $Fixture
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$previous = @{}
$names = @('JAVA_HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'APPDATA', 'XDG_CONFIG_HOME', 'GRADLE_OPTS',
    'AUTOFINANCE_SIGNING_STORE_FILE', 'AUTOFINANCE_SIGNING_STORE_PASSWORD', 'AUTOFINANCE_SIGNING_KEY_ALIAS',
    'AUTOFINANCE_SIGNING_KEY_PASSWORD', 'AUTOFINANCE_SIGNING_FIXTURE', 'AUTOFINANCE_SIGNING_FIXTURE_SHA256')
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name) }
$work = Join-Path $repo ('.tools/android-delivery-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($work)
Push-Location $repo
try {
    $fixtureArgs = @()
    if ($Fixture) { $fixtureArgs = @('--fixture') }
    # OAuth rejects missing T03 before any release build or reading private key material.
    $planText = & node scripts/android-delivery.mjs --plan @fixtureArgs
    if ($LASTEXITCODE -ne 0) { throw 'APK-DELIVERY[CONFIGURATION]: configuración Android no válida; no hay entrega completa.' }
    $plan = ($planText -join "`n") | ConvertFrom-Json
    $snapshot = Join-Path $work 'inputs.json'
    [IO.File]::WriteAllText($snapshot, ($planText -join "`n"), (New-Object Text.UTF8Encoding($false)))
    $toolchain = $plan.inputs.toolchain
    if (-not ((Get-Content (Join-Path $Jdk 'release') -Raw) -match 'JAVA_VERSION="17\.')) { throw 'Se requiere JDK 17.' }
    foreach ($package in @("platforms/android-$($toolchain.androidPlatform)", "build-tools/$($toolchain.androidBuildTools)", "ndk/$($toolchain.androidNdk)")) {
        if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdk $package))) { throw "Falta paquete Android fijado: $package" }
    }
    $env:JAVA_HOME = $Jdk
    $env:ANDROID_HOME = $AndroidSdk
    $env:ANDROID_SDK_ROOT = $AndroidSdk
    $env:APPDATA = Join-Path $work 'config'
    $env:XDG_CONFIG_HOME = Join-Path $work 'config'
    $env:GRADLE_OPTS = '-Dorg.gradle.daemon=false -Dorg.gradle.configuration-cache=false -Dorg.gradle.jvmargs=-Xmx4G'
    foreach ($name in $names) { if ($name.StartsWith('AUTOFINANCE_SIGNING_')) { [Environment]::SetEnvironmentVariable($name, $null) } }
    & flutter --version
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo inicializar Flutter.' }
    & ./scripts/check-toolchain.ps1
    & flutter config --jdk-dir $Jdk --android-sdk $AndroidSdk --build-dir build
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo configurar Flutter.' }
    & flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Falló resolución del lockfile.' }
    if ((Get-FileHash pubspec.lock -Algorithm SHA256).Hash.ToLowerInvariant() -ne $plan.inputs.lockfileSha256) { throw 'LOCKFILE_CHANGED: regenerar sin cambiar dependencias.' }
    $defines = @("--dart-define=APP_ENV=$($plan.appEnvironment)")
    if (-not $Fixture) { $defines += "--dart-define=GOOGLE_ANDROID_SERVER_CLIENT_ID=$($plan.serverClientId)" }
    # Flutter 3.47 needs config-only to regenerate release plugin tooling before --no-pub.
    & flutter build apk --release --config-only @defines
    if ($LASTEXITCODE -ne 0) { throw 'Falló preparación release.' }
    if ($Fixture) {
        foreach ($name in $names) { if ($name.StartsWith('AUTOFINANCE_SIGNING_')) { [Environment]::SetEnvironmentVariable($name, $previous[$name]) } }
    } else {
        if (-not $MaterialDirectory) { $MaterialDirectory = Join-Path $env:LOCALAPPDATA 'MyAutofinance/android-signing' }
        . (Join-Path $PSScriptRoot 'android-signing-private.ps1')
        $material = Read-SigningMaterial $MaterialDirectory
        $cert = Get-SigningCertificate $MaterialDirectory $material $Jdk
        if ((Get-SigningDigest $cert) -ne $plan.expectedCertificate) { throw 'CERTIFICATE_MISMATCH: material distinto de T02.' }
        $env:AUTOFINANCE_SIGNING_STORE_FILE = Join-Path $MaterialDirectory 'distribution.p12'
        $env:AUTOFINANCE_SIGNING_STORE_PASSWORD = $material.password
        $env:AUTOFINANCE_SIGNING_KEY_ALIAS = $material.alias
        $env:AUTOFINANCE_SIGNING_KEY_PASSWORD = $material.password
    }
    & flutter build apk --release --no-pub @defines
    if ($LASTEXITCODE -ne 0) { throw 'Falló compilación APK; no hay candidato validado.' }
    # Remove secrets before inspection; fixture identity remains for the independent verifier.
    foreach ($name in @('STORE_FILE', 'STORE_PASSWORD', 'KEY_ALIAS', 'KEY_PASSWORD')) { [Environment]::SetEnvironmentVariable("AUTOFINANCE_SIGNING_$name", $null) }
    $apk = Join-Path $repo 'build/app/outputs/flutter-apk/app-release.apk'
    if (-not $Fixture) {
        & ./scripts/check-android-signing-secrets.ps1 -Apk $apk -MaterialDirectory $MaterialDirectory
    }
    & node scripts/android-delivery.mjs --apk $apk --sdk $AndroidSdk --jdk $Jdk --snapshot $snapshot @fixtureArgs
    if ($LASTEXITCODE -ne 0) { throw 'APK-DELIVERY[VERIFICATION]: APK rechazado; no hay entrega validada.' }
} finally {
    Pop-Location
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name]) }
}
