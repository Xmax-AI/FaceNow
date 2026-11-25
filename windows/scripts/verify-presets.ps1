#
#  verify-presets.ps1
#  FaceNow
#

[CmdletBinding()]
param(
    [ValidateSet('Domestic','Overseas')][string]$Edition = 'Domestic',
    [string]$BuildRoot = 'C:\dev\FaceNow-presets',
    [string]$MediaDirectory = 'C:\dev\FaceNow-media',
    [switch]$NoBuild
)
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot/run.ps1" -BuildOnly -NoBuild:$NoBuild -Edition $Edition -BuildRoot $BuildRoot -MediaDirectory $MediaDirectory
$repo = Split-Path -Parent $PSScriptRoot
$previous = $env:FACENOW_SMOKE_OUTPUT
try {
    $env:FACENOW_SMOKE_OUTPUT = Join-Path $repo ".build/preset-verification/$Edition"
    New-Item -ItemType Directory -Force $env:FACENOW_SMOKE_OUTPUT | Out-Null
    $report = Join-Path $env:FACENOW_SMOKE_OUTPUT 'smoke-test-presets.json'
    $unhandled = Join-Path $env:FACENOW_SMOKE_OUTPUT 'unhandled.txt'
    Remove-Item $report,$unhandled -ErrorAction SilentlyContinue
    $app = Join-Path $BuildRoot 'bin/FaceNow.App/x64/Release/net10.0-windows10.0.26100.0/win-x64/FaceNow.exe'
    & "$PSScriptRoot/close-running.ps1"
    $process = Start-Process $app -ArgumentList '--smoke-test-presets' -WorkingDirectory (Split-Path $app) -PassThru
    try {
        if (!$process.WaitForExit(180000)) { $null = $process.CloseMainWindow(); throw 'Preset verification timed out.' }
        if (!(Test-Path $report)) { throw "No preset report (exit $($process.ExitCode))." }
        $result = Get-Content $report -Raw | ConvertFrom-Json
        if (!$result.passed -or $process.ExitCode -ne 0 -or (Test-Path $unhandled)) { throw "Preset verification failed: $($result.error)" }
        Write-Output "PASS $Edition presets: all thumbnails decoded, five mode tabs, prompt-only summon, minimum window; no camera, account or generation requests."
    }
    finally { $process.Dispose() }
}
finally { $env:FACENOW_SMOKE_OUTPUT = $previous }
