param(
    # Inspecciona recursos PE sin ejecutar la app ni acceder a su persistencia.
    [string]$ExecutablePath
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$contract = Get-Content -LiteralPath (Join-Path $taskRoot 'packaging/windows/installation-contract.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$resource = Get-Content -LiteralPath (Join-Path $taskRoot 'windows/runner/Runner.rc') -Raw -Encoding UTF8
$cmake = Get-Content -LiteralPath (Join-Path $taskRoot 'windows/CMakeLists.txt') -Raw
$lockfile = Get-Content -LiteralPath (Join-Path $taskRoot 'pubspec.lock') -Raw
$pubspec = Get-Content -LiteralPath (Join-Path $taskRoot 'pubspec.yaml') -Raw

foreach ($field in @{
    CompanyName = $contract.companyName
    ProductName = $contract.productName
    FileDescription = $contract.appName
    InternalName = $contract.internalName
    OriginalFilename = $contract.executable
}.GetEnumerator()) {
    $pattern = 'VALUE\s+"' + $field.Key + '",\s*"' + [regex]::Escape($field.Value) + '"'
    if ($resource -cnotmatch $pattern) { throw "Identidad Windows alterada: $($field.Key)." }
}
if ($cmake -cnotmatch ('set\(BINARY_NAME "' + [regex]::Escape($contract.binaryName) + '"\)')) {
    throw 'BINARY_NAME no coincide con el contrato.'
}
$providerPattern = '(?ms)^  path_provider_windows:\r?\n(?:(?!^  \S)[\s\S])*?    version: "' + [regex]::Escape($contract.pathProviderWindowsVersion) + '"'
if ($lockfile -notmatch $providerPattern) { throw 'Revisar contrato: cambio de path_provider_windows.' }
if ($pubspec -notmatch '(?m)^version: (0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+([1-9]\d*)\s*$') {
    throw 'Se requiere major.minor.patch+build numerico positivo, sin sufijos.'
}
$appVersion = $Matches[0].Trim().Substring('version: '.Length)
$parts = $appVersion -split '[.+]'
foreach ($part in $parts) {
    if ([decimal]$part -gt 65535) { throw 'Componente de version fuera del rango PE 0..65535.' }
}
$numericVersion = $parts -join '.'
$parsedId = [guid]::Parse($contract.appId)
if ($parsedId -eq [guid]::Empty) { throw 'AppId vacio.' }
Write-Output "Contrato v$($contract.contractVersion): $($contract.executable), $appVersion ($numericVersion), $($contract.architecture)."

if ($ExecutablePath) {
    $pePath = (Resolve-Path -LiteralPath $ExecutablePath).Path
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($pePath)
    foreach ($field in @{
        CompanyName = $contract.companyName
        ProductName = $contract.productName
        FileDescription = $contract.appName
        InternalName = $contract.internalName
        OriginalFilename = $contract.executable
        FileVersion = $appVersion
        ProductVersion = $appVersion
    }.GetEnumerator()) {
        if ($info.($field.Key) -cne $field.Value) { throw "Recurso PE incorrecto: $($field.Key)." }
    }
    $peNumeric = '{0}.{1}.{2}.{3}' -f $info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart
    if ($peNumeric -ne $numericVersion) { throw 'FILEVERSION numerica no coincide con pubspec.' }
    $productNumeric = '{0}.{1}.{2}.{3}' -f $info.ProductMajorPart, $info.ProductMinorPart, $info.ProductBuildPart, $info.ProductPrivatePart
    if ($productNumeric -ne $numericVersion) { throw 'PRODUCTVERSION numerica no coincide con pubspec.' }
    $stream = [IO.File]::OpenRead($pePath)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5a4d) { throw 'Cabecera DOS no valida.' }
        $stream.Position = 0x3c
        $peOffset = $reader.ReadUInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw 'El payload debe ser PE x64 (AMD64).'
        }
    } finally { $reader.Dispose(); $stream.Dispose() }

    # Mismo Known Folder/API que path_provider_windows 2.3.0. Solo consulta:
    # no crea el directorio, no lo enumera, no lee bases/registro/CredManager.
    if (-not ('AutofinanceContract.KnownFolder' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace AutofinanceContract {
    public static class KnownFolder {
        [DllImport("shell32.dll")]
        private static extern int SHGetKnownFolderPath(ref Guid id, uint flags, IntPtr token, out IntPtr path);
        public static string Roaming() {
            Guid id = new Guid("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D");
            IntPtr path;
            int result = SHGetKnownFolderPath(ref id, 0, IntPtr.Zero, out path);
            try {
                Marshal.ThrowExceptionForHR(result);
                return Marshal.PtrToStringUni(path);
            } finally { Marshal.FreeCoTaskMem(path); }
        }
    }
}
'@
    }
    $roaming = [AutofinanceContract.KnownFolder]::Roaming()
    if (-not $roaming -or -not [IO.Path]::IsPathRooted($roaming)) { throw 'Known Folder no resoluble.' }
    $effectiveSupport = Join-Path (Join-Path $roaming $info.CompanyName) $info.ProductName
    if ($effectiveSupport -cne (Join-Path $roaming $contract.supportRelativePath)) { throw 'Ruta de soporte distinta del contrato.' }
    # No revelar la raiz del perfil, tampoco si Known Folder esta redirigido.
    $safeSupport = '%RoamingAppData%\' + $contract.supportRelativePath
    Write-Output "PE verificado sin ejecutar. Soporte derivado de Known Folder y recursos: $safeSupport"
    Write-Output 'No acredita instalacion ni consulta getApplicationSupportDirectory dentro del runner (T03/T08).'
}
