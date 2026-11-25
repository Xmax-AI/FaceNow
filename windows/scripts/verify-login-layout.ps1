[CmdletBinding()]
param(
    [string]$BuildRoot = 'C:\dev\FaceNow-login-aligned',
    [switch]$NoBuild
)
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot/run.ps1" -BuildOnly -NoBuild:$NoBuild -BuildRoot $BuildRoot
$repo = Split-Path -Parent $PSScriptRoot
$previous = $env:FACENOW_SMOKE_OUTPUT
try {
    $env:FACENOW_SMOKE_OUTPUT = Join-Path $repo '.build/login-alignment'
    New-Item -ItemType Directory -Force $env:FACENOW_SMOKE_OUTPUT | Out-Null
    $report = Join-Path $env:FACENOW_SMOKE_OUTPUT 'smoke-test-login-layout.json'
    $unhandled = Join-Path $env:FACENOW_SMOKE_OUTPUT 'unhandled.txt'
    Remove-Item $report,$unhandled -ErrorAction SilentlyContinue
    $app = Join-Path $BuildRoot 'bin/FaceNow.App/x64/Release/net10.0-windows10.0.26100.0/win-x64/FaceNow.exe'
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $app
    $start.Arguments = '--smoke-test-login-layout'
    $start.WorkingDirectory = Split-Path $app
    $start.UseShellExecute = $false
    & "$PSScriptRoot/close-running.ps1"
    $process = [Diagnostics.Process]::Start($start)
    try {
        if (!$process.WaitForExit(60000)) { $null = $process.CloseMainWindow(); throw 'Login layout verification timed out.' }
        if (!(Test-Path $report)) { throw "No login layout report (exit $($process.ExitCode))." }
        $result = Get-Content $report -Raw | ConvertFrom-Json
        if (!$result.passed -or $process.ExitCode -ne 0 -or (Test-Path $unhandled)) { throw "Login layout failed (exit $($process.ExitCode)): $($result.error)" }
        Write-Output 'PASS login layout: minimum/default/wide, three methods, focus, enabled, loading, invalid key; isolated account, no camera or account requests.'
    }
    finally { $process.Dispose() }
}
finally { $env:FACENOW_SMOKE_OUTPUT = $previous }
