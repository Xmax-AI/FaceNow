[CmdletBinding()]
param(
    [ValidateSet('Domestic','Overseas')][string]$Edition = 'Domestic',
    [string]$MediaDirectory = 'C:\dev\FaceNow-media',
    [string]$BuildRoot = 'C:\dev\FaceNow-build',
    [string]$DotNet = 'C:\dev\dotnet\dotnet.exe',
    [string]$CameraBuildRoot = 'C:\dev\FaceNow-camera',
    [switch]$Preview,
    [switch]$PreviewSession,
    [switch]$PreviewCameraSetup,
    [switch]$PreviewLogin,
    [switch]$Verify,
    [switch]$VerifyCamera,
    [switch]$VerifyRelay,
    [switch]$BuildOnly,
    [switch]$NoBuild
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (!(Test-Path $DotNet)) { $DotNet = (Get-Command dotnet -ErrorAction Stop).Source }
if ($BuildRoot.StartsWith('\\')) { throw 'Use a local Windows build directory.' }
$env:DOTNET_ROOT = Split-Path $DotNet
$build = $BuildRoot.Replace('\','/').TrimEnd('/') + '/'
$stamp = Join-Path $BuildRoot '.facenow-edition'
if ((Test-Path $stamp) -and (Get-Content $stamp -Raw).Trim() -ne $Edition) { throw 'Use a separate BuildRoot for each FaceNow edition.' }
New-Item -ItemType Directory -Force $BuildRoot | Out-Null
Set-Content $stamp $Edition
if (!$NoBuild) {
    & "$PSScriptRoot/restore-sdk.ps1"
    & $DotNet build "$repo/src/FaceNow.App/FaceNow.App.csproj" -c Release '-p:Platform=x64' "-p:FaceNowBuildRoot=$build" "-p:FaceNowEdition=$Edition" "-p:FaceNowMediaDirectory=$MediaDirectory"
    if ($LASTEXITCODE -ne 0) { throw 'FaceNow build failed.' }
}
$app = Join-Path $BuildRoot 'bin/FaceNow.App/x64/Release/net10.0-windows10.0.26100.0/win-x64/FaceNow.exe'
if (!(Test-Path $app)) { throw "Build output was not found: $app" }
foreach ($name in @('XmaxSDK.dll', 'agora_rtc_sdk.dll', 'libagora_clear_vision_extension.dll', 'Xmax.VideoBeautyWorker.exe')) {
    if (!(Test-Path -LiteralPath (Join-Path (Split-Path $app) $name) -PathType Leaf)) {
        throw "The app output is missing SDK runtime file $name. Rebuild with the released SDK packages."
    }
}
foreach ($architecture in @('x64','arm64','directshow-x64')) {
    $nativeCamera = Join-Path $CameraBuildRoot $architecture
    if ((Test-Path "$nativeCamera/FaceNow.CameraControl.exe") -and (Test-Path "$nativeCamera/FaceNow.CameraSource.dll")) {
        $destination = Join-Path (Split-Path $app) "Camera/$architecture"
        New-Item -ItemType Directory -Force $destination | Out-Null
        Copy-Item "$nativeCamera/FaceNow.CameraControl.exe","$nativeCamera/FaceNow.CameraSource.dll" $destination -Force
    }
}
if ($BuildOnly) { Write-Output $app; exit }
foreach ($existing in @(Get-Process -Name FaceNow -ErrorAction SilentlyContinue)) {
    if ($existing.HasExited) { continue }
    if (!$existing.CloseMainWindow() -or !$existing.WaitForExit(30000)) {
        throw "Close the existing FaceNow instance (PID $($existing.Id)) before opening another build."
    }
}
if (@(Get-Process -Name FaceNow -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'FaceNow is still running. Close it before opening another build.'
}
if ($Verify -or $VerifyCamera -or $VerifyRelay) {
    $previous = $env:FACENOW_SMOKE_OUTPUT
    $previousCredential = $env:FACENOW_SMOKE_CREDENTIAL_ID
    try {
        $env:FACENOW_SMOKE_OUTPUT = Join-Path $repo '.build/verification'
        New-Item -ItemType Directory -Force $env:FACENOW_SMOKE_OUTPUT | Out-Null
        $env:FACENOW_SMOKE_CREDENTIAL_ID = [Guid]::NewGuid().ToString('N')
        $modes = @()
        if ($Verify) { $modes += @('--smoke-test-account','--smoke-test-ui','--smoke-test-frames','--smoke-test-key-gate','--smoke-test-key-memory-write','--smoke-test-key-memory-read','--smoke-test-key-memory-clear','--smoke-test-key-memory-empty') }
        if ($VerifyCamera) { $modes += '--smoke-test-virtual-camera' }
        if ($VerifyRelay) { $modes += '--smoke-test-camera-relay' }
        foreach ($mode in $modes) {
            $report = Join-Path $env:FACENOW_SMOKE_OUTPUT ($mode.TrimStart('-') + '.json')
            Remove-Item $report -ErrorAction SilentlyContinue
            $process = Start-Process $app -ArgumentList $mode -WorkingDirectory (Split-Path $app) -PassThru
            if (!$process.WaitForExit(120000)) { Stop-Process -Id $process.Id -Force; throw "$mode timed out." }
            if (!(Test-Path $report)) { throw "$mode did not produce a report (exit $($process.ExitCode))." }
            $result = Get-Content $report -Raw | ConvertFrom-Json
            if (!$result.passed) { throw "$mode failed: $($result.error)" }
            Write-Output "PASS FaceNow $mode"
        }
    }
    finally { $env:FACENOW_SMOKE_OUTPUT = $previous; $env:FACENOW_SMOKE_CREDENTIAL_ID = $previousCredential }
    exit
}
$start = @{ FilePath=$app; WorkingDirectory=(Split-Path $app); PassThru=$true }
if ($PreviewLogin) { $start.ArgumentList = '--preview-login' }
elseif ($PreviewCameraSetup) { $start.ArgumentList = '--preview-camera-setup' }
elseif ($PreviewSession) { $start.ArgumentList = '--preview-session' }
elseif ($Preview) { $start.ArgumentList = '--preview' }
$process = Start-Process @start
Write-Output "FaceNow started (PID $($process.Id))."
