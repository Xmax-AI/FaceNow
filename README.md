# FaceNow

FaceNow 的 macOS 和 Windows 原生应用。

- **macOS** 在 Xcode 中打开 [macos/XmaxCamera.xcodeproj](macos/XmaxCamera.xcodeproj)。Xcode 会解析已锁定的 XmaxSDK Swift Package。
- **Windows** 打开 [windows/FaceNow.sln](windows/FaceNow.sln)。首次构建前运行 `windows/scripts/restore-sdk.ps1` 下载官方 XmaxSDK NuGet 包。完整步骤见 [Windows 构建说明](windows/README.md)。
