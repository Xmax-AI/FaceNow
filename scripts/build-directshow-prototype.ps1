[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseClasses,
    [string]$BuildRoot = 'C:\dev\FaceNow-directshow-prototype',
    [string]$VisualStudio = 'C:\dev\VisualStudio2022'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$BaseClasses = (Resolve-Path -LiteralPath $BaseClasses).ProviderPath
$devcmd = Join-Path $VisualStudio 'Common7/Tools/VsDevCmd.bat'
if (!(Test-Path -LiteralPath $devcmd)) { throw 'Pass -VisualStudio pointing to Visual Studio with the x64 C++ tools installed.' }
if (!(Test-Path -LiteralPath "$BaseClasses/streams.h")) { throw 'Pass -BaseClasses pointing to the DirectShow BaseClasses from Microsoft Windows classic samples.' }

$out = (New-Item -ItemType Directory -Force $BuildRoot).FullName
$source = Join-Path $repo 'native/DirectShow'
$flags = '/nologo /std:c++17 /EHsc /MT /O2 /DWIN32_LEAN_AND_MEAN /DUNICODE /D_UNICODE /DWINVER=0x0A00 /D_WIN32_WINNT=0x0A00'
$includes = "/I`"$BaseClasses`" /I`"$repo/native/third_party/wil`""
$objects = Get-ChildItem -LiteralPath $BaseClasses -Filter '*.cpp' -File | ForEach-Object { '"' + $_.BaseName + '.obj"' }
$commands = @(
    "@call `"$devcmd`" -no_logo -arch=x64 -host_arch=x64",
    '@if errorlevel 1 exit /b 1',
    "@cd /d `"$out`"",
    "cl $flags /I`"$BaseClasses`" /c `"$BaseClasses\*.cpp`"",
    '@if errorlevel 1 exit /b 1',
    "cl $flags /DNOMINMAX $includes /LD `"$source\CameraFilter.cpp`" $($objects -join ' ') /link /DEF:`"$source\CameraFilter.def`" /OUT:FaceNow.DirectShowPrototype.dll strmiids.lib mfuuid.lib ole32.lib oleaut32.lib advapi32.lib crypt32.lib cfgmgr32.lib winmm.lib user32.lib gdi32.lib",
    '@if errorlevel 1 exit /b 1'
)
$batch = Join-Path $out 'build.cmd'
[IO.File]::WriteAllLines($batch, $commands, [Text.Encoding]::Default)
& cmd.exe /c $batch
if ($LASTEXITCODE -ne 0) { throw 'DirectShow prototype build failed.' }
Write-Output "Built FaceNow DirectShow prototype (x64): $out"
