[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BuildRoot,
    [string]$MediaDirectory = 'C:\dev\FaceNow-media',
    [string]$CameraBuildRoot = 'C:\dev\FaceNow-camera',
    [string]$NsisCompiler = 'C:\dev\FaceNow-tools\nsis-3.12\makensis.exe',
    [string]$ReleaseDirectory = '',
    [switch]$SkipTests
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$version = ([xml](Get-Content "$repo/Directory.Build.props" -Raw)).Project.PropertyGroup.Version
$editions = [ordered]@{ Domestic = 'mainland'; Overseas = 'overseas' }
if (!$ReleaseDirectory) {
    $ReleaseDirectory = Join-Path $repo ".build/releases/$version-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
}
$ReleaseDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReleaseDirectory)
if (Test-Path -LiteralPath $ReleaseDirectory) { throw "Release directory already exists: $ReleaseDirectory" }
if (Test-Path $BuildRoot) { throw 'Use a fresh local BuildRoot for the two edition packages.' }
New-Item -ItemType Directory $BuildRoot | Out-Null
foreach ($edition in $editions.Keys) {
    $root = Join-Path $BuildRoot $edition
    if (!$SkipTests) {
        & "$PSScriptRoot/test-media.ps1" -BuildRoot "$root/tests/media" -MediaDirectory $MediaDirectory -Edition $edition -FullHd
        & "$PSScriptRoot/test-generation.ps1" -BuildRoot "$root/tests/generation" -Edition $edition
        & "$PSScriptRoot/test-accounts.ps1" -BuildRoot "$root/tests/accounts" -Edition $edition
    }
    & "$PSScriptRoot/build-installer.ps1" -BuildRoot "$root/app" -CameraBuildRoot $CameraBuildRoot -NsisCompiler $NsisCompiler -MediaDirectory $MediaDirectory -Edition $edition
}
$packages = Join-Path $BuildRoot 'packages'
New-Item -ItemType Directory $packages | Out-Null
Get-ChildItem "$BuildRoot/*/app/packages/*-Setup-*.exe" | Copy-Item -Destination $packages
Get-ChildItem "$packages/*.exe" | ForEach-Object {
    '{0}  {1}' -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(),$_.Name
} | Set-Content "$packages/SHA256SUMS" -Encoding UTF8
Write-Output "Both FaceNow edition installers: $packages"

New-Item -ItemType Directory -Path (Split-Path -Parent $ReleaseDirectory) -Force | Out-Null
New-Item -ItemType Directory -Path $ReleaseDirectory | Out-Null
$releaseName = 'FaceNow.exe'
$checksums = foreach ($edition in $editions.Keys) {
    $productId = if ($edition -eq 'Overseas') { 'FaceNowOverseas' } else { 'FaceNow' }
    $installer = Join-Path $packages "$productId-Setup-$version.exe"
    $region = $editions[$edition]
    $destination = Join-Path $ReleaseDirectory $region
    New-Item -ItemType Directory -Path $destination | Out-Null
    $executable = Join-Path $destination $releaseName
    Copy-Item -LiteralPath $installer -Destination $executable
    '{0}  {1}/{2}' -f (Get-FileHash -LiteralPath $executable).Hash.ToLowerInvariant(),$region,$releaseName
}
$checksumFile = Join-Path $ReleaseDirectory 'SHA256SUMS'
[IO.File]::WriteAllText($checksumFile, (($checksums -join "`n") + "`n"), [Text.Encoding]::ASCII)
$archivePaths = @($editions.Values | ForEach-Object { Join-Path $ReleaseDirectory $_ })
$archivePaths += $checksumFile
$archive = Join-Path $ReleaseDirectory "FaceNow-$version-windows.zip"
Compress-Archive -LiteralPath $archivePaths -DestinationPath $archive -CompressionLevel NoCompression
Write-Output "FaceNow release: $ReleaseDirectory"
Write-Output "Both FaceNow edition installers in one archive: $archive"
