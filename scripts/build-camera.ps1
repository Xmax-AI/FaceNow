[CmdletBinding()]
param(
    [string]$BuildRoot = 'C:\dev\FaceNow-camera',
    [string]$VisualStudio = 'C:\dev\VisualStudio2022',
    [ValidateSet('x64','arm64')][string[]]$Architectures = @('x64','arm64')
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$devcmd = Join-Path $VisualStudio 'Common7/Tools/VsDevCmd.bat'
if (!(Test-Path $devcmd)) { throw 'Pass -VisualStudio with Desktop C++ and ARM64 tools installed.' }
$sdkInclude = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/Include/10.0.26100.0'
$source = Join-Path $repo 'native/CameraSource'
$files = @('SimpleMediaSource.cpp','SimpleMediaStream.cpp','SimpleFrameGenerator.cpp','VirtualCameraMediaSourceActivate.cpp','dllmain.cpp','winrtCommon.cpp') | ForEach-Object { '"' + (Join-Path $source $_) + '"' }
foreach ($arch in $Architectures) {
    $out = Join-Path $BuildRoot $arch
    New-Item -ItemType Directory -Force $out | Out-Null
    $flags = '/nologo /std:c++17 /EHsc /MT /O2 /DWIN32_LEAN_AND_MEAN /DNOMINMAX /DUNICODE /D_UNICODE /DWINVER=0x0A00 /D_WIN32_WINNT=0x0A00'
    $includes = "/I`"$source`" /I`"$repo/native/third_party/wil`" /I`"$sdkInclude/cppwinrt`""
    $commands = @(
        "@call `"$devcmd`" -no_logo -arch=$arch -host_arch=x64",
        "@cd /d `"$out`"",
        "cl $flags $includes /LD $($files -join ' ') /link /DEF:`"$source/VirtualCameraMediaSource.def`" /OUT:FaceNow.CameraSource.dll mf.lib mfplat.lib mfuuid.lib mfsensorgroup.lib windowsapp.lib ole32.lib advapi32.lib crypt32.lib",
        '@if errorlevel 1 exit /b 1',
        "cl $flags /I`"$repo/native`" `"$repo/native/CameraControl.cpp`" /link /OUT:FaceNow.CameraControl.exe mf.lib mfplat.lib mfuuid.lib mfreadwrite.lib mfsensorgroup.lib ole32.lib advapi32.lib shell32.lib crypt32.lib",
        '@if errorlevel 1 exit /b 1',
        "cl $flags `"$repo/native/tests/CenterFillTests.cpp`" /link /OUT:FaceNow.FrameScalingTests.exe",
        '@if errorlevel 1 exit /b 1',
        "cl $flags $includes `"$repo/native/tests/FramePipeTests.cpp`" /link /OUT:FaceNow.FramePipeTests.exe mfplat.lib mfuuid.lib ole32.lib advapi32.lib crypt32.lib",
        '@if errorlevel 1 exit /b 1'
    )
    $batch = Join-Path $out 'build.cmd'
    [IO.File]::WriteAllLines($batch, $commands, [Text.Encoding]::Default)
    & cmd.exe /c $batch
    if ($LASTEXITCODE -ne 0) { throw "Native camera build failed ($arch)." }
    Write-Output "Built FaceNow camera ($arch): $out"
}
