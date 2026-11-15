# FaceNow for macOS

FaceNow targets macOS 13 and later. Use Xcode 27 for development. Open `FaceNow.xcodeproj` in Xcode and select `FaceNow` for the mainland China edition or `FaceNow-oversea` for the overseas edition. Xcode resolves the pinned XmaxSDK and other Swift packages.

From the macOS directory, build the mainland China edition without Apple Developer signing credentials:

```sh
xcodebuild -project FaceNow.xcodeproj -scheme FaceNow \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/domestic \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  FACENOW_AUDIO_DRIVER_SIGNING_IDENTITY=- build
```

For the overseas edition, use `-scheme FaceNow-oversea` and `-derivedDataPath .build/overseas`. Both schemes produce an app named `FaceNow.app`.

To exercise the system camera extension, use an Apple Developer team authorized to sign the app and its nested targets, with matching bundle identifiers, App Groups, and provisioning profiles. See the [virtual microphone driver notes](VirtualMicrophoneDriver/README.md) for its packaging requirements.

Run `swift test` from this directory to test the shared camera, audio, networking, and account code.

Third-party notices include [DM Sans](App/Fonts/DMSans-OFL.txt), the [login scenario artwork](Modules/FNUser/Resources/Scenarios-Licenses.txt), and the [Core Audio driver sample](VirtualMicrophoneDriver/LICENSE-Apple.txt).
