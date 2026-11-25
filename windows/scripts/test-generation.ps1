[CmdletBinding()]
param(
    [ValidateSet('Domestic','Overseas')][string]$Edition='Domestic',
    [string]$DotNet = 'C:\dev\dotnet\dotnet.exe',
    [string]$BuildRoot = 'C:\dev\FaceNow-generation-tests'
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path $DotNet)) { $DotNet = (Get-Command dotnet -ErrorAction Stop).Source }
$env:DOTNET_ROOT = Split-Path $DotNet
$repo = Split-Path -Parent $PSScriptRoot
$build = $BuildRoot.Replace('\','/').TrimEnd('/') + '/'
& "$PSScriptRoot/restore-sdk.ps1"
& $DotNet run --project "$repo/tests/FaceNow.GenerationTests/FaceNow.GenerationTests.csproj" -c Release '-p:Platform=x64' "-p:FaceNowBuildRoot=$build" "-p:FaceNowEdition=$Edition"
if ($LASTEXITCODE -ne 0) { throw 'Generation lifecycle tests failed.' }
