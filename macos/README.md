# FaceNow for macOS

## Prerequisites

- Xcode 27 with the macOS SDK. For terminal builds, select Xcode 27 under **Xcode > Settings > Locations > Command Line Tools**.
- Git and network access to download Swift packages and their binary dependencies.
- Python 3 at `/usr/bin/python3`, which the Xcode build scripts use to package the virtual microphone driver.

FaceNow targets macOS 13 and later.

<br>

## Get the source code

```sh
git clone https://github.com/Xmax-AI/FaceNow.git
cd FaceNow/macos
```

Run the remaining commands from `macos`.

<br>

## Choose a build scheme

| Edition | Xcode scheme | Derived data directory |
| --- | --- | --- |
| Mainland China | `FaceNow` | `.build/domestic` |
| Overseas | `FaceNow-oversea` | `.build/overseas` |

Both schemes produce `FaceNow.app`. Use separate derived data directories to keep the builds independent.

<br>

## Resolve Swift package dependencies

Xcode resolves the packages automatically when you open `FaceNow.xcodeproj`. The project uses the published [Xmax SDK 1.1.6](https://github.com/Xmax-AI/XmaxSDK-MacOS/releases/tag/1.1.6), with no local SDK checkout required. For a terminal build, resolve the dependencies first with the command below. Package versions and revisions are recorded in the project's [Package.resolved](FaceNow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved).

The terminal commands use the Mainland China scheme. For the overseas edition, substitute its scheme and derived data directory in both commands.

```sh
xcodebuild -resolvePackageDependencies \
  -project FaceNow.xcodeproj -scheme FaceNow \
  -derivedDataPath .build/domestic \
  -onlyUsePackageVersionsFromResolvedFile
```

<br>

## Build FaceNow

In Xcode, open `FaceNow.xcodeproj`, select your edition’s scheme and **My Mac**, then choose **Product > Build**.

For a local compilation check without Apple Developer signing credentials, run the Debug build from the terminal.

```sh
xcodebuild -project FaceNow.xcodeproj -scheme FaceNow \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/domestic \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  FACENOW_AUDIO_DRIVER_SIGNING_IDENTITY=- build
```

The command writes the app to `.build/domestic/Build/Products/Debug/FaceNow/FaceNow.app`. If you use the overseas scheme and directory, the app is under `.build/overseas/Build/Products/Debug/FaceNow-oversea/FaceNow.app`.
