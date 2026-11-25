[CmdletBinding()]
param(
    [ValidateSet('Domestic','Overseas')][string]$Edition = 'Domestic',
    [string]$DotNet = 'C:\dev\dotnet\dotnet.exe',
    [string]$BuildRoot = 'C:\dev\FaceNow-account-tests'
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path $DotNet)) { $DotNet = (Get-Command dotnet -ErrorAction Stop).Source }
$env:DOTNET_ROOT = Split-Path $DotNet
$repo = Split-Path -Parent $PSScriptRoot
$build = $BuildRoot.Replace('\','/').TrimEnd('/') + '/'
& $DotNet run --project "$repo/tests/FaceNow.AccountTests/FaceNow.AccountTests.csproj" -c Release '-p:Platform=x64' "-p:FaceNowBuildRoot=$build" "-p:FaceNowEdition=$Edition"
if ($LASTEXITCODE -ne 0) { throw 'Account tests failed.' }
$identity = [Guid]::NewGuid().ToString('N')
$cache = Join-Path ([IO.Path]::GetTempPath()) ('FaceNow-account-storage-' + $identity)
try {
    foreach ($mode in @('write','read','delete','empty')) {
        & $DotNet run --project "$repo/tests/FaceNow.AccountStorageTests/FaceNow.AccountStorageTests.csproj" -c Release '-p:Platform=x64' "-p:FaceNowBuildRoot=$build" "-p:FaceNowEdition=$Edition" -- $mode $identity $cache
        if ($LASTEXITCODE -ne 0) { throw "Account storage test failed: $mode" }
    }
}
finally {
    # Best-effort cleanup uses the same random target; production credentials are never touched.
    & $DotNet run --project "$repo/tests/FaceNow.AccountStorageTests/FaceNow.AccountStorageTests.csproj" -c Release '-p:Platform=x64' "-p:FaceNowBuildRoot=$build" "-p:FaceNowEdition=$Edition" -- delete $identity $cache
    if (Test-Path $cache) { Remove-Item $cache -Recurse -Force }
}
