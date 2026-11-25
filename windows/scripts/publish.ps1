[CmdletBinding()]
param(
    [ValidateSet('Domestic','Overseas')][string]$Edition = 'Domestic',
    [string]$MediaDirectory = 'C:\dev\FaceNow-media',
    [string]$BuildRoot = 'C:\dev\FaceNow-release',
    [string]$CameraBuildRoot = 'C:\dev\FaceNow-camera',
    [string]$DotNet = 'C:\dev\dotnet\dotnet.exe',
    [string]$VcRuntimeDirectory = 'C:\dev\VisualStudio2022\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT',
    [switch]$Slim,
    [switch]$SkipArchive
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if ($BuildRoot.StartsWith('\\')) { throw 'Use a local Windows BuildRoot for XAML compilation.' }
if (!(Test-Path $DotNet)) { $DotNet = (Get-Command dotnet -ErrorAction Stop).Source }
foreach ($file in @("$VcRuntimeDirectory/vcruntime140.dll", "$VcRuntimeDirectory/msvcp140.dll")) {
    if (!(Test-Path $file)) { throw "Missing publish dependency: $file" }
}
if (!(Test-Path "$MediaDirectory/FaceNow.FrameEffects.dll")) { throw 'Build the FaceNow output compositor first.' }
foreach ($architecture in @('x64','arm64','directshow-x64')) {
    foreach ($name in @('FaceNow.CameraControl.exe','FaceNow.CameraSource.dll')) {
        if (!(Test-Path "$CameraBuildRoot/$architecture/$name")) { throw "Build the camera component first: $architecture/$name" }
    }
}
$directShowLicense = "$CameraBuildRoot/directshow-x64/LICENSE"
if (!(Test-Path $directShowLicense -PathType Leaf)) { throw 'The DirectShow BaseClasses MIT license is missing from the camera build.' }
$env:DOTNET_ROOT = Split-Path $DotNet
$version = ([xml](Get-Content "$repo/Directory.Build.props" -Raw)).Project.PropertyGroup.Version
$productId = if ($Edition -eq 'Overseas') { 'FaceNowOverseas' } else { 'FaceNow' }
$publish = Join-Path $BuildRoot "publish/$productId-$version-win-x64"
if (Test-Path $publish) { throw "Publish directory already exists; use a fresh BuildRoot: $publish" }
$properties = @('-p:Platform=x64', "-p:FaceNowBuildRoot=$($BuildRoot.Replace('\','/').TrimEnd('/'))/",
    "-p:FaceNowEdition=$Edition", "-p:FaceNowMediaDirectory=$MediaDirectory",
    '-p:DebugType=None','-p:DebugSymbols=false')
if ($Slim) { $properties += '-p:FaceNowSlimDistribution=true' }
& "$PSScriptRoot/restore-sdk.ps1"
& $DotNet publish "$repo/src/FaceNow.App/FaceNow.App.csproj" -c Release -r win-x64 --self-contained true -o $publish @properties
if ($LASTEXITCODE -ne 0) { throw 'FaceNow publish failed.' }
if ($Slim) {
    # Optional Agora extensions, unused by FaceNow's external-video RTC path.
    # Keep the RTC engine, codecs, FFmpeg, audio processing and ClearVision result beauty.
    foreach ($name in @('libagora_lip_sync_extension.dll','libagora_spatial_audio_extension.dll',
        'libagora_segmentation_extension.dll',
        'libagora_face_capture_extension.dll','libagora_audio_beauty_extension.dll',
        'libagora_content_inspect_extension.dll','libagora_video_quality_analyzer_extension.dll')) {
        Remove-Item (Join-Path $publish $name) -ErrorAction SilentlyContinue
    }
    # The transitive Windows ML NuGet package also contributes native runtime assets,
    # independently of the WinAppSDK component payload filtered by Directory.Build.targets.
    foreach ($name in @('DirectML.dll','onnxruntime.dll','Microsoft.Windows.AI.MachineLearning.dll',
        'Microsoft.Windows.AI.MachineLearning.Projection.dll')) {
        Remove-Item (Join-Path $publish $name) -ErrorAction SilentlyContinue
    }
}
foreach ($architecture in @('x64','arm64','directshow-x64')) {
    $destination = Join-Path $publish "Camera/$architecture"
    New-Item -ItemType Directory -Force $destination | Out-Null
    Copy-Item "$CameraBuildRoot/$architecture/FaceNow.CameraControl.exe","$CameraBuildRoot/$architecture/FaceNow.CameraSource.dll" $destination
}
Copy-Item "$VcRuntimeDirectory/*.dll" $publish -Force
& "$PSScriptRoot/check-sdk-abi.ps1" -Payload $publish -DotNet $DotNet
Copy-Item "$repo/THIRD_PARTY.md" $publish
$notices = Join-Path $publish 'licenses/native'
New-Item -ItemType Directory -Force $notices | Out-Null
Copy-Item $directShowLicense "$notices/DirectShow-BaseClasses-MIT.txt"
$assets = Get-Content (Join-Path $BuildRoot 'obj/FaceNow.App/project.assets.json') -Raw | ConvertFrom-Json
$packageRoot = $assets.packageFolders.PSObject.Properties.Name | Select-Object -First 1
$sdkVersion = ([xml](Get-Content "$repo/Directory.Build.props" -Raw)).Project.PropertyGroup.XmaxSdkVersion
$sdkPackage = Join-Path $packageRoot "xmax.sdk/$sdkVersion"
$sdkLicenses = Join-Path $sdkPackage 'licenses'
if (!(Test-Path -LiteralPath "$sdkLicenses/LICENSE" -PathType Leaf)) {
    throw 'The released Xmax SDK package is missing its license payload.'
}
Copy-Item "$sdkLicenses/native/*" $notices -Recurse -Force
Copy-Item "$sdkLicenses/THIRD_PARTY.md/THIRD_PARTY_NOTICES.txt" "$notices/XmaxSDK-dependencies.md" -Force
Copy-Item "$sdkLicenses/LICENSE" "$notices/XmaxSDK-MIT.txt" -Force
foreach ($entry in $assets.libraries.PSObject.Properties) {
    if ($entry.Value.type -ne 'package' -or $entry.Name -match 'BuildTools|SDK.NET.Ref|CsWinRT') { continue }
    $package = Join-Path $packageRoot $entry.Value.path
    $licenses = Get-ChildItem $package -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)license|notice' }
    if ($licenses) {
        $destination = Join-Path $publish ('licenses/managed/'+$entry.Name.Replace('/','-'))
        New-Item -ItemType Directory -Force $destination | Out-Null
        $licenses | Copy-Item -Destination $destination
    }
}
$dotnetNotices = Join-Path $publish 'licenses/dotnet'
New-Item -ItemType Directory -Force $dotnetNotices | Out-Null
Get-ChildItem $env:DOTNET_ROOT -File | Where-Object { $_.Name -match '^(LICENSE|ThirdPartyNotices)\.' } | Copy-Item -Destination $dotnetNotices
@'
FaceNow for Windows — portable build

1. Extract the entire ZIP to a local folder on Windows 11.
2. Double-click FaceNow.exe. Keep all DLLs, Assets and Camera folders beside it.
   The .NET, Windows App SDK and Visual C++ app runtimes are included.
3. Sign in with a phone/email verification code or an active Xmax API key.
   Choose your generation key in the account menu, then select your physical camera.
   Security verification uses Microsoft Edge WebView2 Runtime.
4. Start Camera stays on the loading page until RTC connects.
5. To use AI video in another app, open Virtual Camera > Set up camera.
   Windows requests administrator permission for the one-time camera setup.
   Then select the FaceNow virtual camera in the other app. Windows adds a localized camera suffix.

Architecture: x64 application; includes native x64 and ARM64 camera components.
No API Key or user settings are bundled. This is a development preview build.
'@ | Set-Content "$publish/README.txt" -Encoding UTF8
Write-Output "FaceNow executable: $publish/FaceNow.exe"
if ($SkipArchive) { return }
$packages = Join-Path $BuildRoot 'packages'
New-Item -ItemType Directory -Force $packages | Out-Null
$archive = Join-Path $packages "$productId-$version-win-x64.zip"
if (Test-Path -LiteralPath $archive) { throw "Archive already exists: $archive" }
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$source = [IO.Path]::GetFullPath($publish).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$temporary = "$archive.$([Guid]::NewGuid().ToString('N')).tmp"
try {
    $zip = [IO.Compression.ZipFile]::Open($temporary, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in [IO.Directory]::EnumerateFiles($source, '*', [IO.SearchOption]::AllDirectories)) {
            $entry = $file.Substring($source.Length).Replace('\', '/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $file, $entry, [IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
    finally { $zip.Dispose() }
    [IO.File]::Move($temporary, $archive)
}
finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
}
'{0}  {1}' -f (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant(),(Split-Path -Leaf $archive) | Set-Content "$packages/SHA256SUMS" -Encoding UTF8
Write-Output "FaceNow executable: $publish/FaceNow.exe"
Write-Output "FaceNow portable archive: $archive"
