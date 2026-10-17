param(
    [Parameter(Mandatory = $true)][string]$InstallerPath
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pin = (Get-Content (Join-Path $taskRoot 'packaging/windows/payload-toolchain.json') -Raw | ConvertFrom-Json).inno
$installer = (Resolve-Path -LiteralPath $InstallerPath).Path
if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant() -cne $pin.sha256) {
    throw 'Instalador Inno distinto del SHA256 fijado. No se ejecuta.'
}
$destination = Join-Path $taskRoot ('.tools/inno-' + $pin.version)
# Obtencion manual de URL fija; no ejecutar una descarga flotante ni instalar globalmente.
$process = Start-Process -FilePath $installer -ArgumentList @('/CURRENTUSER', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/DIR="' + $destination + '"')) -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0) { throw 'No se pudo preparar Inno por usuario.' }
$compiler = Join-Path $destination 'ISCC.exe'
# ISCC/ISCmplr do not carry meaningful VERSIONINFO; ask the compiler's VER.
& $compiler /O- (Join-Path $taskRoot 'packaging/windows/compiler-version.iss')
if ($LASTEXITCODE -ne 0) { throw 'Version ISCC incorrecta o compilador no operativo.' }
Copy-Item -LiteralPath $installer -Destination (Join-Path $destination 'verified-installer.exe')
$receipt = @{
    version = $pin.version; source = $pin.url; installerSha256 = $pin.sha256
    files = @(Get-ChildItem -LiteralPath $destination -File | Where-Object { $_.Name -notin @('provenance.json', 'verified-installer.exe') } | ForEach-Object {
        @{ path = $_.Name; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    licenseSha256 = (Get-FileHash -LiteralPath (Join-Path $destination 'license.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
} | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $destination 'provenance.json'), $receipt, (New-Object Text.UTF8Encoding($false)))
Write-Output ('Inno verificado; compilador local: .tools/inno-' + $pin.version + '/ISCC.exe')
