param(
    [string]$AndroidId = 'emulator-5554',
    [string]$EvidenceDirectory = '.tools/ma-tsk-186-native'
)
$ErrorActionPreference = 'Stop'
$adbPath = Join-Path $env:LOCALAPPDATA 'Android/sdk/platform-tools/adb.exe'
if (-not (Test-Path -LiteralPath $adbPath)) { throw 'No se encuentra adb.' }
New-Item -ItemType Directory -Force $EvidenceDirectory | Out-Null
$evidencePath = (Resolve-Path -LiteralPath $EvidenceDirectory).Path
$runId = [Guid]::NewGuid().ToString('N')
$marker = "MA-TSK-186: esperando KEYCODE_BACK $runId"
$backJob = Start-Job -ArgumentList $adbPath, $AndroidId, $marker, $evidencePath -ScriptBlock {
    param($adb, $device, $readyMarker, $evidence)
    $ErrorActionPreference = 'Stop'
    "Esperando $readyMarker" | Set-Content -Encoding utf8 (Join-Path $evidence 'android-back.log')
    $deadline = (Get-Date).AddMinutes(10)
    while ((Get-Date) -lt $deadline) {
        $lines = & $adb -s $device logcat -d -s 'flutter:I' 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo leer logcat.' }
        if ($lines | Select-String -SimpleMatch $readyMarker) {
            $focused = & $adb -s $device shell dumpsys window 2>&1 |
                Select-String -SimpleMatch 'mCurrentFocus='
            if ($focused -notmatch 'com.carlosmg91.myautofinance') {
                throw "Autofinance no tiene foco para Back. Revisa el emulador: $focused"
            }
            & $adb -s $device shell input keyevent KEYCODE_BACK
            if ($LASTEXITCODE -ne 0) { throw 'No se pudo enviar Android Back.' }
            "$readyMarker -> adb KEYCODE_BACK enviado" | Add-Content -Encoding utf8 (Join-Path $evidence 'android-back.log')
            Write-Output "$readyMarker -> adb KEYCODE_BACK enviado"
            return
        }
        Start-Sleep -Milliseconds 500
    }
    throw 'No llegó el punto de comprobación Android Back.'
}
try {
    # PowerShell 5 convierte stderr informativo de FlutterDriver en ErrorRecord.
    # El resultado se verifica con código y log, sin interrumpir la conexión.
    $ErrorActionPreference = 'Continue'
    & flutter drive --debug --no-pub -d $AndroidId `
        --target=integration_test/indicator_screen_test.dart `
        --driver=test_driver/indicators.dart `
        --dart-define=APP_ENV=test `
        --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false `
        --dart-define=INDICATOR_ANDROID_BACK=true `
        "--dart-define=INDICATOR_ANDROID_BACK_RUN=$runId" `
        2>&1 | ForEach-Object { $_.ToString() } | Tee-Object (Join-Path $EvidenceDirectory 'android.log')
    $runnerExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($backJob.State -eq 'Failed') { $backJob | Receive-Job -ErrorAction Stop }
    if ($runnerExit -ne 0) { throw 'El runner Android ha fallado.' }
    $nativeLog = Join-Path $EvidenceDirectory 'android.log'
    if ((Select-String -LiteralPath $nativeLog -SimpleMatch 'Some tests failed.') -or
        -not (Select-String -LiteralPath $nativeLog -SimpleMatch 'All tests passed!')) {
        throw 'El test nativo no terminó correctamente.'
    }
    $backJob | Wait-Job -Timeout 10 | Out-Null
    if ($backJob.State -ne 'Completed') { throw 'Android Back no se confirmó en el host.' }
    $backJob | Receive-Job -ErrorAction Stop
    Copy-Item -LiteralPath (Join-Path $EvidenceDirectory 'android-back.log') `
        -Destination 'docs/ep-023/flutter-capturas/android-back.txt' -Force
} finally {
    $ErrorActionPreference = 'Stop'
    $backJob | Stop-Job
    $backJob | Remove-Job
}
