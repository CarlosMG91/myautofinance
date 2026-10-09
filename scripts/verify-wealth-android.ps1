param(
    [Parameter(Mandatory = $true)]
    [string]$AndroidId,
    [string]$AdbPath = '',
    [string]$EvidenceDirectory = '.tools/148'
)

# Ejecuta el guion EP-009; el único evento externo es Back del sistema Android.
# No abre la base habitual: el runner crea y elimina su SQLite sintético.
if (-not $AdbPath) {
    $sdkDirectory = $env:ANDROID_HOME
    if (-not $sdkDirectory) {
        $sdkDirectory = Join-Path $env:LOCALAPPDATA 'Android/sdk'
    }
    $AdbPath = Join-Path $sdkDirectory 'platform-tools/adb.exe'
}
if (-not (Test-Path -LiteralPath $AdbPath)) { throw 'No se encuentra adb.' }
$AdbPath = (Resolve-Path -LiteralPath $AdbPath).Path
New-Item -ItemType Directory -Force $EvidenceDirectory -ErrorAction Stop | Out-Null
$evidencePath = (Resolve-Path -LiteralPath $EvidenceDirectory).Path
$runId = [Guid]::NewGuid().ToString('N')
$marker = "MA-TSK-148: esperando KEYCODE_BACK $runId"

# El identificador evita reaccionar a logcat de una ejecución anterior.
$backJob = Start-Job -ArgumentList $AdbPath, $AndroidId, $marker -ScriptBlock {
    param($adb, $device, $readyMarker)
    $deadline = (Get-Date).AddMinutes(12)
    while ((Get-Date) -lt $deadline) {
        $lines = & $adb -s $device logcat -d -s 'flutter:I' 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo leer logcat.' }
        if ($lines | Select-String -SimpleMatch $readyMarker) {
            & $adb -s $device shell input keyevent KEYCODE_BACK
            if ($LASTEXITCODE -ne 0) { throw 'No se pudo enviar Android Back.' }
            Write-Output "$readyMarker -> adb KEYCODE_BACK enviado"
            return
        }
        Start-Sleep -Milliseconds 500
    }
    throw 'No llegó el punto de comprobación Android Back.'
}

try {
    & flutter drive --debug --no-pub -d $AndroidId `
        --target=integration_test/wealth_management_test.dart `
        --driver=test/support/category_native_driver.dart `
        --dart-define=APP_ENV=test `
        --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false `
        --dart-define=WEALTH_ANDROID_BACK=true `
        "--dart-define=WEALTH_ANDROID_BACK_RUN=$runId" `
        2>&1 | Tee-Object (Join-Path $evidencePath 'native-android.log')
    $runnerExit = $LASTEXITCODE
    if ($runnerExit -ne 0) { throw "Recorrido Android fallido: código $runnerExit." }
    # El driver genérico puede devolver 0 tras un timeout del test nativo.
    # Exigir también el resultado del test impide acreditar un éxito falso.
    $nativeLog = Join-Path $evidencePath 'native-android.log'
    if ((Select-String -LiteralPath $nativeLog -SimpleMatch 'Some tests failed.') -or
        -not (Select-String -LiteralPath $nativeLog -SimpleMatch 'All tests passed!')) {
        throw 'El test nativo no terminó correctamente; consultar native-android.log.'
    }
    $backJob | Wait-Job -Timeout 10 | Out-Null
    if ($backJob.State -ne 'Completed') { throw 'Android Back no se confirmó en el host.' }
    $backJob | Receive-Job -ErrorAction Stop |
        Tee-Object (Join-Path $evidencePath 'android-back.log')
}
finally {
    $backJob | Stop-Job
    $backJob | Remove-Job
}
