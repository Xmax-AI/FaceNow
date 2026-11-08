[CmdletBinding()]
param(
    [ValidateSet('Domestic','Overseas')][string]$Edition = 'Domestic',
    [string]$MediaDirectory = 'C:\dev\FaceNow-media',
    [string]$NativeDirectory = 'C:\dev\XmaxSDK-build\Sources\XmaxSDK\RelWithDebInfo',
    [string]$BuildRoot = 'C:\dev\FaceNow-build',
    [string]$XmaxSdkRoot = '',
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
if (!$XmaxSdkRoot) { $XmaxSdkRoot = Join-Path (Split-Path -Parent $repo) 'XmaxSDK' }
if (!(Test-Path $DotNet)) { $DotNet = (Get-Command dotnet -ErrorAction Stop).Source }
if ($BuildRoot.StartsWith('\\')) { throw 'Use a local Windows build directory.' }
if (!(Test-Path "$XmaxSdkRoot/Sources/XmaxSDK.WinUI/XmaxSDK.WinUI.csproj")) { throw 'Pass -XmaxSdkRoot pointing to the adjacent XmaxSDK.' }
if (!(Test-Path "$NativeDirectory/XmaxSDK.dll")) { throw 'Pass -NativeDirectory containing XmaxSDK.dll and matching dependencies.' }
$env:DOTNET_ROOT = Split-Path $DotNet
$build = $BuildRoot.Replace('\','/').TrimEnd('/') + '/'
$stamp = Join-Path $BuildRoot '.facenow-edition'
if ((Test-Path $stamp) -and (Get-Content $stamp -Raw).Trim() -ne $Edition) { throw 'Use a separate BuildRoot for each FaceNow edition.' }
New-Item -ItemType Directory -Force $BuildRoot | Out-Null
Set-Content $stamp $Edition
if (!$NoBuild) {
    & $DotNet build "$repo/src/FaceNow.App/FaceNow.App.csproj" -c Release '-p:Platform=x64' "-p:FaceNowBuildRoot=$build" "-p:XmaxDotNetBuildRoot=${build}sdk/" "-p:XmaxSdkRoot=$XmaxSdkRoot" "-p:XmaxNativeDir=$NativeDirectory" "-p:FaceNowEdition=$Edition" "-p:FaceNowMediaDirectory=$MediaDirectory"
    if ($LASTEXITCODE -ne 0) { throw 'FaceNow build failed.' }
}
$app = Join-Path $BuildRoot 'bin/FaceNow.App/x64/Release/net10.0-windows10.0.26100.0/win-x64/FaceNow.exe'
if (!(Test-Path $app)) { throw "Build output was not found: $app" }
foreach ($architecture in @('x64','arm64','directshow-x64')) {
    $nativeCamera = Join-Path $CameraBuildRoot $architecture
    if ((Test-Path "$nativeCamera/FaceNow.CameraControl.exe") -and (Test-Path "$nativeCamera/FaceNow.CameraSource.dll")) {
        $destination = Join-Path (Split-Path $app) "Camera/$architecture"
        New-Item -ItemType Directory -Force $destination | Out-Null
        Copy-Item "$nativeCamera/FaceNow.CameraControl.exe","$nativeCamera/FaceNow.CameraSource.dll" $destination -Force
    }
}
if ($BuildOnly) { Write-Output $app; exit }
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
