[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AppDirectory,
    [string]$ReportDirectory = ''
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
if (!$ReportDirectory) { $ReportDirectory=Join-Path $repo ('.build/signout-regression/'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')) }
$application=Join-Path $AppDirectory 'FaceNow.exe'
if (!(Test-Path $application)) {throw 'Pass the directory of a self-contained FaceNow publish.'}
$managed=Join-Path $AppDirectory 'FaceNow.dll'
if (!(Test-Path $managed) -or ![Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($managed)).Contains('VerifySignOutAsync')) {
    throw 'This build does not include the isolated sign-out regression modes. Build the current source first.'
}
foreach ($mode in @('--smoke-test-signout-cached','--smoke-test-signout')) {
    $output=Join-Path $ReportDirectory $mode.TrimStart('-')
    if (Test-Path $output) {throw 'Use a fresh report directory to avoid stale regression results.'}
    New-Item -ItemType Directory -Force $output | Out-Null
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$application
    $start.WorkingDirectory=$AppDirectory
    $start.Arguments=$mode
    $start.UseShellExecute=$false
    $start.EnvironmentVariables['FACENOW_SMOKE_OUTPUT']=$output
    $start.EnvironmentVariables['DOTNET_DISABLE_GUI_ERRORS']='1'
    & "$PSScriptRoot/close-running.ps1"
    $process=[Diagnostics.Process]::Start($start)
    try {
        if (!$process.WaitForExit(60000)) {$null=$process.CloseMainWindow(); throw "Sign-out regression timed out; PID $($process.Id)."}
        $report=Join-Path $output ($mode.TrimStart('-')+'.json')
        if (!(Test-Path $report)) {throw "Sign-out regression exited without a report (exit $($process.ExitCode))."}
        $result=Get-Content $report -Raw | ConvertFrom-Json
        if (!$result.passed -or $process.ExitCode -ne 0 -or (Test-Path "$output/unhandled.txt")) {throw "Sign-out regression failed: $($result.error)"}
        Write-Output "PASS $mode : four account-popup sign-outs, cleared access, resumed login video, repeated login and clean exit."
    }
    finally {$process.Dispose()}
}
Write-Output "Eight sign-out cycles passed; simulated account, no credential-store access, camera, cloud generation or screenshots. Reports: $ReportDirectory"
