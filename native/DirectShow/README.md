# FaceNow DirectShow 虚拟摄像头

Windows 10 2004（build 19041）及更新版本的 x64 系统使用 DirectShow 后端。国内版和海外版共用 `FaceNow 虚拟摄像头`。在「虚拟设备」中设置摄像头时，管理员 helper 部署 DLL 并注册到 DirectShow 视频输入类别。卸载最后一个版本时，移除这项机器级注册需要管理员权限。

设备通过 `FaceNow.DirectShow.<会话 ID>` 读取同一 Windows 会话的生成画面。x64 DirectShow 客户端连接时，使用 FaceNow 当前发布的尺寸，可协商 1 到 30 fps。先启动生成，再在采集应用中打开或重新连接摄像头，可使用所选比例。断流或空闲时显示灰色占位。

发布前运行 `scripts/build-camera.ps1 -DirectShowBaseClasses C:\dev\baseclasses`。参数目录包含微软 DirectShow BaseClasses 源码和对应的 MIT `LICENSE`。发布脚本将 `directshow-x64` 和许可证一起打包。下面的命令使用 x64 FFmpeg 验证正式设备的尺寸、颜色和画面方向。

```powershell
dotnet run --project .\tests\FaceNow.CameraRelayTests -c Release -- C:\tools\ffmpeg.exe --directshow 1080 1920
```

## 独立原型

`FaceNow.DirectShowPrototype.dll` 将一个独立的 x64 测试摄像头注册到 DirectShow 的视频输入设备列表，设备名为 `FaceNow DirectShow Test`。采集端请求 1280×720、30 fps 的 RGB32 画面时，DLL 通过现有 `FramePipe` 读取同一 Windows 会话下的 FaceNow 帧。没有发布者或画面过期时，DLL 输出灰色占位。现阶段由离线验证程序调用生产 `FramePublisher` 发布测试图。

在 Windows 的仓库根目录，用 Visual Studio x64 C++ 工具构建。`-BaseClasses` 指向 [微软 Windows classic samples 的 DirectShow BaseClasses 源码](https://github.com/microsoft/Windows-classic-samples/tree/434f6002bdf9cf9829406c3ff2b33387982d6168/Samples/Win7Samples/multimedia/directshow/baseclasses)。该源码使用 [MIT 许可证](https://github.com/microsoft/Windows-classic-samples/blob/434f6002bdf9cf9829406c3ff2b33387982d6168/LICENSE)。

```powershell
.\scripts\build-directshow-prototype.ps1 -BaseClasses C:\dev\baseclasses
```

在管理员 PowerShell 里运行下面的注册命令，`ExitCode` 为 `0` 时注册成功。

```powershell
$dll = 'C:\dev\FaceNow-directshow-prototype\FaceNow.DirectShowPrototype.dll'
(Start-Process "$env:SystemRoot\System32\regsvr32.exe" -ArgumentList "/s `"$dll`"" -Wait -PassThru).ExitCode
```

从普通用户的 PowerShell 运行采集验证。需要 .NET 10 SDK 和支持 DirectShow 的 x64 FFmpeg。验证程序发送彩色测试图，从已注册设备采集 12 帧并检查颜色与方向。

```powershell
dotnet run --project .\tests\FaceNow.CameraRelayTests -c Release -- C:\tools\ffmpeg.exe --directshow-prototype
```

关闭测试客户端后，在管理员 PowerShell 里注销测试设备，再移除 DLL。

```powershell
(Start-Process "$env:SystemRoot\System32\regsvr32.exe" -ArgumentList "/s /u `"$dll`"" -Wait -PassThru).ExitCode
```
