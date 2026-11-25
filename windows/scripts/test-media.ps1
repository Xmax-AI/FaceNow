[CmdletBinding()]
param([string]$DotNet='C:\dev\dotnet\dotnet.exe', [string]$BuildRoot='C:\dev\FaceNow-media-tests',
      [string]$MediaDirectory='C:\dev\FaceNow-media',
      [ValidateSet('Domestic','Overseas')][string]$Edition='Domestic', [switch]$FullHd)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$env:DOTNET_ROOT=Split-Path $DotNet
$build=$BuildRoot.Replace('\','/').TrimEnd('/')+'/'
& "$PSScriptRoot/restore-sdk.ps1"
& $DotNet run --project "$repo/tests/FaceNow.MediaTests/FaceNow.MediaTests.csproj" -c Release '-p:Platform=x64' "-p:FaceNowBuildRoot=$build" "-p:FaceNowEdition=$Edition" -- $MediaDirectory $Edition $(if ($FullHd) {'1080'} else {'small'})
if ($LASTEXITCODE -ne 0) {throw 'FaceNow media and edition tests failed.'}
