#
#  prepare-webview2.ps1
#  FaceNow
#

[CmdletBinding()]
param([string]$InstallerPath = 'C:\dev\FaceNow-tools\WebView2\MicrosoftEdgeWebview2Setup.exe')
$ErrorActionPreference = 'Stop'

function Assert-MicrosoftInstaller([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)CN=Microsoft Corporation(,|$)') {
        throw 'The WebView2 bootstrapper must have a valid Microsoft Corporation signature.'
    }
}

if (!(Test-Path -LiteralPath $InstallerPath)) {
    $parent = Split-Path -Parent $InstallerPath
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = Join-Path $parent ([Guid]::NewGuid().ToString('N') + '.exe')
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile $temporary -TimeoutSec 120
        Assert-MicrosoftInstaller $temporary
        Move-Item -LiteralPath $temporary -Destination $InstallerPath
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}
Assert-MicrosoftInstaller $InstallerPath
Write-Output (Resolve-Path -LiteralPath $InstallerPath).Path
