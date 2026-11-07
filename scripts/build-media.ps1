[CmdletBinding()]
param([string]$BuildRoot='C:\dev\FaceNow-media', [string]$VisualStudio='C:\dev\VisualStudio2022')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force $BuildRoot | Out-Null
$commands=@("@call `"$VisualStudio/Common7/Tools/VsDevCmd.bat`" -no_logo -arch=x64 -host_arch=x64", "@cd /d `"$BuildRoot`"",
 "cl /nologo /std:c++17 /utf-8 /EHsc /O2 /MT /LD /I`"$repo/native`" `"$repo/native/Output/FrameEffects.cpp`" /link /OUT:FaceNow.FrameEffects.dll", '@if errorlevel 1 exit /b 1')
[IO.File]::WriteAllLines("$BuildRoot/build-media.cmd",$commands,[Text.Encoding]::Default)
& cmd.exe /c "$BuildRoot/build-media.cmd"
if ($LASTEXITCODE -ne 0) {throw 'FaceNow output compositor compilation failed.'}
Write-Output "Output compositor built: $BuildRoot/FaceNow.FrameEffects.dll"
