[CmdletBinding()]
param([string]$BuildRoot='C:\dev\FaceNow-media', [string]$VisualStudio='C:\dev\VisualStudio2022',
      [string]$AgoraRoot='C:\dev\XmaxSDK-deps\agora\sdk', [string]$AgoraHeaders='')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
if (!$AgoraHeaders) { $AgoraHeaders=Join-Path $repo '.build/beauty-headers' }
if (!(Test-Path "$AgoraHeaders/IAgoraService.h")) { throw 'Pass -AgoraHeaders with matching Agora 4.6.2 low-level headers.' }
New-Item -ItemType Directory -Force $BuildRoot | Out-Null
$commands=@("@call `"$VisualStudio/Common7/Tools/VsDevCmd.bat`" -no_logo -arch=x64 -host_arch=x64", "@cd /d `"$BuildRoot`"",
 "cl /nologo /std:c++17 /utf-8 /EHsc /O2 /MT /DUNICODE /D_UNICODE /I`"$AgoraHeaders`" `"$repo/native/Beauty/BeautyWorker.cpp`" /link /OUT:FaceNow.BeautyWorker.exe `"$AgoraRoot/x86_64/agora_rtc_sdk.dll.lib`"", '@if errorlevel 1 exit /b 1',
 "cl /nologo /std:c++17 /utf-8 /EHsc /O2 /MT /LD /I`"$repo/native`" `"$repo/native/Beauty/FrameEffects.cpp`" /link /OUT:FaceNow.FrameEffects.dll", '@if errorlevel 1 exit /b 1')
[IO.File]::WriteAllLines("$BuildRoot/build-media.cmd",$commands,[Text.Encoding]::Default)
& cmd.exe /c "$BuildRoot/build-media.cmd"
if ($LASTEXITCODE -ne 0) {throw 'FaceNow beauty worker compilation failed.'}
Copy-Item "$AgoraRoot/x86_64/*.dll" $BuildRoot -Force
Write-Output "Media worker built: $BuildRoot/FaceNow.BeautyWorker.exe"
