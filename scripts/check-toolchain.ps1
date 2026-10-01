param()
$ErrorActionPreference = 'Stop'
$config = Get-Content (Join-Path $PSScriptRoot '../toolchain.json') -Raw | ConvertFrom-Json
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter no esta en PATH. Consulta docs/ep-003/entorno.md.'
}
$rawVersion = & flutter --version --machine
if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar la version de Flutter.' }
$version = ($rawVersion -join "`n") | ConvertFrom-Json
if ($version.frameworkVersion -ne $config.flutter) {
    throw "Flutter incorrecto: esperado $($config.flutter), encontrado $($version.frameworkVersion)."
}
if (($version.dartSdkVersion -split ' ')[0] -ne $config.dart) {
    throw "Dart incorrecto: esperado $($config.dart), encontrado $($version.dartSdkVersion)."
}
Write-Output "Versiones correctas: Flutter $($config.flutter), Dart $($config.dart)."
