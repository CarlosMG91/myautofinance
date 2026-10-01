param()
$ErrorActionPreference = 'Stop'

# Mismo directorio y comandos para agentes y runners Windows/Linux (PowerShell 7).
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & (Join-Path $PSScriptRoot 'check-toolchain.ps1')

    & flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron resolver las dependencias fijadas.' }

    & dart format --output=none --set-exit-if-changed lib test
    if ($LASTEXITCODE -ne 0) { throw 'Formato pendiente: ejecutar dart format lib test.' }

    & flutter analyze --no-pub --fatal-infos --fatal-warnings
    if ($LASTEXITCODE -ne 0) { throw 'El análisis estático ha fallado.' }

    & flutter test --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Las pruebas han fallado.' }

    foreach ($appEnvironment in @('development', 'test', 'production', 'invalid-synthetic')) {
        & flutter test --no-pub "--dart-define=APP_ENV=$appEnvironment" test/environment_bootstrap_test.dart
        if ($LASTEXITCODE -ne 0) { throw "El arranque con APP_ENV=$appEnvironment ha fallado." }
    }
    Write-Output 'Calidad correcta: formato, análisis, pruebas y configuración de arranque.'
}
finally {
    Pop-Location
}
