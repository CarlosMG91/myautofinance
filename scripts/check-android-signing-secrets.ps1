param(
    [Parameter(Mandatory = $true)][string] $Apk,
    [string] $MaterialDirectory = (Join-Path $env:LOCALAPPDATA 'MyAutofinance/android-signing')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-signing-private.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$material = Read-SigningMaterial $MaterialDirectory
$secrets = @($material.alias, $material.password, (Join-Path $MaterialDirectory 'distribution.p12'))
$zip = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Apk))
$count = 0
try {
    foreach ($entry in $zip.Entries) {
        if ($entry.FullName -match '(?i)(\.(p12|pfx|jks|keystore|dpapi)$|(^|/)key\.properties$)') { throw 'APK-SIGNING[SECRET_IN_APK]: Archivo privado en el APK.' }
        $stream = $entry.Open()
        $memory = New-Object IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            $bytes = $memory.ToArray()
            foreach ($encoding in @([Text.Encoding]::UTF8, [Text.Encoding]::Unicode)) {
                $content = $encoding.GetString($bytes)
                foreach ($secret in $secrets) {
                    if ($content.Contains($secret)) { throw 'APK-SIGNING[SECRET_IN_APK]: Material privado encontrado en el APK.' }
                }
            }
            $count++
        } finally { $stream.Dispose(); $memory.Dispose() }
    }
} finally { $zip.Dispose() }
Write-Output "APK verificado: $count entradas descomprimidas sin material de firma conocido."
