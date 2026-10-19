# XmaxCamera

A standalone macOS application that sends Xmax-generated video to **Xmax Virtual Camera**, a native Core Media I/O camera extension.

## Requirements

- macOS 13.0 or later
- Xcode 26 or later, with Swift 6.2 or later
- An Apple Developer team and signing identities that support System Extensions and App Groups
- An Xmax API key for generation; the test pattern works without a key or physical camera

## Open and configure

Open `XmaxCamera.xcodeproj` and select the **XmaxCamera** scheme. SwiftPM resolves the published [XmaxSDK 1.0.0](https://github.com/XingMai/XmaxSDK-MacOS/releases/tag/1.0.0) package; no sibling SDK checkout is required.

In **Signing & Capabilities**, select the **same Team on both targets**:

| Target | Bundle identifier | Purpose |
| --- | --- | --- |
| XmaxCamera | `ai.xmax.camera` | Capture, generation, previews and extension setup |
| XmaxCameraExtension | `ai.xmax.camera.extension` | Virtual camera source and producer sink |

Keep automatic signing enabled. Both targets already declare the sandbox and matching App Group; the host also declares camera access, network access and System Extension installation. If your team requires different identifiers, update the target identifiers, `Shared/CameraConfiguration.swift` and both entitlements together.

Team selection is intentionally left blank in the checked-in project. Machine-specific overrides can optionally live in the ignored `Configuration/Local.xcconfig` file:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

## Run

1. Build the signed **XmaxCamera** scheme.
2. Copy **Xmax Camera.app** from the build products to **/Applications**, then launch that copy. macOS requires this location for extension activation.
3. Click **Install & Enable** and complete the macOS approval flow. Use **Refresh** to check extension status.
4. Click **Send Test Pattern**. In a video application's camera settings, select **Xmax Virtual Camera** and confirm that the color bars and moving white marker appear.
5. Click **Stop**. Enter an API key, select a physical camera and model, enter a **Free Prompt**, then click **Start Generation**. Grant camera access when macOS requests it.

Keep the host running while using the virtual camera. Local preview and generated video appear side by side. Audio uses the meeting application's regular microphone; this project only publishes video.

**Stop** closes camera capture and generation and stops feeding the sink. The extension displays a waiting card instead of retaining the last image indefinitely. The camera stays installed until **Remove** is selected.

The API key is cached in this application's UserDefaults under `xmax.camera.apiKey`, independently of XLab.

## Architecture

```text
Physical camera → XmaxSDK → generated frame callback
                                  ↓
                         latest-frame mailbox
                                  ↓
                  aspect fit → 1280 × 720 NV12 @ 30 fps
                                  ↓
                 CMIO sink → Camera Extension → CMIO source
                                                    ↓
                                          Meeting application
```

- `App/CameraSessionController.swift` owns the SDK lifecycle. The local preview remains mounted while waiting for SDK readiness. Session tokens reject late callbacks after stop or restart.
- `App/VirtualCameraOutput.swift` normalizes frames on a dedicated queue and enqueues retained sample buffers into the CMIO sink. It drops work when the two-buffer queue is full.
- `CameraExtension/` owns the stable virtual device and source/sink streams. Producer and consumer lifecycles are independent. The sink accepts a single producer with the host signing identifier; meeting clients read the source.
- `Shared/` defines the transport contract, bounded mailbox and renderer. The extension uses only system frameworks and has no XmaxSDK dependency.

No additional mirroring is applied to generated frames. Generation dimensions are fitted with black bars, preserving aspect ratio. Source samples use the macOS host clock. Frames older than two seconds are replaced with the waiting card. No App Group file polling or private IPC is used for video transport.

This project is separate from XmaxSDK and XLab. Changes to virtual camera integration belong here.

## Validation

Build without signing to check both targets and extension embedding:

```sh
xcodebuild -project XmaxCamera.xcodeproj -scheme XmaxCamera \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Run hardware-independent tests for the shared media pipeline:

```sh
swift test --scratch-path .build/CoreTests
```

The root Swift package exposes the shared core for tests; the application is built with the Xcode project. Tests cover producer cancellation, concurrent frame handoff, freshness, aspect fit, NV12/BGRA conversion, orientation, black padding, sample timing and allocation limits.

Unsigned builds cannot validate camera extension activation or conference compatibility. After signing and enabling the extension, validate the test pattern, real generation, stop, app exit and restart in the installed Feishu and Tencent Meeting versions. Compatibility with those clients is not yet verified.

## Git workflow

Use `feature/yueting-v<version>` for development, `develop` for integration and `main` for release-ready changes. The initial implementation is on `feature/yueting-v1.0.0`. No remote repository or application release has been created.

## References

- [Apple: Creating a camera extension with Core Media I/O](https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o)
- [Apple WWDC: Create camera extensions with Core Media IO](https://developer.apple.com/videos/play/wwdc2022/10022/)

## License

MIT. See [LICENSE](LICENSE).
