# FaceNow for Windows

基于 C# / .NET 10 / WinUI 3。当前界面按 XLab WinUI 对齐：同款白色首页、Logo、标题、棋盘格启动区、顶部工具栏、双视频会话页、五种模式、圆形参考图、Free Prompt、API Key 弹层与 450 ms 页面过渡。进程和窗口名称保留 FaceNow。

已接入 SDK 摄像头、显式启动/停止生成、参考图选择、上传流程、自由提示词、统计和凭据保存。虚拟摄像头接收 SDK 远端视频，按所选比例跨进程输出，停止或断流时切回占位。Windows 11 使用 Media Foundation，Windows 10 x64 使用 [DirectShow](native/DirectShow/README.md)。真实云端到会议的完整链路、会议兼容、录制和托盘仍待验收或实现。已提供自包含 EXE 安装器。关闭窗口停止并释放 AI 会话。

首页右上角保留 Virtual Camera 入口，面板只显示 Setup needed（需要设置）、Ready to use（已设置好）和 Unavailable（暂不可用）。不可用时在正文解释原因和下一步，检查与安装仅显示短暂进度；生成页面不显示此入口。首次使用才显示 Set up camera（Windows UAC 提权仅用于安装组件）；检查与权限设置收在帮助中。设备是否可用仍依据 symbolic link 枚举确认。默认使用 X2.1，采集与生成基准为 1920×1080，启用动态画质调档。虚拟摄像头在生成会话中使用首页所选比例的尺寸。回传画面等比铺满输出画布，比例不同时居中裁剪。同尺寸 BGRA 帧按行复制。空闲时显示纯色灰底（RGB 241/243/244，#F1F3F4）。SDK 回调已接入，传帧通道以本地合成帧验证，真实云端生成未在本次运行。Windows 注册流程见 [原生组件注册说明](native/Registration.md)。

## 国内、海外、美颜与水印

同一套代码构建 `Domestic`（固定简体中文、国内服务）和 `Overseas`（固定英文、海外服务）。语言不随 Windows 切换。`ProductProfile` 统一账户/生成 API、预设 CDN、浏览器链接、验证码语言和存储位置。海外版安装为 FaceNow Overseas，与国内版分别保存凭据、缓存、摄像头选择和美颜参数；旧国内凭据位置保留。两版共享系统虚拟摄像头，同一时间只允许一版发布，另一版仍可生成和预览。卸载其中一版时，若另一版仍安装则保留设备。

国内登录页只显示“手机 / API Key”，海外登录页只显示“邮箱 / API Key”，均为等宽双段切换。登录成功即清空本地表单、验证错误、渠道草稿和验证码倒计时，退出后恢复本版默认入口；已验证的账户凭据与表单输入分别管理。

生成页增加美颜开关，以及磨皮、美白、锐化、红润四项调节；默认开启，四项强度为 0，与 macOS SDK 一致。已有用户保存的设置继续保留。美颜只处理生成结果，调用 XmaxSDK 封装的美颜接口，由 SDK 管理独立进程中的 Agora ClearVision 本地媒体图，不改变上传的实体摄像头画面。预览和虚拟输出使用同一处理结果。效果故障只关闭美颜并恢复原视频；IPC、首帧和处理等待均有界，不结束生成会话。

生成预览左上角显示 `✦ FaceNow`，右上角显示“AI 生成”或“AI Generation”。虚拟输出等比铺满所选尺寸后再合成同款水印，因此会议软件收到的像素也包含标识；预览仅镜像视频，标识保持正常方向。当前输出仍为 30 fps，不包含 macOS 的插帧功能。

```powershell
# 构建 FaceNow 最终画布组件；美颜由 XmaxSDK 原生分发提供
./scripts/build-media.ps1
# 两个版本必须使用不同 BuildRoot
./scripts/run.ps1 -Edition Domestic -BuildRoot C:/dev/FaceNow-domestic
./scripts/run.ps1 -Edition Overseas -BuildRoot C:/dev/FaceNow-overseas
```

Windows 版通过 NuGet 引用 GitHub Releases 上的 [XmaxSDK](https://github.com/Xmax-AI/XmaxSDK-Windows/releases)。`Directory.Build.props` 固定 SDK 版本及下载校验值。运行、测试和发布脚本自动下载两个 SDK 包并校验 SHA-256，由 NuGet 将原生 DLL、Agora 和美颜 worker 放入产物。直接使用 Visual Studio 或 `dotnet build` 前，先运行 `./scripts/restore-sdk.ps1`。`build-media.ps1` 构建 FaceNow 的水印画布组件，产物默认在 `C:/dev/FaceNow-media`，可用 `-MediaDirectory` 覆盖。

## 运行

正常启动先进入账户流程：手机号验证码、邮箱验证码和 API Key 登录按构建版本使用与 macOS 相同的国内或海外平台接口。保存的账户会先显示缓存首页并在后台验证，验证完成前不能生成。旧版保存的 API Key 只在服务确认有效记录及所属用户后迁移；登录成功后通过账户菜单选择或显式创建生成 Key，不会自动创建 Key。

需要 .NET 10 SDK。安全验证弹层使用 Microsoft Edge WebView2 Runtime。EXE 安装器会尝试联网补装缺失的 Runtime，失败时继续安装 FaceNow。登录时如缺少 Runtime，用户可在弹窗中前往微软官网下载，或切换到 API Key 登录。安装器支持 Windows 10 2004 及以上版本（x64）和 Windows 11（x64 或 ARM64 上的 x64 仿真）。

```powershell
./scripts/run.ps1
# 首页预览：不打开摄像头、不读取保存的 Key、不创建生成会话
./scripts/run.ps1 -Preview
# 直接查看双视频会话页
./scripts/run.ps1 -PreviewSession
./scripts/run.ps1 -PreviewCameraSetup
# 登录页预览：使用模拟账户，不读写真实凭据、不请求账户服务
./scripts/run.ps1 -PreviewLogin
# 编译并验证界面、帧显示、缺 Key 拦截和隔离的凭据恢复
./scripts/run.ps1 -Verify
# Windows 11 已安装并启用摄像头后，通过 Frame Server 验证读帧
./scripts/run.ps1 -NoBuild -VerifyCamera
# Windows 11 本地合成视频经过 Frame Server，检查断流与重启
./scripts/run.ps1 -NoBuild -VerifyRelay
```

默认 .NET 位于 `C:/dev/dotnet/dotnet.exe`，不存在则查找 PATH。使用 `-DotNet` 和 `-BuildRoot` 覆盖。构建产物放在 Windows 本地 `C:/dev/FaceNow-build`，避免在共享目录运行 XAML 编译。

虚拟摄像头组件需先用 Visual Studio C++ 工具构建：`./scripts/build-camera.ps1 -DirectShowBaseClasses C:/dev/baseclasses`，默认将 Media Foundation 的 x64、ARM64 组件和 DirectShow 的 x64 组件输出到 `C:/dev/FaceNow-camera`。之后 `run.ps1` 自动复制到应用的 `Camera` 目录，可用 `-CameraBuildRoot` 覆盖路径。ARM64 Windows 11 的 Frame Server 使用 ARM64 媒体源，主程序以 x64 仿真运行。缺少组件时仍能打开主程序，并显示 Not installed。

## 使用

1. 使用手机号、邮箱验证码或有效 API Key 登录。首页账户菜单提供当前账户、积分、生成 Key 选择和退出；没有可用 Key 时可显式创建 FaceNow Key。账户凭据安全保存在当前 Windows 用户的凭据管理器中。
2. 首页顶部选择摄像头，点击 Start Camera，首页显示 Starting…，使用首张 Character Swap 预设启动摄像头和生成；RTC 连接成功后才进入生成页并开始计时。缺少 Key 时打开账户菜单，缺少摄像头时打开选择面板，启动失败会留在首页显示错误。
3. 会话页切换 Character Swap、Virtual Try-On、Style Transfer、Virtual Summon、Free Prompt。切换分类不自动生成；选择参考图或提交提示词才更新条件。
4. 内置参考图与 macOS `20261030` 预设一致：角色替换 19 项、虚拟试衣 12 项、风格转换 8 项、虚拟召唤 8 项。召唤前两项为小狗、小鼠的纯提示词，其余 6 项带图；缩略图和生成使用同一张原图，预设各自保留匹配的中英文提示词。帽子、眼镜、上衣及下装使用各自的专用指令。
5. Upload 使用 macOS 对应模式的默认提示词，独立于当前选中的内置预设；虚拟召唤上传图使用保留原主体并新增参考角色到肩膀或手上的指令。Free Prompt 上传保留当前自写文本，显式提交使用编辑器当前文本。上传完成仅在选择仍有效时自动应用；服务上传和真实生成需要使用有效 Key 验收。
6. 顶部可控制统计显示，Stop Session 返回首页并关闭会话。FaceNow 不采集麦克风，会议软件中的麦克风由用户独立选择。
7. 打开 Virtual Camera，首次使用按提示 Set up camera。点击 Start Camera 后，在会议或直播软件中选择 FaceNow 虚拟摄像头。Windows 会追加本地化的设备后缀。生成开始后自动传输远端视频，Stop Session 后切回占位；生成期间安装成功也会接入已有会话。此流程已实现，真实云端与会议客户端尚需完整验收。

`-Preview` 中 Start 按钮显示 Preview UI，点击只切换页面，不创建摄像头或生成会话；仍可通过 HTTPS 加载缩略图。`-PreviewCameraSetup` 打开可交互的首次摄像头设置演示：Setup needed → 权限步骤模拟 → Setting up camera… → Ready to use，支持取消与 Restart setup preview。此模式不启动真实安装、不读写 API Key、不改动摄像头注册，权限步骤明确标为模拟，不是 Windows UAC 弹窗。`-PreviewLogin` 使用内存中的模拟账户，可用模拟 Key `uk-facenow-isolated-preview` 查看登录后的首页，界面明确显示模拟说明。`XMAX_API_KEY` 仍供显式 SDK 冒烟诊断使用，普通启动的账户流程不使用它绕过身份验证或覆盖账户选择。真实生成使用当前构建版本的区域服务，可能按服务规则计费；默认验收不执行真实生成。

FaceNow 的账户凭据保存在国内版 `XMAX.AI/FaceNow/Account` 或海外版 `XMAX.AI/FaceNowOverseas/Account`，包含明确的凭据类型及所选 Key 的记录 ID；普通磁盘缓存只保存账户资料及凭据摘要。旧版 `XMAX.AI/FaceNow/ApiKey` 在验证并迁移成功后清空。退出先停止生成，再清理账户凭据与缓存，保留虚拟摄像头安装。摄像头选择和缩略图缓存使用 FaceNow 独立位置，不读写 XLab 的用户设置。

## 工程边界

FaceNow 源码文件头使用文件名和产品名。第三方源码和改编代码的版权及来源见 [第三方声明](THIRD_PARTY.md)。

- `src/FaceNow.App`：基于 XLab WinUI 适配的窗口、控件、UI 调度、缩略图与冒烟验证。
- `src/FaceNow.App/User`：原生登录页、表单状态与验证码安全验证；窗口协调首页、账户菜单及生成退出。
- `src/FaceNow.Core/User`：账户模型、接口与应用级 UserRepository，独立于 WinUI、HTTP 和 Windows 凭据实现。
- `src/FaceNow.Windows/Network`：国内账户 HTTP 契约，按请求设置认证、严格校验响应并限制响应大小。
- `src/FaceNow.Windows/Studio`：整理到产品内部的会话 ViewModel、串行条件更新、上传与预设逻辑。
- `src/FaceNow.Windows/Security`：FaceNow 独立的 Windows 凭据管理器接入。
- `src/FaceNow.Core`：与 UI 框架无关的虚拟输出契约。
- `src/FaceNow.Windows/VirtualCamera`：设备管理、SDK 包所有权与后台队列、受限命名管道最新帧发布。
- `native/CameraSource`：基于微软示例适配的 COM 媒体源，接收 BGRA，按会话尺寸提供 RGB32/NV12 和占位图。
- `native/CameraControl.cpp`：架构匹配的组件安装、设备注册、移除、查询和帧读取辅助程序。

运行时只通过公开接口依赖 `Xmax.SDK` 和 `Xmax.SDK.WinUI`，不引用 XLab 示例程序集。界面与会话代码保留 MIT 来源声明，由 FaceNow 自身维护；后续 XLab 修改不会自动改变产品界面。

FaceNow 将本地与生成轨道绑定到 SDK 双路控件，首张结果帧呈现后淡入。虚拟摄像头通过独立媒体回调消费 SDK 美颜结果，再合成输出水印。

Copyright (c) 2026 XMAX.AI PTE. LTD.
