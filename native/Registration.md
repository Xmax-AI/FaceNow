# Windows 11 虚拟摄像头注册

当前已实现：原生 COM 媒体源、纯灰占位生成、组件安装、CurrentUser 设备注册/移除和状态查询。Windows 11 ARM64 虚拟机已通过系统 Frame Server 读取 10 帧验收。SDK AI 视频回调已接入受限命名管道，使用本地合成帧通过系统传输检查；真实云端和会议兼容性尚未验收。

## 应用内操作

1. 先运行 `scripts/build-camera.ps1`，再用 `scripts/run.ps1` 构建或启动。它把 x64 / ARM64 组件复制到应用目录；控制器根据操作系统架构选择对应 helper。
2. 右上角 Virtual Camera → Install & Enable。安装 helper 通过 Windows UAC 请求管理员权限，部署自身旁边固定名称的 DLL 并注册 COM；主程序保持普通用户运行。
3. 安装完成后，普通用户 helper 使用 MFCreateVirtualCamera + Start 创建设备，保存实际 symbolic link，并通过设备枚举确认 Registered。
4. Test Video 从已注册设备读取 10 帧，显示最后一帧；这是系统采集路径，不是 UI 模拟图。生成时输出近期的远端帧，空闲或断流时输出纯色灰底 #F1F3F4。
5. Remove Camera 调用 IMFVirtualCamera::Remove 并删除当前用户保存的 symbolic link。它不卸载公共组件文件与 COM 注册，方便后续再次启用。

界面已接入安装、启用、移除和测试按钮；本次系统安装/注册验证通过命令行 helper 完成，交互式 UAC 点击流程仍需人工验收。

## 原生实现

- CLSID：`{C1EF1269-DBA1-473B-BD21-7F3695635A11}`。
- 注册名称为 `FaceNow 虚拟摄像头`。Windows 会在设备列表中追加本地化的系统后缀。设备设置会注册新名称，再移除旧名称的注册。
- `MFVirtualCameraType_SoftwareCameraSource`、`MFVirtualCameraLifetime_System`、`MFVirtualCameraAccess_CurrentUser`。
- 安装目录：`Program Files/FaceNow/Camera/<DLL SHA256 前 12 字节>/FaceNow.CameraSource.dll`。新版本使用新目录，避免覆盖被占用 DLL；历史版本清理由正式安装器实现。
- COM：HKLM `Software/Classes/CLSID/{CLSID}/InProcServer32`，线程模型 Both。
- 用户设备记录：HKCU `Software/XMAX.AI/FaceNow/VirtualCamera` 的 SymbolicLink。
- 媒体源提供 1280×720 RGB32/NV12 格式，声明 30 fps；持续输出节奏和性能仍需独立验收。
- 测试源不加载 .NET、WinUI、XmaxSDK 或用户凭证。静态 CRT 构建，不依赖 VC 运行库安装。

System 生命周期使设备保留至显式移除；关闭 FaceNow 不移除设备。已验证 helper 退出后仍可读取，系统重启恢复仍待验收。应用用保存的完整 symbolic link 排除自身作为输入，避免反馈采集。

## 状态

| 状态 | 依据 |
|---|---|
| Not supported | 系统不支持当前 Windows 11 后端 |
| Not installed | 应用目录缺少架构匹配的 helper 或 source，无法安装 |
| Not registered | 组件可部署，但系统未枚举到该用户保存的设备 |
| Registered | 枚举到匹配 symbolic link 的设备；不代表 AI 输出已连接 |
| Error / Unknown | 查询或操作失败，显示实际错误 |

状态查询只枚举，不激活视频源。Output on 表示近期有视频帧提交到传帧通道；不代表会议对端接收。安装组件 SHA256 与应用附带源 DLL 不一致时要求更新，避免旧测试源被误认为支持 AI 输出。隐私权限错误可通过弹层中的 Camera Privacy Settings 打开系统设置。

## 开发命令

在 `C:/dev/FaceNow-camera/<系统架构>` 中执行：

```powershell
# 只读，不打开实体摄像头或创建生成会话
./FaceNow.CameraControl.exe --status
# 仅此步骤需要管理员权限
./FaceNow.CameraControl.exe --install
# 以下以目标用户运行
./FaceNow.CameraControl.exe --enable
./FaceNow.CameraControl.exe --verify test-video.bmp
./FaceNow.CameraControl.exe --remove
# 无需安装或注册，直接激活旁边的合成源
./FaceNow.CameraControl.exe --self-test local-test.bmp
```

`--verify` 与 `--self-test` 检查 10 帧、递增时间戳和非均匀视频或预期灰色占位像素，并可保存最后一帧 BMP。它们不等于会议对端接收、帧率或长期稳定性验收。额外的 `scripts/run.ps1 -VerifyRelay` 验证真实系统管线的像素、无黑边铺满、断流、停止和重启行为。

参考：[微软 VirtualCamera 示例](https://github.com/microsoft/Windows-Camera/tree/master/Samples/VirtualCamera)、[MFCreateVirtualCamera](https://learn.microsoft.com/en-us/windows/win32/api/mfvirtualcamera/nf-mfvirtualcamera-mfcreatevirtualcamera)、[IMFVirtualCamera::Start](https://learn.microsoft.com/en-us/windows/win32/api/mfvirtualcamera/nf-mfvirtualcamera-imfvirtualcamera-start)。
