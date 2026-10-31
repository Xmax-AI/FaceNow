# Third-party and shared components

- **XmaxSDK**：通过相邻源码工程引用 `Xmax.SDK` 和 `Xmax.SDK.WinUI`；预设目录通过嵌入资源复用。SDK 许可证保存在 `licenses/XmaxSDK-MIT.txt`。原生运行时依赖按 SDK 随附的 notices 一起部署。
- **Agora 4.6.2 / ClearVision**：生成结果美颜使用与 XmaxSDK 相同版本的 Agora 本地媒体图和 ClearVision 扩展，由 FaceNow 独立的 `FaceNow.BeautyWorker.exe` 调用。运行库沿用 SDK 的再分发和 notices；Slim 发布保留 `libagora_clear_vision_extension.dll`。编译所需的 Agora 低层 C++ 头文件和导入库由开发环境提供，不作为 FaceNow 源码再分发。
- **ApiKeyStore**：Windows 凭据适配基于 XmaxSDK 的 MIT 实现，使用 FaceNow 独立的凭据条目。
- **XLab WinUI 界面与会话逻辑**：基于 `Examples/XLabWinUI` 和 `Examples/XLabShared` 的 MIT 源码适配到产品内部，保留同款布局、控件、弹层与动画；使用 FaceNow 命名空间和独立持久化位置，不引用示例程序集。
- **DM Sans**：来自 SDK 示例的字体，构建输出保留 `DMSans-OFL.txt`。
- **FaceNow 应用图标**：复用 macOS FaceNow 当前发行版的黑底白色 Xmax 星标成品，转换为 Windows 多尺寸 ICO；来源见 `assets/README.md`。
- **FaceNow 登录素材**：演示视频和海报复用 macOS `FNUser/Resources/Login`；场景品牌图标及其来源和许可证随应用部署在 `Assets/Login/Scenarios-sources.md` 与 `Assets/Login/Scenarios-Licenses.txt`。
- **登录场景图标着色**：`Assets/Login/Scenarios/Muted` 是上述矢量图标的派生配色，以 `#6B7380` 和界面不透明度复现 macOS 的蒙版着色；原始矢量文件、署名与许可证均保留。
- **Microsoft Edge WebView2 / 腾讯验证码**：安全验证使用 WinUI 提供的 WebView2 控件，按需动态加载腾讯官方 `TJCaptcha.js`，不随应用复制第三方脚本或将账户凭据传入网页。
- **Windows App SDK / Windows SDK BuildTools / .NET**：按所固定依赖版本的许可证和再分发要求使用。
- **Microsoft Windows-Camera**：`native/CameraSource` 改编自 [VirtualCamera 示例](https://github.com/microsoft/Windows-Camera/tree/master/Samples/VirtualCamera)，保留版权声明，使用 FaceNow 独立 CLSID，简化为合成测试源并修正流选择、分配器和帧生成。MIT 许可证见 `licenses/Windows-Camera-MIT.txt`。
- **Windows Implementation Libraries (WIL)**：`native/third_party/wil` 包含 [microsoft/wil](https://github.com/microsoft/wil) 的头文件，供原生媒体源使用。MIT 许可证见 `licenses/WIL-MIT.txt`，构建时不下载依赖。

- **NSIS 3.12**：EXE 安装包使用 [NSIS](https://nsis.sourceforge.io/) 构建，保留官方 `COPYING`，随安装文件置于 `licenses/NSIS-COPYING.txt`；包含其 zlib/libpng 与 LZMA 模块许可证。未修改的对应源码可从 [NSIS 3.12 官方发行目录](https://sourceforge.net/projects/nsis/files/NSIS%203/3.12/) 获取。

原生 SDK、.NET、Windows App SDK 与安装器说明随发行包保留在 `licenses/`；不携带用户的 API Key 或设置。
