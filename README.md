# FaceNow for Windows

基于 C# / .NET 10 / WinUI 3，与 `XmaxSDK` 平级开发。当前界面按 XLab WinUI 对齐：同款白色首页、Logo、标题、棋盘格启动区、顶部工具栏、双视频会话页、四种模式、圆形参考图、Free Prompt、API Key 弹层与 450 ms 页面过渡。进程和窗口名称保留 FaceNow。

```text
Windows/
  XmaxSDK/
  FaceNow/
```

已接入 SDK 摄像头、显式启动/停止生成、参考图选择、上传流程、自由提示词、统计和凭据保存。Windows 11 虚拟摄像头已实现注册、SDK 远端视频回调接入和 1080p 跨进程输出，停止或断流时切回占位。真实云端到会议的完整链路、会议兼容、录制和托盘仍待验收或实现。已提供自包含 EXE 安装器。关闭窗口停止并释放 AI 会话；卸载应用时移除当前用户的虚拟摄像头设备。

首页右上角保留 Virtual Camera 入口，面板只显示 Setup needed（需要设置）、Ready to use（已设置好）和 Unavailable（暂不可用）。不可用时在正文解释原因和下一步，检查与安装仅显示短暂进度；生成页面不显示此入口。首次使用才显示 Set up camera（Windows UAC 提权仅用于安装组件）；检查与权限设置收在帮助中。设备是否可用仍依据 symbolic link 枚举确认。默认使用 X2.1，采集与生成基准为 1920×1080，启用动态画质调档。虚拟摄像头输出固定为 1920×1080，同尺寸 BGRA 帧按行直接复制；回传尺寸变化时等比铺满、居中裁剪，不拉伸或补黑边；空闲时为与 macOS 一致的纯色灰底（RGB 241/243/244，#F1F3F4）。SDK 回调已接入，传帧通道以本地合成帧验证，真实云端生成未在本次运行。Windows 注册流程见 [原生组件注册说明](native/Registration.md)。

## 国内、海外、美颜与水印

同一套代码构建 `Domestic`（固定简体中文、国内服务）和 `Overseas`（固定英文、海外服务）。语言不随 Windows 切换。`ProductProfile` 统一账户/生成 API、预设 CDN、浏览器链接、验证码语言和存储位置。海外版安装为 FaceNow Overseas，与国内版分别保存凭据、缓存、摄像头选择和美颜参数；旧国内凭据位置保留。两版共享系统虚拟摄像头，同一时间只允许一版发布，另一版仍可生成和预览。卸载其中一版时，若另一版仍安装则保留设备。

国内登录页只显示“手机号 / API Key”，海外登录页只显示“邮箱 / API Key”，均为等宽双段切换。登录成功即清空本地表单、验证错误、渠道草稿和验证码倒计时，退出后恢复本版默认入口；已验证的账户凭据与表单输入分别管理。

生成页增加美颜开关，以及磨皮、美白、锐化、红润四项调节；默认关闭，参数为 50% / 50% / 0% / 0%，与 macOS 一致。美颜只处理生成结果，使用独立进程中的 Agora ClearVision 本地媒体图，不改变上传的实体摄像头画面。预览和虚拟输出使用同一处理结果。效果故障只关闭美颜并恢复原视频；IPC、首帧和处理等待均有界，不结束生成会话。

生成预览左上角显示 `✦ FaceNow`，右上角显示“AI 生成”或“AI Generation”。虚拟输出在等比 Fill 到 1920×1080 后再合成同款水印，因此会议软件收到的像素也包含标识；预览仅镜像视频，标识保持正常方向。当前输出仍为 30 fps，不包含 macOS 的插帧功能。

```powershell
# 先构建本地美颜和最终画布组件；头文件需包含 IAgoraService / NGIAgora* 及配套 aosl
./scripts/build-media.ps1 -AgoraHeaders C:/deps/agora-4.6.2/low-level/include
# 两个版本必须使用不同 BuildRoot
./scripts/run.ps1 -Edition Domestic -BuildRoot C:/dev/FaceNow-domestic
./scripts/run.ps1 -Edition Overseas -BuildRoot C:/dev/FaceNow-overseas
# 离线检查真实美颜像素、输出水印、故障恢复、设置和区域隔离
./scripts/test-media.ps1 -Edition Domestic -FullHd
# 同时检查并发布两版，要求全新的 BuildRoot
./scripts/build-editions.ps1 -BuildRoot C:/dev/FaceNow-editions-new -NativeDirectory <SDK原生目录> -DependencyNoticesDirectory <原生依赖说明目录>
```

美颜构建需要 Visual Studio C++、与 SDK 相同的 Agora 4.6.2 x64 DLL、导入库及低层头文件（含 `aosl`）；普通 RTC SDK 头文件包可能缺少这些接口。`build-media.ps1` 可用 `-AgoraRoot` / `-AgoraHeaders` 指定，产物默认在 `C:/dev/FaceNow-media`，运行/发布可用 `-MediaDirectory` 覆盖。发布会检查 RTC 和 ClearVision DLL 哈希，拒绝混装。两版安装包分别为 `FaceNow-Setup-1.0.0.exe` 和 `FaceNowOverseas-Setup-1.0.0.exe`。

## 运行

正常启动先进入账户流程：手机号验证码、邮箱验证码和 API Key 登录按构建版本使用与 macOS 相同的国内或海外平台接口。保存的账户会先显示缓存首页并在后台验证，验证完成前不能生成。旧版保存的 API Key 只在服务确认有效记录及所属用户后迁移；登录成功后通过账户菜单选择或显式创建生成 Key，不会自动创建 Key。登录架构及验收边界见 [账户模块](Docs/Accounts.md)。

需要 .NET 10 SDK、相邻 XmaxSDK 源码、带摄像头和 Agora 支持的原生 SDK 及匹配运行依赖。安全验证弹层使用 Microsoft Edge WebView2 Runtime，缺失时给出安装提示。首版目标为 Windows 11 x64；目前也在 Windows 11 ARM 虚拟机中以 x64 仿真验证。

```powershell
./scripts/run.ps1
# 首页预览：不打开摄像头、不读取保存的 Key、不创建生成会话
./scripts/run.ps1 -Preview
# 直接查看双视频会话页
./scripts/run.ps1 -PreviewSession
./scripts/run.ps1 -PreviewCameraSetup
# 登录页预览：使用模拟账户，不读写真实凭据、不请求账户服务
./scripts/run.ps1 -PreviewLogin
# 账户逻辑、隔离凭据跨进程检查与原生登录流程
./scripts/verify-accounts.ps1
# 生成失败、积分耗尽与清理并发回归（模拟事件，不调用原生 SDK 或云服务）
./scripts/test-generation.ps1
# 在自包含发布目录中检查缓存/普通登录后的真实弹窗退出、再次登录和关闭；无截图
./scripts/test-signout.ps1 -AppDirectory C:/dev/FaceNow-release/publish/FaceNow-1.0.0-win-x64
# 按 macOS 尺寸规则检查登录布局并生成各窗口/输入状态截图
./scripts/verify-login-layout.ps1
# 编译并验证界面、帧显示、缺 Key 拦截和隔离的凭据恢复
./scripts/run.ps1 -Verify
# 已安装并启用摄像头后，通过系统管线验证虚拟摄像头读帧
./scripts/run.ps1 -NoBuild -VerifyCamera
# 本地合成视频经过完整跨进程/系统管线，检查断流与重启
./scripts/run.ps1 -NoBuild -VerifyRelay
```

默认 .NET 位于 `C:/dev/dotnet/dotnet.exe`，不存在则查找 PATH；原生 SDK 默认位于 `C:/dev/XmaxSDK-build/Sources/XmaxSDK/RelWithDebInfo`。使用 `-DotNet`、`-NativeDirectory`、`-XmaxSdkRoot`、`-BuildRoot` 覆盖。构建产物放在 Windows 本地 `C:/dev/FaceNow-build`，避免在共享目录运行 XAML 编译。

虚拟摄像头组件需先用 Visual Studio C++ 工具构建：`./scripts/build-camera.ps1`，默认生成 x64 / ARM64 两套到 `C:/dev/FaceNow-camera`。之后 `run.ps1` 自动复制到应用的 `Camera/{architecture}`，可用 `-CameraBuildRoot` 覆盖路径。Frame Server 使用系统原生架构：ARM64 Windows 使用 ARM64 媒体源，即使主程序以 x64 仿真运行。缺少组件时仍能打开主程序，并显示 Not installed。

macOS + Parallels：

```sh
bash scripts/run.sh
bash scripts/run.sh -Preview
bash scripts/run.sh -PreviewSession
bash scripts/run.sh -PreviewCameraSetup
bash scripts/run.sh -Verify
# 已编译后直接打开
bash scripts/run.sh -NoBuild
```

默认使用运行中的 `Windows 11` 虚拟机、`\\Mac\FaceNowSource` 源码共享与 `\\Mac\XmaxSDK` SDK 共享。可用 `FACENOW_WINDOWS_VM`、`FACENOW_WINDOWS_SOURCE`、`XMAX_WINDOWS_SOURCE` 覆盖。FaceNowSource 避免与 FaceNow 安装镜像重名。

## 发布免安装版

在 Windows 中运行 `scripts/publish.ps1 -DependencyNoticesDirectory <原生依赖说明目录>`，使用新的本地 `-BuildRoot`。脚本生成 `publish/FaceNow-版本-win-x64/FaceNow.exe` 和 `packages/FaceNow-版本-win-x64.zip`，包含 .NET、WinUI、Visual C++ 运行库、原生 SDK、两种架构的摄像头组件及依赖说明。解压整个 ZIP 后运行 FaceNow.exe，保留同目录的 DLL、Assets 和 Camera；无需安装开发环境。该包不携带用户 API Key，摄像头注册仍由首次使用时的 Set up camera 完成。

## EXE 安装包

```powershell
./scripts/build-installer.ps1 -BuildRoot C:/dev/FaceNow-installer-new -NativeDirectory C:/dev/XmaxSDK-release-1.1.0/Sources/XmaxSDK/Release -NsisCompiler C:/dev/FaceNow-tools/nsis-3.12/makensis.exe -DependencyNoticesDirectory <原生依赖说明目录>
```

使用官方 NSIS 3.12 或更新版本，编译器目录须包含 `COPYING`。`-NativeDirectory` 必须匹配相邻 SDK 源码的 `VERSION`，发布脚本会检查 DLL 版本，防止 C# 与 C++ SDK 混装。产物为 `packages/FaceNow-Setup-版本.exe`，单个文件即可分发，运行库全部内置，无需额外下载 .NET 或 WinUI。默认安装到当前用户的 `%LocalAppData%/Programs/FaceNow`，创建桌面和开始菜单快捷方式，并提供系统卸载入口；首次使用虚拟摄像头仍由应用中的 Set up camera 完成。

安装器采用 `publish.ps1 -Slim -SkipArchive` 构建：在 WinAppSDK 生成文件和 WinRT 注册前排除未使用的 AI、ML、Search、Widgets 组件，并去掉额外携带的 Windows ML 原生文件和未使用的 Agora 扩展。保留 RTC 主体、编解码、音频处理、VC、.NET、WinUI 和 x64/ARM64 摄像头组件，不启用可能破坏反射绑定的 .NET 裁剪。后续增加本地 AI 或 RTC 扩展功能时需重新检查这些清单。

安装和卸载会阻止替换仍在运行的 FaceNow。卸载删除程序及快捷方式、移除当前用户的虚拟摄像头，但保留凭据和缓存；机器级摄像头 COM 组件为系统共享副本，保留在 ProgramData。维护或隔离验证时可使用卸载器的 `/KEEP_CAMERA` 参数保留当前虚拟摄像头。卸载只删除构建清单中的文件，不递归删除用户放入安装目录的其他文件。

## 使用

1. 使用手机号、邮箱验证码或有效 API Key 登录。首页账户菜单提供当前账户、积分、生成 Key 选择和退出；没有可用 Key 时可显式创建 FaceNow Key。账户凭据安全保存在当前 Windows 用户的凭据管理器中。
2. 首页顶部选择摄像头，点击 Start Camera，首页显示 Starting…，使用首张 Character Swap 预设启动摄像头和生成；RTC 连接成功后才进入生成页并开始计时。缺少 Key 时打开账户菜单，缺少摄像头时打开选择面板，启动失败会留在首页显示错误。
3. 会话页切换 Character Swap、Virtual Try-On、Style Transfer、Free Prompt。切换分类不自动生成；选择参考图或提交提示词才更新条件。
4. Upload 支持选择本地参考图；Free Prompt 支持上传、移除参考图与提示词提交。服务上传和真实生成需要后续使用有效 Key 验收。
5. 顶部可控制统计显示，Stop Session 返回首页并关闭会话。FaceNow 不采集麦克风，会议软件中的麦克风由用户独立选择。
6. 打开 Virtual Camera，首次使用按提示 Set up camera。点击 Start Camera 后，在会议或直播软件中选择 FaceNow - Xmax Virtual Camera。生成开始后自动传输远端视频，Stop Session 后切回占位；生成期间安装成功也会接入已有会话。此流程已实现，真实云端与会议客户端尚需完整验收。

`-Preview` 中 Start 按钮显示 Preview UI，点击只切换页面，不创建摄像头或生成会话；仍可通过 HTTPS 加载缩略图。`-PreviewCameraSetup` 打开可交互的首次摄像头设置演示：Setup needed → 权限步骤模拟 → Setting up camera… → Ready to use，支持取消与 Restart setup preview。此模式不启动真实安装、不读写 API Key、不改动摄像头注册，权限步骤明确标为模拟，不是 Windows UAC 弹窗。`-PreviewLogin` 使用内存中的模拟账户，可用模拟 Key `uk-facenow-isolated-preview` 查看登录后的首页，界面明确显示模拟说明。`XMAX_API_KEY` 仍供显式 SDK 冒烟诊断使用，普通启动的账户流程不使用它绕过身份验证或覆盖账户选择。真实生成使用当前构建版本的区域服务，可能按服务规则计费；默认验收不执行真实生成。

FaceNow 的账户凭据保存在国内版 `XMAX.AI/FaceNow/Account` 或海外版 `XMAX.AI/FaceNowOverseas/Account`，包含明确的凭据类型及所选 Key 的记录 ID；普通磁盘缓存只保存账户资料及凭据摘要。旧版 `XMAX.AI/FaceNow/ApiKey` 在验证并迁移成功后清空。退出先停止生成，再清理账户凭据与缓存，保留虚拟摄像头安装。摄像头选择和缩略图缓存使用 FaceNow 独立位置，不读写 XLab 的用户设置。

## 工程边界

- `src/FaceNow.App`：基于 XLab WinUI 适配的窗口、控件、UI 调度、缩略图与冒烟验证。
- `src/FaceNow.App/User`：原生登录页、表单状态与验证码安全验证；窗口协调首页、账户菜单及生成退出。
- `src/FaceNow.Core/User`：账户模型、接口与应用级 UserRepository，独立于 WinUI、HTTP 和 Windows 凭据实现。
- `src/FaceNow.Windows/Network`：国内账户 HTTP 契约，按请求设置认证、严格校验响应并限制响应大小。
- `src/FaceNow.Windows/Studio`：整理到产品内部的会话 ViewModel、串行条件更新、上传与预设逻辑。
- `src/FaceNow.Windows/Security`：FaceNow 独立的 Windows 凭据管理器接入。
- `src/FaceNow.Core`：与 UI 框架无关的虚拟输出契约。
- `src/FaceNow.Windows/VirtualCamera`：设备管理、SDK 包所有权与后台队列、受限命名管道最新帧发布。
- `native/CameraSource`：基于微软示例适配的 COM 媒体源，接收 BGRA，提供 1080p RGB32/NV12 和占位图。
- `native/CameraControl.cpp`：架构匹配的组件安装、设备注册、移除、查询和帧读取辅助程序。

运行时只通过公开接口依赖 `Xmax.SDK` 和 `Xmax.SDK.WinUI`，不引用 XLab 示例程序集。界面与会话代码保留 MIT 来源声明，由 FaceNow 自身维护；后续 XLab 修改不会自动改变产品界面。

LocalVideo 使用 SDK 预览；生成结果从独立媒体回调进入统一处理管线，美颜后分别交给预览邮箱和虚拟输出合成器。[传帧实现与协议](Docs/FrameTransport.md) 说明会话隔离、权限和断流行为。[完整架构](Docs/Architecture.md) 记录后续 MF / IPC / Windows 10 扩展。

## 验收输出

`-Verify` 运行隔离登录流程、界面、合成帧、旧 SDK 缺 Key 拦截和四个独立进程的凭据保存/恢复/修改/删除检查。`scripts/verify-accounts.ps1` 额外执行账户逻辑及 HTTP 契约回归，以及随机隔离账户条目的跨进程保存/恢复/清理检查。测试不会改写用户的 FaceNow 凭据或发送真实验证码。原始报告与截图位于 `.build/verification/`，独立账户流程报告位于 `.build/account-verification/`：

- `aligned-landing.png`：首页。
- `aligned-session.png`：双视频与形象选择页。
- `aligned-free-prompt.png`：Free Prompt。
- `virtual-camera-ai-relay.png`：本地合成帧通过系统虚拟摄像头后的实际截图。
- `smoke-test-*.json`：各检查报告。

详细结果见 [验证记录](Docs/Verification.md)。这些验证不代表真实摄像头、云端生成、上传或会议兼容性已经通过。
