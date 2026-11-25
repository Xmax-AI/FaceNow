#
#  check-sdk-abi.ps1
#  FaceNow
#

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Payload,
    [string]$DotNet = 'C:\dev\dotnet\dotnet.exe'
)

$ErrorActionPreference = 'Stop'
if (!(Test-Path $DotNet)) { $DotNet = (Get-Command dotnet -ErrorAction Stop).Source }
$repo = Split-Path -Parent $PSScriptRoot
$version = ([xml](Get-Content "$repo/Directory.Build.props" -Raw)).Project.PropertyGroup.XmaxSdkVersion
foreach ($name in @('XmaxSDK.dll', 'agora_rtc_sdk.dll', 'libagora_clear_vision_extension.dll', 'Xmax.VideoBeautyWorker.exe')) {
    if (!(Test-Path -LiteralPath (Join-Path $Payload $name) -PathType Leaf)) {
        throw "The payload is missing SDK runtime file $name."
    }
}
$nativeVersion = (Get-Item -LiteralPath (Join-Path $Payload 'XmaxSDK.dll')).VersionInfo.ProductVersion
if ($nativeVersion -ne $version) { throw "Native SDK version '$nativeVersion' does not match required SDK version '$version'." }
# The probe's ClientConfig layout matches version 2 of the SDK C ABI.
$abi = 2
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("FaceNow-SdkAbi-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $probe = Join-Path $scratch 'check-sdk-abi.cs'
    Copy-Item -LiteralPath "$PSScriptRoot/check-sdk-abi.cs" -Destination $probe
    & $DotNet run --file $probe --tl:off -- $Payload $abi
    if ($LASTEXITCODE -ne 0) {
        throw "The packaged DLL failed the XmaxSDK C ABI $abi check. Rebuild with the matching released Xmax SDK packages."
    }
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
