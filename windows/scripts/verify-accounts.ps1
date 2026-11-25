[CmdletBinding()]
param(
    [string]$BuildRoot = 'C:\dev\FaceNow-account-build',
    [string]$DotNet = 'C:\dev\dotnet\dotnet.exe',
    [switch]$SkipLogicTests,
    [ValidateRange(1,10)][int]$Repeat = 1
)
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot/run.ps1" -BuildOnly -BuildRoot $BuildRoot -DotNet $DotNet
if (!$SkipLogicTests) { & "$PSScriptRoot/test-accounts.ps1" -DotNet $DotNet }
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $BuildRoot 'bin/FaceNow.App/x64/Release/net10.0-windows10.0.26100.0/win-x64/FaceNow.exe'
$previous = $env:FACENOW_SMOKE_OUTPUT
try {
    $env:FACENOW_SMOKE_OUTPUT = Join-Path $repo '.build/account-verification'
    New-Item -ItemType Directory -Force $env:FACENOW_SMOKE_OUTPUT | Out-Null
    $report = Join-Path $env:FACENOW_SMOKE_OUTPUT 'smoke-test-account.json'
    $unhandled = Join-Path $env:FACENOW_SMOKE_OUTPUT 'unhandled.txt'
    for ($iteration = 1; $iteration -le $Repeat; $iteration++) {
        Remove-Item $report,$unhandled -ErrorAction SilentlyContinue
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $app
        $start.Arguments = '--smoke-test-account'
        $start.WorkingDirectory = Split-Path $app
        $start.UseShellExecute = $false
        & "$PSScriptRoot/close-running.ps1"
        $process = [Diagnostics.Process]::Start($start)
        try {
            if (!$process.WaitForExit(60000)) { $null = $process.CloseMainWindow(); throw 'Account UI verification timed out.' }
            if (!(Test-Path $report)) { throw "Account UI verification did not produce a report (exit $($process.ExitCode))." }
            $result = Get-Content $report -Raw | ConvertFrom-Json
            if (!$result.passed -or $process.ExitCode -ne 0 -or (Test-Path $unhandled)) {
                throw "Account UI verification failed (exit $($process.ExitCode)): $($result.error). Check $unhandled if present."
            }
            Write-Output "PASS isolated WinUI login $iteration/$Repeat : video playback, channel drafts, validation, resend, rejected key, success toast for all three login methods, toast timing/replacement/dismissal, verified home, account menu, sign-out and clean exit; no account requests or camera."
        }
        finally { $process.Dispose() }
    }
}
finally { $env:FACENOW_SMOKE_OUTPUT = $previous }
