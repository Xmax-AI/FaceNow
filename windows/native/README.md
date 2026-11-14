# Native camera output

Windows 11 software virtual camera prototype, adapted from Microsoft's MIT VirtualCamera sample.

- `CameraSource/`: native COM activation, source, stream and 1280×720 RGB32/NV12 output with a plain #F1F3F4 waiting canvas.
- `CameraControl.cpp`: architecture-matched helper for install, enable, remove, status and frame verification.
- `Identity.h`: shared fixed CLSID and friendly name.
- `third_party/wil/`: vendored WIL headers; licenses are in `../licenses`.

Build on Windows with Visual Studio Desktop C++ tools (including ARM64 tools) and Windows SDK 10.0.26100.0:

```powershell
./scripts/build-camera.ps1
./scripts/verify-camera.ps1 -Architecture arm64
# After Install & Enable in the app:
./scripts/verify-camera.ps1 -Architecture arm64 -Installed
```

Defaults: VS at `C:/dev/VisualStudio2022`, output `C:/dev/FaceNow-camera/{x64,arm64}`.
`run.ps1` copies both helper/source pairs into the app's `Camera` directory.
The helper and source architecture must match the OS Frame Server, independently of the app process architecture.

The source receives BGRA from the app through a per-device named pipe.
`RemoteCameraPump` uses the independent SDK callback and a one-packet queue; `FramePublisher` serves only the latest fresh frame.
On stop, disconnection or 1500 ms without new content, output falls back to a plain #F1F3F4 canvas matching macOS.
The local end-to-end check is `scripts/run.ps1 -VerifyRelay`; see [frame transport](../Docs/FrameTransport.md).
Cloud generation and meeting reception remain separate acceptance items.
Full installer, upgrades, reboot recovery, long running output and meeting compatibility remain separate acceptance items.

See [registration and commands](Registration.md) for permissions, lifecycle and precise status semantics.
