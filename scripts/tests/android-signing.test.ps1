param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../android-signing-private.ps1')
function Assert-SigningTest([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw "Signing test failed: $Message" }
}
$key = Get-SigningRandom 64
$payload = [Text.Encoding]::UTF8.GetBytes('synthetic backup with no real credentials')
$encrypted = Protect-SigningBackup $payload $key
$decrypted = Unprotect-SigningBackup $encrypted $key
Assert-SigningTest ([Convert]::ToBase64String($decrypted) -eq [Convert]::ToBase64String($payload)) 'portable authenticated round trip'
$wrong = Get-SigningRandom 64
$rejected = $false
try { $null = Unprotect-SigningBackup $encrypted $wrong } catch { $rejected = $_.Exception.Message -match 'INVALID_BACKUP' }
Assert-SigningTest $rejected 'wrong recovery key rejected'
$tampered = [byte[]]$encrypted.Clone(); $tampered[18] = $tampered[18] -bxor 1
$rejected = $false
try { $null = Unprotect-SigningBackup $tampered $key } catch { $rejected = $_.Exception.Message -match 'INVALID_BACKUP' }
Assert-SigningTest $rejected 'modified backup rejected before decryption'
foreach ($path in @($script:SigningRepo, (Join-Path $script:SigningRepo 'signing-private'), 'relative.p12', [IO.Path]::GetPathRoot($script:SigningRepo))) {
    $rejected = $false
    try { $null = Assert-PrivateSigningPath $path } catch { $rejected = $_.Exception.Message -match 'INVALID_LOCATION' }
    Assert-SigningTest $rejected 'repo and relative paths rejected'
}
$temporary = New-PrivateSigningDirectory (Join-Path ([IO.Path]::GetTempPath()) ('autofinance-signing-test-' + [Guid]::NewGuid().ToString('N')))
try {
    $synthetic = [pscustomobject]@{ password = [Convert]::ToBase64String((Get-SigningRandom 32)); alias = 'synthetic-only' }
    Write-SigningMaterial $temporary $synthetic
    $roundTrip = Read-SigningMaterial $temporary
    Assert-SigningTest ($roundTrip.password -eq $synthetic.password -and $roundTrip.alias -eq $synthetic.alias) 'DPAPI round trip'
    $onDisk = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes((Join-Path $temporary 'credentials.dpapi')))
    Assert-SigningTest (-not $onDisk.Contains($synthetic.password) -and -not $onDisk.Contains($synthetic.alias)) 'secrets encrypted at rest'
    $acl = Get-Acl -LiteralPath $temporary
    Assert-SigningTest $acl.AreAccessRulesProtected 'directory does not inherit broad permissions'
    [IO.File]::WriteAllText((Join-Path $temporary 'credentials.dpapi'), 'corrupt synthetic fixture')
    $rejected = $false
    try { $null = Read-SigningMaterial $temporary } catch { $rejected = $_.Exception.Message -match 'MISSING_MATERIAL' }
    Assert-SigningTest $rejected 'corrupt material gives typed error'
} finally {
    $checked = Assert-PrivateSigningPath $temporary
    if ([IO.Path]::GetDirectoryName($checked) -ne [IO.Path]::GetTempPath().TrimEnd('\', '/') -or [IO.Path]::GetFileName($checked) -notlike 'autofinance-signing-test-*') { throw 'Unexpected test directory; not deleted.' }
    Remove-Item -LiteralPath $checked -Recurse -Force
}
Write-Output '11 signing custody checks passed (synthetic fixtures only).'
