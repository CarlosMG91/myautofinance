param(
    [Parameter(Mandatory = $true)]
    [string]$Device
)
$ErrorActionPreference = 'Stop'

Push-Location (Join-Path $PSScriptRoot '..')
try {
    & (Join-Path $PSScriptRoot 'check-toolchain.ps1')
    $csvBytes = [IO.File]::ReadAllBytes((Join-Path $PWD 'docs/ep-001/historico-ejemplo.csv'))
    $buffer = New-Object IO.MemoryStream
    try {
        # La doble codificación base64 de dart-defines sin compresión excede
        # el límite de cmd.exe al generar flutter_assemble en Windows.
        $compressor = New-Object IO.Compression.GZipStream(
            $buffer, [IO.Compression.CompressionMode]::Compress, $true
        )
        try {
            $compressor.Write($csvBytes, 0, $csvBytes.Length)
        }
        finally {
            $compressor.Dispose()
        }
        $syntheticCsv = [Convert]::ToBase64String($buffer.ToArray())
    }
    finally {
        $buffer.Dispose()
    }
    $flutterArguments = @(
        'drive', '--debug', '--no-pub', '-d', $Device,
        '--target=integration_test/diagnostic_acceptance_test.dart',
        '--driver=test_driver/diagnostic_acceptance.dart',
        '--dart-define=APP_ENV=test',
        '--dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false',
        "--dart-define=SYNTHETIC_CSV_GZIP_BASE64=$syntheticCsv"
    )
    # FlutterDriver escribe también progreso correcto en stderr. PowerShell
    # 5 no debe convertir ese progreso en una excepción del script.
    $previousErrorPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & flutter @flutterArguments
    }
    finally {
        $ErrorActionPreference = $previousErrorPreference
    }
    if ($LASTEXITCODE -ne 0) { throw "El recorrido nativo de diagnóstico falló en $Device." }
}
finally {
    Pop-Location
}
