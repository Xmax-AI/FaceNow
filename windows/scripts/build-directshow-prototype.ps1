[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseClasses,
    [string]$BuildRoot = 'C:\dev\FaceNow-directshow-prototype',
    [string]$VisualStudio = 'C:\dev\VisualStudio2022',
    [switch]$Production
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$BaseClasses = (Resolve-Path -LiteralPath $BaseClasses).ProviderPath
$devcmd = Join-Path $VisualStudio 'Common7/Tools/VsDevCmd.bat'
if (!(Test-Path -LiteralPath $devcmd)) { throw 'Pass -VisualStudio pointing to Visual Studio with the x64 C++ tools installed.' }
if (!(Test-Path -LiteralPath "$BaseClasses/streams.h")) { throw 'Pass -BaseClasses pointing to the DirectShow BaseClasses from Microsoft Windows classic samples.' }
if ($Production -and !(Test-Path -LiteralPath "$BaseClasses/LICENSE")) { throw 'Copy the Microsoft samples MIT LICENSE into the BaseClasses directory.' }

$out = (New-Item -ItemType Directory -Force $BuildRoot).FullName
$source = Join-Path $repo 'native/DirectShow'
$flags = '/nologo /std:c++17 /EHsc /MT /O2 /DWIN32_LEAN_AND_MEAN /DUNICODE /D_UNICODE /DWINVER=0x0A00 /D_WIN32_WINNT=0x0A00'
$includes = "/I`"$BaseClasses`" /I`"$repo/native/third_party/wil`""
$dll = if ($Production) { 'FaceNow.CameraSource.dll' } else { 'FaceNow.DirectShowPrototype.dll' }
$filterFlags = if ($Production) { '' } else { '/DFACENOW_DIRECTSHOW_PROTOTYPE' }
$objects = Get-ChildItem -LiteralPath $BaseClasses -Filter '*.cpp' -File | ForEach-Object { '"' + $_.BaseName + '.obj"' }
$commands = @(
    "@call `"$devcmd`" -no_logo -arch=x64 -host_arch=x64",
    '@if errorlevel 1 exit /b 1',
    "@cd /d `"$out`"",
    "cl $flags /I`"$BaseClasses`" /c `"$BaseClasses\*.cpp`"",
    '@if errorlevel 1 exit /b 1',
    "rc /nologo /I`"$repo/assets`" /fo CameraPlaceholder.res `"$repo/native/CameraPlaceholder.rc`"",
    '@if errorlevel 1 exit /b 1',
    "cl $flags /utf-8 /DNOMINMAX $filterFlags $includes /LD `"$source\CameraFilter.cpp`" $($objects -join ' ') CameraPlaceholder.res /link /DEF:`"$source\CameraFilter.def`" /OUT:$dll strmiids.lib mfuuid.lib ole32.lib oleaut32.lib advapi32.lib crypt32.lib cfgmgr32.lib winmm.lib user32.lib gdi32.lib windowscodecs.lib",
    '@if errorlevel 1 exit /b 1'
)
if ($Production) {
    $commands += @(
        "cl $flags /utf-8 /DNOMINMAX /DFACENOW_DIRECTSHOW_BACKEND `"$repo/native/CameraControl.cpp`" /link /OUT:FaceNow.CameraControl.exe strmiids.lib ole32.lib oleaut32.lib advapi32.lib shell32.lib crypt32.lib",
        '@if errorlevel 1 exit /b 1'
    )
}
$batch = Join-Path $out 'build.cmd'
[IO.File]::WriteAllLines($batch, $commands, [Text.Encoding]::Default)
& cmd.exe /c $batch
if ($LASTEXITCODE -ne 0) { throw 'DirectShow camera build failed.' }
if ($Production) { Copy-Item -LiteralPath "$BaseClasses/LICENSE" -Destination "$out/LICENSE" -Force }
Write-Output "Built $dll (DirectShow x64): $out"
