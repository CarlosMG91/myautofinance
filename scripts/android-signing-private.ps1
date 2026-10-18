# Windows private signing primitives. Never write secret values to the pipeline.
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Security
$script:SigningRepo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Assert-SigningJdk([string] $Jdk) {
    if (-not (Test-Path -LiteralPath (Join-Path $Jdk 'release')) -or -not ((Get-Content -LiteralPath (Join-Path $Jdk 'release') -Raw) -match 'JAVA_VERSION="17\.')) {
        throw 'APK-SIGNING[INVALID_JDK]: Se requiere el JDK 17 fijado, sin actualizar SDK.'
    }
}

function Assert-PrivateSigningPath([string] $Path) {
    if (-not [IO.Path]::IsPathRooted($Path)) { throw 'APK-SIGNING[INVALID_LOCATION]: Se requiere ruta absoluta privada.' }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $protectedRoots = @([IO.Path]::GetPathRoot($full), $env:USERPROFILE, $env:LOCALAPPDATA, $env:APPDATA, [IO.Path]::GetTempPath())
    foreach ($protectedRoot in $protectedRoots) {
        if ($protectedRoot -and $full.Equals($protectedRoot.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'APK-SIGNING[INVALID_LOCATION]: Elegir una subcarpeta privada específica, no una raíz de usuario o sistema.'
        }
    }
    if ($full.Equals($script:SigningRepo, [StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($script:SigningRepo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'APK-SIGNING[INVALID_LOCATION]: El material privado debe estar fuera del repositorio.'
    }
    $cursor = $full
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'APK-SIGNING[INVALID_LOCATION]: No se admiten enlaces o redirecciones en la ruta privada.'
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}

function New-PrivateSigningDirectory([string] $Path) {
    $full = Assert-PrivateSigningPath $Path
    $null = [IO.Directory]::CreateDirectory($full)
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl.SetOwner($sid)
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $full -AclObject $acl
    return $full
}

function Get-SigningRandom([int] $Count) {
    $bytes = New-Object byte[] $Count
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ,$bytes
}

function Write-SigningMaterial([string] $Directory, $Material) {
    $payload = [Text.Encoding]::UTF8.GetBytes(($Material | ConvertTo-Json -Compress))
    $encrypted = [Security.Cryptography.ProtectedData]::Protect($payload, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    [IO.File]::WriteAllBytes((Join-Path $Directory 'credentials.dpapi'), $encrypted)
    [Array]::Clear($payload, 0, $payload.Length)
}

function Read-SigningMaterial([string] $Directory) {
    $null = Assert-PrivateSigningPath $Directory
    $payload = $null
    try {
        $payload = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes((Join-Path $Directory 'credentials.dpapi')), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        return ([Text.Encoding]::UTF8.GetString($payload) | ConvertFrom-Json)
    } catch { throw 'APK-SIGNING[MISSING_MATERIAL]: Material ausente, dañado o de otro usuario Windows; recuperar respaldo, no regenerar clave.' }
    finally { if ($payload) { [Array]::Clear($payload, 0, $payload.Length) } }
}

function Invoke-SigningKeytool([string] $Jdk, [string[]] $Arguments, [string] $Password) {
    # Password is inherited by the child, never passed as a command-line value.
    $previous = $env:AUTOFINANCE_KEYTOOL_PASSWORD
    try {
        $env:AUTOFINANCE_KEYTOOL_PASSWORD = $Password
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $result = & (Join-Path $Jdk 'bin/keytool.exe') @Arguments 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = $oldPreference
        if ($code -ne 0) { throw 'APK-SIGNING[KEYTOOL_FAILED]: No se pudo comprobar o crear el material privado. No se imprime la salida sensible.' }
    } finally { $env:AUTOFINANCE_KEYTOOL_PASSWORD = $previous; $ErrorActionPreference = 'Stop' }
}

function Get-SigningCertificate([string] $Directory, $Material, [string] $Jdk) {
    $output = Join-Path $Directory ('certificate-' + [Guid]::NewGuid().ToString('N') + '.der')
    $request = $output + '.csr'
    try {
        $common = @('-keystore', (Join-Path $Directory 'distribution.p12'), '-storetype', 'PKCS12', '-storepass:env', 'AUTOFINANCE_KEYTOOL_PASSWORD', '-alias', $Material.alias)
        Invoke-SigningKeytool $Jdk (@('-exportcert', '-file', $output) + $common) $Material.password
        # A CSR proves recovery of the usable private key, not just the public certificate.
        Invoke-SigningKeytool $Jdk (@('-certreq', '-file', $request) + $common) $Material.password
        return ,([IO.File]::ReadAllBytes($output))
    } finally {
        foreach ($file in @($output, $request)) { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file } }
    }
}

function Get-SigningDigest([byte[]] $Bytes, [string] $Algorithm = 'SHA256') {
    $hash = [Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    try { return ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hash.Dispose() }
}

function Protect-SigningBackup([byte[]] $Payload, [byte[]] $Key) {
    $aes = [Security.Cryptography.Aes]::Create()
    $hmac = New-Object Security.Cryptography.HMACSHA256
    try {
        $aes.Key = [byte[]]$Key[0..31]; $aes.GenerateIV()
        $cipher = $aes.CreateEncryptor().TransformFinalBlock($Payload, 0, $Payload.Length)
        $body = [byte[]](@(1) + $aes.IV + $cipher)
        $hmac.Key = [byte[]]$Key[32..63]
        return ,([byte[]]($body + $hmac.ComputeHash($body)))
    } finally { $aes.Dispose(); $hmac.Dispose() }
}

function Unprotect-SigningBackup([byte[]] $Encrypted, [byte[]] $Key) {
    if ($Key.Length -ne 64 -or $Encrypted.Length -lt 65 -or $Encrypted[0] -ne 1) { throw 'APK-SIGNING[INVALID_BACKUP]: Formato de respaldo inválido.' }
    $hmac = New-Object Security.Cryptography.HMACSHA256
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $body = [byte[]]$Encrypted[0..($Encrypted.Length - 33)]
        $hmac.Key = [byte[]]$Key[32..63]
        $mac = $hmac.ComputeHash($body)
        $difference = 0
        for ($i = 0; $i -lt 32; $i++) { $difference = $difference -bor ($mac[$i] -bxor $Encrypted[$Encrypted.Length - 32 + $i]) }
        if ($difference -ne 0) { throw 'APK-SIGNING[INVALID_BACKUP]: Respaldo alterado o llave de recuperación incorrecta.' }
        $aes.Key = [byte[]]$Key[0..31]; $aes.IV = [byte[]]$body[1..16]
        return ,$aes.CreateDecryptor().TransformFinalBlock($body, 17, $body.Length - 17)
    } finally { $hmac.Dispose(); $aes.Dispose() }
}
