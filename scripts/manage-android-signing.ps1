param(
    [ValidateSet('Create', 'Check', 'Recover')][string] $Action = 'Check',
    [string] $MaterialDirectory = (Join-Path $env:LOCALAPPDATA 'MyAutofinance/android-signing'),
    [string] $BackupDirectory = (Join-Path $env:USERPROFILE 'MyAutofinance-private-backup/android-signing'),
    [string] $RecoveryKeyFile = (Join-Path $env:USERPROFILE 'MyAutofinance-private-recovery/android-signing-recovery.key'),
    [Parameter(Mandatory = $true)][string] $Jdk
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-signing-private.ps1')
Assert-SigningJdk $Jdk
if ($env:CI) { throw 'APK-SIGNING[PRIVATE_ONLY]: La custodia se ejecuta localmente, nunca en CI.' }
$MaterialDirectory = Assert-PrivateSigningPath $MaterialDirectory
$BackupDirectory = Assert-PrivateSigningPath $BackupDirectory
$RecoveryKeyFile = Assert-PrivateSigningPath $RecoveryKeyFile
$backupFile = Join-Path $BackupDirectory 'android.signing-backup'
$publicFile = Join-Path $script:SigningRepo 'packaging/android/distribution-certificate.pem'
$recoveryTest = $null
$key = $null
try {
    if ($Action -eq 'Create') {
        # Never overwrite partial material or silently replace an existing identity.
        if ((Test-Path -LiteralPath $MaterialDirectory) -or (Test-Path -LiteralPath $backupFile) -or (Test-Path -LiteralPath $RecoveryKeyFile) -or (Test-Path -LiteralPath $publicFile) -or (Test-Path -LiteralPath (Join-Path $script:SigningRepo 'android/key.properties'))) {
            throw 'APK-SIGNING[ALREADY_EXISTS]: Existe material o identidad previa. Comprobar o recuperar; no crear otra clave.'
        }
        $null = New-PrivateSigningDirectory $MaterialDirectory
        $null = New-PrivateSigningDirectory $BackupDirectory
        $null = New-PrivateSigningDirectory ([IO.Path]::GetDirectoryName($RecoveryKeyFile))
        $material = [pscustomobject]@{
            alias = ('key-' + [Guid]::NewGuid().ToString('N'))
            password = [Convert]::ToBase64String((Get-SigningRandom 48))
        }
        Write-SigningMaterial $MaterialDirectory $material
        Invoke-SigningKeytool $Jdk @('-genkeypair', '-noprompt', '-keystore', (Join-Path $MaterialDirectory 'distribution.p12'), '-storetype', 'PKCS12', '-alias', $material.alias, '-storepass:env', 'AUTOFINANCE_KEYTOOL_PASSWORD', '-keypass:env', 'AUTOFINANCE_KEYTOOL_PASSWORD', '-keyalg', 'RSA', '-keysize', '4096', '-sigalg', 'SHA256withRSA', '-validity', '36500', '-dname', 'CN=Autofinance Private Distribution') $material.password
        $certificate = Get-SigningCertificate $MaterialDirectory $material $Jdk
        $material | Add-Member -NotePropertyName certificateSha256 -NotePropertyValue (Get-SigningDigest $certificate)
        Write-SigningMaterial $MaterialDirectory $material
        $key = Get-SigningRandom 64
        [IO.File]::WriteAllText($RecoveryKeyFile, [Convert]::ToBase64String($key))
        $payload = [Text.Encoding]::UTF8.GetBytes((@{
            material = $material
            keystore = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $MaterialDirectory 'distribution.p12')))
        } | ConvertTo-Json -Compress))
        [IO.File]::WriteAllBytes($backupFile, (Protect-SigningBackup $payload $key))
        [Array]::Clear($payload, 0, $payload.Length)
    }
    if ($Action -eq 'Recover') {
        if (Test-Path -LiteralPath $MaterialDirectory) { throw 'APK-SIGNING[ALREADY_EXISTS]: Recuperar solo en un destino nuevo; no reemplazar originales.' }
    } else {
        $material = Read-SigningMaterial $MaterialDirectory
        $certificate = Get-SigningCertificate $MaterialDirectory $material $Jdk
        if ((Get-SigningDigest $certificate) -ne $material.certificateSha256) { throw 'APK-SIGNING[CERTIFICATE_MISMATCH]: Identidad local alterada.' }
    }
    # Always restore the protected backup into a fresh private directory and use its key.
    $key = [Convert]::FromBase64String([IO.File]::ReadAllText($RecoveryKeyFile))
    $payload = Unprotect-SigningBackup ([IO.File]::ReadAllBytes($backupFile)) $key
    $restored = [Text.Encoding]::UTF8.GetString($payload) | ConvertFrom-Json
    [Array]::Clear($payload, 0, $payload.Length)
    $recoveryTest = New-PrivateSigningDirectory (Join-Path ([IO.Path]::GetTempPath()) ('autofinance-signing-' + [Guid]::NewGuid().ToString('N')))
    [IO.File]::WriteAllBytes((Join-Path $recoveryTest 'distribution.p12'), [Convert]::FromBase64String($restored.keystore))
    $recoveredCertificate = Get-SigningCertificate $recoveryTest $restored.material $Jdk
    $sha256 = Get-SigningDigest $recoveredCertificate
    if ($sha256 -ne $restored.material.certificateSha256 -or ($Action -ne 'Recover' -and $sha256 -ne (Get-SigningDigest $certificate))) {
        throw 'APK-SIGNING[CERTIFICATE_MISMATCH]: Recuperación distinta del certificado original.'
    }
    if (Test-Path -LiteralPath $publicFile) {
        $x509 = New-Object Security.Cryptography.X509Certificates.X509Certificate2($publicFile)
        if ((Get-SigningDigest $x509.RawData) -ne $sha256) { throw 'APK-SIGNING[CERTIFICATE_MISMATCH]: Identidad distinta del certificado público fijado.' }
    } elseif ($Action -ne 'Create') {
        throw 'APK-SIGNING[MISSING_CERTIFICATE]: Falta identidad pública independiente. No adoptar una nueva silenciosamente.'
    }
    if ($Action -eq 'Create') {
        $pem = "-----BEGIN CERTIFICATE-----`n" + [Convert]::ToBase64String($certificate, [Base64FormattingOptions]::InsertLineBreaks).Replace("`r", '') + "`n-----END CERTIFICATE-----`n"
        [IO.File]::WriteAllText($publicFile, $pem, (New-Object Text.UTF8Encoding($false)))
    }
    if ($Action -eq 'Recover') {
        $null = New-PrivateSigningDirectory $MaterialDirectory
        Copy-Item -LiteralPath (Join-Path $recoveryTest 'distribution.p12') -Destination (Join-Path $MaterialDirectory 'distribution.p12')
        Write-SigningMaterial $MaterialDirectory $restored.material
    }
    [pscustomobject]@{
        purpose = 'signing-custody-only'; completeDelivery = $false
        certificateSha1 = Get-SigningDigest $recoveredCertificate 'SHA1'
        certificateSha256 = $sha256
        recoveryVerified = $true; privateKeyOperationVerified = $true
    } | ConvertTo-Json
} finally {
    if ($recoveryTest -and (Test-Path -LiteralPath $recoveryTest)) {
        # Verified absolute directory created above, outside the repo, with fixed prefix.
        $checked = Assert-PrivateSigningPath $recoveryTest
        if ([IO.Path]::GetDirectoryName($checked) -ne [IO.Path]::GetTempPath().TrimEnd('\', '/') -or [IO.Path]::GetFileName($checked) -notlike 'autofinance-signing-*') { throw 'APK-SIGNING[INVALID_LOCATION]: Temporal inesperado; no se borra.' }
        Remove-Item -LiteralPath $checked -Recurse -Force
    }
    if ($key) { [Array]::Clear($key, 0, $key.Length) }
}
