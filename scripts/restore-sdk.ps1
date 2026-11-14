#
#  restore-sdk.ps1
#  FaceNow
#

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$settings = ([xml](Get-Content "$repo/Directory.Build.props" -Raw)).Project.PropertyGroup
$version = $settings.XmaxSdkVersion
$feed = Join-Path $repo '.build/xmax-sdk/packages'
$release = "https://github.com/Xmax-AI/XmaxSDK-Windows/releases/download/$version"
$packages = @{
    "Xmax.SDK.$version.nupkg" = $settings.XmaxSdkPackageSHA256
    "Xmax.SDK.WinUI.$version.nupkg" = $settings.XmaxSdkWinUIPackageSHA256
}

New-Item -ItemType Directory -Path $feed -Force | Out-Null
foreach ($name in $packages.Keys) {
    $destination = Join-Path $feed $name
    $expectedHash = $packages[$name]
    if ((Test-Path -LiteralPath $destination) -and
        (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $expectedHash) {
        continue
    }

    $temporary = Join-Path $feed ([Guid]::NewGuid().ToString('N') + '.download')
    try {
        & curl.exe --fail --location --silent --show-error --connect-timeout 15 --max-time 120 --retry 2 --output $temporary "$release/$name"
        if ($LASTEXITCODE -ne 0) { throw "Could not download $name from $release (curl exit $LASTEXITCODE)." }
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $expectedHash) {
            throw "The GitHub Release checksum does not match for $name."
        }
        Move-Item -LiteralPath $temporary -Destination $destination -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
}
