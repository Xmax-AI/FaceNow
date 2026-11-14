<p align="center">
  <img src="./docs/assets/facenow-banner.png" alt="FaceNow. Your New Look For every camera moment" width="880">
</p>

Introducing FaceNow, a desktop app that lets you bring a new look to video calls and live streams through a virtual camera. FaceNow leverages Xmax’s video editing model to support real-time video transformation, letting you become a whole new character, switch up your outfit, and more, with specific reference images and prompts. Now that it’s open-source, you can build novel experiences on top of it for your own lawful use cases.

## 从源码构建

- **macOS** 在 Xcode 中打开 [macos/XmaxCamera.xcodeproj](macos/XmaxCamera.xcodeproj)。Xcode 会解析已锁定的 XmaxSDK Swift Package。
- **Windows** 打开 [windows/FaceNow.sln](windows/FaceNow.sln)。首次构建前运行 `windows/scripts/restore-sdk.ps1` 下载官方 XmaxSDK NuGet 包。完整步骤见 [Windows 构建说明](windows/README.md)。
