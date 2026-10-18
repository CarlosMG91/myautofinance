param(
    [string] $MaterialDirectory = (Join-Path $env:LOCALAPPDATA 'MyAutofinance/android-signing'),
    [Parameter(Mandatory = $true)][string] $Jdk,
    [Parameter(Mandatory = $true)][string] $AndroidSdk
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-signing-private.ps1')
Assert-SigningJdk $Jdk
if ($env:CI) { throw 'APK-SIGNING[PRIVATE_ONLY]: El APK técnico de distribución solo se genera localmente.' }
$material = Read-SigningMaterial $MaterialDirectory
$certificate = Get-SigningCertificate $MaterialDirectory $material $Jdk
$publicFile = Join-Path $script:SigningRepo 'packaging/android/distribution-certificate.pem'
$publicCertificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2($publicFile)
if ((Get-SigningDigest $certificate) -ne (Get-SigningDigest $publicCertificate.RawData)) { throw 'APK-SIGNING[CERTIFICATE_MISMATCH]: Material distinto del certificado público.' }
$values = @{
    AUTOFINANCE_SIGNING_STORE_FILE = Join-Path $MaterialDirectory 'distribution.p12'
    AUTOFINANCE_SIGNING_STORE_PASSWORD = $material.password
    AUTOFINANCE_SIGNING_KEY_ALIAS = $material.alias
    AUTOFINANCE_SIGNING_KEY_PASSWORD = $material.password
    AUTOFINANCE_SIGNING_FIXTURE = $null
    GRADLE_OPTS = '-Dorg.gradle.daemon=false -Dorg.gradle.configuration-cache=false -Dorg.gradle.jvmargs=-Xmx4G'
    JAVA_HOME = $Jdk
    APPDATA = Join-Path $script:SigningRepo ('.tools/signing-flutter-config-' + [Guid]::NewGuid().ToString('N'))
}
$previous = @{}
foreach ($name in $values.Keys) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name)
    # Do not expose signing material to dependency resolution/tooling preparation.
    $initial = if ($name.StartsWith('AUTOFINANCE_SIGNING_')) { $null } else { $values[$name] }
    [Environment]::SetEnvironmentVariable($name, $initial)
}
Push-Location $script:SigningRepo
try {
    $null = [IO.Directory]::CreateDirectory($env:APPDATA)
    & flutter config --jdk-dir $Jdk --build-dir build
    if ($LASTEXITCODE -ne 0) { throw 'APK-SIGNING[INVALID_JDK]: No se pudo aislar la configuración Flutter/JDK.' }
    $lockBefore = (Get-FileHash -LiteralPath 'pubspec.lock' -Algorithm SHA256).Hash
    $ErrorActionPreference = 'Continue'
    & flutter pub get --enforce-lockfile
    $pubExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($pubExit -ne 0) { throw 'APK-SIGNING[DEPENDENCIES]: No se pudieron resolver las dependencias fijadas.' }
    # Flutter 3.47 --no-pub skips release plugin regeneration. Generate release
    # tooling first (no Gradle build/key), then compile with --no-pub as contracted.
    $ErrorActionPreference = 'Continue'
    & flutter build apk --release --config-only --dart-define=APP_ENV=production
    $configExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ((Get-FileHash -LiteralPath 'pubspec.lock' -Algorithm SHA256).Hash -ne $lockBefore) { throw 'APK-SIGNING[LOCKFILE_CHANGED]: Cambió el lockfile; se detiene sin generar la entrega.' }
    if ($configExit -ne 0) { throw 'APK-SIGNING[CONFIGURATION]: No se pudo preparar el registro de plugins release.' }
    foreach ($name in $values.Keys) {
        if ($name.StartsWith('AUTOFINANCE_SIGNING_')) { [Environment]::SetEnvironmentVariable($name, $values[$name]) }
    }
    # No secret flags, version overrides, installation, upload or final-delivery claim.
    $ErrorActionPreference = 'Continue'
    & flutter build apk --release --no-pub --dart-define=APP_ENV=production
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw 'APK-SIGNING[BUILD_FAILED]: Falló el APK técnico. No es una entrega completa.' }
    $destination = Join-Path $script:SigningRepo 'dist-private/android/signing-check'
    $null = [IO.Directory]::CreateDirectory($destination)
    $apk = Join-Path $destination 'autofinance-technical-signature-check.apk'
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination $apk
    $inspection = & node scripts/check-android-apk-contract.mjs --apk $apk --sdk $AndroidSdk --jdk $Jdk --expected-certificate (Get-SigningDigest $certificate)
    if ($LASTEXITCODE -ne 0) { throw 'APK-SIGNING[VERIFICATION_FAILED]: apksigner/contrato rechazó el APK técnico.' }
    & (Join-Path $PSScriptRoot 'check-android-signing-secrets.ps1') -Apk $apk -MaterialDirectory $MaterialDirectory
    [IO.File]::WriteAllText((Join-Path $destination 'technical-inspection.json'), ($inspection -join "`n"), (New-Object Text.UTF8Encoding($false)))
    Write-Output ($inspection -join "`n")
    Write-Output 'APK técnico de firma, APP_ENV=production. No acredita Drive real ni entrega completa. No se ha instalado.'
} finally {
    Pop-Location
    foreach ($name in $values.Keys) { [Environment]::SetEnvironmentVariable($name, $previous[$name]) }
}
