[CmdletBinding()]
param(
    [ValidateSet('Domestic','Overseas')][string]$Edition = 'Domestic',
    [string]$MediaDirectory = 'C:\dev\FaceNow-media',
    [string]$BuildRoot = 'C:\dev\FaceNow-installer',
    [string]$CameraBuildRoot = 'C:\dev\FaceNow-camera',
    [string]$NsisCompiler = 'C:\dev\FaceNow-tools\nsis-3.12\makensis.exe',
    [string]$WebView2Bootstrapper = 'C:\dev\FaceNow-tools\WebView2\MicrosoftEdgeWebview2Setup.exe',
    [switch]$SkipPublish
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (!(Test-Path $NsisCompiler)) { throw 'Pass -NsisCompiler pointing to an official NSIS 3.12 or later compiler.' }
$webView2Installer = & "$PSScriptRoot/prepare-webview2.ps1" -InstallerPath $WebView2Bootstrapper
if (!$SkipPublish) {
    & "$PSScriptRoot/publish.ps1" -BuildRoot $BuildRoot -Slim -SkipArchive -Edition $Edition -MediaDirectory $MediaDirectory -CameraBuildRoot $CameraBuildRoot
    if (!$?) { throw 'Installer payload publishing failed.' }
}
$version = ([xml](Get-Content "$repo/Directory.Build.props" -Raw)).Project.PropertyGroup.Version
$productId = if ($Edition -eq 'Overseas') { 'FaceNowOverseas' } else { 'FaceNow' }
$payload = Join-Path $BuildRoot "publish/$productId-$version-win-x64"
if (!(Test-Path "$payload/FaceNow.exe")) { throw 'The installer payload is missing.' }
if ($SkipPublish) { & "$PSScriptRoot/check-sdk-abi.ps1" -Payload $payload }
$nsisNotices = Join-Path (Split-Path -Parent $NsisCompiler) 'COPYING'
if (!(Test-Path $nsisNotices)) { throw 'Use an official NSIS distribution including its COPYING file.' }
New-Item -ItemType Directory -Force "$payload/licenses" | Out-Null
Copy-Item $nsisNotices "$payload/licenses/NSIS-COPYING.txt" -Force
Copy-Item "$repo/THIRD_PARTY.md" "$payload/THIRD_PARTY.md" -Force
$packages = Join-Path $BuildRoot 'packages'
$work = Join-Path $BuildRoot 'installer'
New-Item -ItemType Directory -Force $packages,$work | Out-Null
$manifest = Join-Path $work 'RemovePayload.nsh'
$files = @(Get-ChildItem $payload -File -Recurse)
$lines = [Collections.Generic.List[string]]::new()
$lines.Add('!macro RemovePayload')
foreach ($file in $files) {
    $relative = $file.FullName.Substring($payload.Length).TrimStart('\','/').Replace('$','$$')
    $lines.Add('  Delete "$INSTDIR\'+$relative+'"')
}
foreach ($directory in (Get-ChildItem $payload -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending)) {
    $relative = $directory.FullName.Substring($payload.Length).TrimStart('\','/').Replace('$','$$')
    $lines.Add('  RMDir "$INSTDIR\'+$relative+'"')
}
$lines.Add('!macroend')
[IO.File]::WriteAllLines($manifest,$lines,[Text.UTF8Encoding]::new($false))
$sizeKiB = [Math]::Ceiling(($files | Measure-Object Length -Sum).Sum / 1KB)
$output = Join-Path $packages "$productId-Setup-$version.exe"
$editionArgument = if ($Edition -eq 'Overseas') { '/DOVERSEAS' } else { '/DDOMESTIC' }
& $NsisCompiler '/V3' $editionArgument "/DWEBVIEW2_BOOTSTRAPPER=$webView2Installer" "/DPAYLOAD=$payload" "/DOUTPUT=$output" "/DVERSION=$version" "/DSIZE_KB=$sizeKiB" "/DUNINSTALL_MANIFEST=$manifest" "$repo/installer/FaceNow.nsi"
if ($LASTEXITCODE -ne 0) { throw 'NSIS installer compilation failed.' }
'{0}  {1}' -f (Get-FileHash $output -Algorithm SHA256).Hash.ToLowerInvariant(),(Split-Path -Leaf $output) | Set-Content "$packages/SHA256SUMS" -Encoding UTF8
Write-Output "FaceNow installer: $output"
