[CmdletBinding()]
param(
    [string]$BuildRoot = 'C:\dev\FaceNow-camera',
    [ValidateSet('x64','arm64')][string]$Architecture = $(if ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64' -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }),
    [switch]$Installed
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$output = Join-Path $repo '.build/verification'
New-Item -ItemType Directory -Force $output | Out-Null
$helper = Join-Path $BuildRoot "$Architecture/FaceNow.CameraControl.exe"
$scalingTests = Join-Path $BuildRoot "$Architecture/FaceNow.FrameScalingTests.exe"
& (Join-Path $BuildRoot "$Architecture/FaceNow.WaitingCanvasTests.exe")
if ($LASTEXITCODE -ne 0) { throw 'Virtual camera waiting-artwork regression checks failed.' }
& $scalingTests
if ($LASTEXITCODE -ne 0) { throw 'Virtual camera center-fill regression checks failed.' }
& (Join-Path $BuildRoot "$Architecture/FaceNow.FramePipeTests.exe")
if ($LASTEXITCODE -ne 0) { throw 'Virtual camera signed-stride pipe regression checks failed.' }
function Invoke-Check([string]$Mode, [string]$Name) {
    $report = Join-Path $output ($Name + '.json')
    $errorFile = Join-Path $output ($Name + '-error.txt')
    $bitmap = Join-Path $output ($Name + '.bmp')
    $process = Start-Process $helper -ArgumentList @($Mode,$bitmap) -PassThru -WindowStyle Hidden -RedirectStandardOutput $report -RedirectStandardError $errorFile
    $null = $process.Handle
    if (!$process.WaitForExit(45000)) { Stop-Process -Id $process.Id -Force; throw "$Mode timed out." }
    $process.WaitForExit()
    if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) { throw "$Mode failed ($($process.ExitCode)): $(Get-Content $errorFile -Raw)" }
    $result = Get-Content $report -Raw | ConvertFrom-Json
    if (!$result.passed -or $result.frames -ne 10) { throw "Invalid camera result: $report" }
    Write-Output "PASS $Name ($($result.width)x$($result.height), $($result.frames) frames)"
}
Invoke-Check '--self-test' "native-self-test-$Architecture"
if ($Installed) { Invoke-Check '--verify' 'windows-frame-server' }
