param(
    [string]$CMake = 'cmake',
    [string]$Generator = 'Visual Studio 17 2022'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$output = Join-Path $root '.tools/ma-tsk-230-native'
& $CMake -S (Join-Path $root 'windows/maintenance') -B $output -G $Generator -A x64
if ($LASTEXITCODE -ne 0) { throw 'No se pudo configurar el módulo nativo.' }
& $CMake --build $output --config Release
if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar el módulo nativo.' }
$ctest = Join-Path (Split-Path (Get-Command $CMake).Source -Parent) 'ctest.exe'
& $ctest --test-dir $output -C Release --output-on-failure
if ($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas del protocolo.' }
Write-Output 'Protocolo comprobado sin acceder a credenciales. Credential Manager requiere el perfil desechable documentado.'
