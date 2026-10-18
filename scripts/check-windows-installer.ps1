param(
    [string]$CMake = 'cmake',
    [string]$Generator = 'Visual Studio 17 2022',
    [string]$InnoDirectory = '.tools/inno-6.5.4'
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $taskRoot
try {
    $build = Join-Path $taskRoot '.tools/ma-tsk-232-native'
    & $CMake -S packaging/windows/installer -B $build -G $Generator -A Win32
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo configurar el adaptador.' }
    & $CMake --build $build --config Release
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar el adaptador.' }
    $ctest = Join-Path (Split-Path (Get-Command $CMake).Source -Parent) 'ctest.exe'
    & $ctest --test-dir $build -C Release --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw 'Pruebas nativas de archivos fallidas.' }
    & node --test scripts/tests/windows-installer.test.mjs scripts/tests/windows-payload.test.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Pruebas de contrato/paquete fallidas.' }
    $fixture = Join-Path $taskRoot ('.tools/ma-tsk-232-inno-fixture-' + [Guid]::NewGuid().ToString('N'))
    & node scripts/tests/compile-installer-fixture.mjs (Join-Path $build 'Release/autofinance_setup_bridge.dll') $fixture
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar el fixture sintetico.' }
    & (Join-Path $InnoDirectory 'ISCC.exe') ('/DPackageInclude=' + (Join-Path $fixture 'output/package.iss.inc')) packaging/windows/autofinance.iss
    if ($LASTEXITCODE -ne 0) { throw 'Script Inno no compila.' }
    Write-Output 'Pruebas sinteticas y compilacion Inno correctas. El EXE de fixture NO es Autofinance instalable; no se ha ejecutado ni instalado. Perfil limpio/credenciales/UI pendientes.'
}
finally { Pop-Location }
