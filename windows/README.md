# FaceNow for Windows

## Prerequisites

- Windows 11 with Git and PowerShell. Build from a local Windows drive.
- .NET 10 SDK. The required SDK version is recorded in [global.json](global.json).
- Visual Studio or Visual Studio Build Tools with **Desktop development with C++**, the x64 MSVC compiler, and Windows SDK 10.0.26100.0.
- Network access to GitHub Releases and NuGet.org.

<br>

## Get the source code

```powershell
git clone https://github.com/Xmax-AI/FaceNow.git
Set-Location .\FaceNow\windows
```

Run the remaining commands from the `windows` directory.

<br>

## Restore dependencies

```powershell
.\scripts\restore-sdk.ps1
```

This downloads the Xmax SDK packages and verifies their SHA-256 checksums against [Directory.Build.props](Directory.Build.props). The app build restores the remaining NuGet packages using [NuGet.Config](NuGet.Config).

<br>

## Build the native video compositor

The compositor adds the FaceNow watermark to generated video. In PowerShell, locate the Visual Studio installation with the x64 C++ tools and build the compositor.

```powershell
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
.\scripts\build-media.ps1 -VisualStudio $visualStudio -BuildRoot "$PWD\.build\media"
```

<br>

## Build FaceNow

Use the same compositor for both editions and a separate build directory for each. Run the command for the edition you want to build.

| Edition | Script option | Build directory |
| --- | --- | --- |
| Mainland China | `Domestic` | `.build\domestic` |
| Overseas | `Overseas` | `.build\overseas` |

```powershell
.\scripts\run.ps1 -Edition Domestic -BuildRoot "$PWD\.build\domestic" -MediaDirectory "$PWD\.build\media" -BuildOnly
.\scripts\run.ps1 -Edition Overseas -BuildRoot "$PWD\.build\overseas" -MediaDirectory "$PWD\.build\media" -BuildOnly
```

Each command builds a Release x64 app and prints the path to `FaceNow.exe`. The virtual camera helpers are built separately. See the [native camera guide](native/README.md).
