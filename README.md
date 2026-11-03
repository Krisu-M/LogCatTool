# LogCatTool

在 Windows 上双击运行的 Android 日志抓取工具。自动查找 adb，未找到时询问是否安装，连接设备后清空历史日志并开始采集。

## 下载与使用

从 [Releases](https://github.com/Krisu-M/LogCatTool/releases/latest) 下载工具包，解压后运行 `Game_Logcat.bat`。也可以单独下载 Release 中的 BAT 文件。

1. 用数据线连接手机，开启 USB 调试，并在手机上允许电脑调试。
2. 双击 `Game_Logcat.bat`。
3. 未找到 adb 时会弹窗询问：选择 Yes/是，同意官方许可并下载安装；选择 No/否退出。
4. 看到“正在抓取设备”后，启动游戏并复现问题。
5. 关闭窗口即可停止，已写入的日志保留。

电脑需要 Windows PowerShell 5.1；无需管理员权限、Python 或 Android Studio。手机需要支持 adb 调试。当前版本不支持 iOS 或仅支持 HDC 的设备。

## 日志保存

输出位置：`%USERPROFILE%\game_logcat.txt`，例如 `C:\Users\Krisu_M\game_logcat.txt`。

**每次开始抓取都会清空目标设备的历史日志，并覆盖旧日志文件。** 如需保留上次结果，请先复制该文件。清空设备日志失败时停止采集，已有日志文件保持不变。

工具采集所有可访问日志缓冲区，包含游戏、系统和其他应用的输出。保存格式为 UTF-8，包含时间、进程 ID、线程 ID、等级和标签。

## adb 查找与安装

- 检查当前进程、用户和系统 PATH，以及 `ANDROID_HOME`、`ANDROID_SDK_ROOT`。
- 检查常见安装目录、本工具旁的 `adb.exe` 或 `platform-tools` 文件夹。
- 自动安装到 `%LOCALAPPDATA%\GameLogcat\platform-tools`，后续运行直接复用。
- 使用 Google 官方 Platform-Tools 下载地址，首次安装需要能访问 `dl.google.com`。
- 下载和使用须遵循 [Android SDK 官方许可条款](https://developer.android.com/tools/releases/platform-tools)。发布包不附带 Google 的二进制文件。

未找到自定义目录中的 adb 时，可将该目录加入 PATH，或将完整 `platform-tools` 文件夹放到工具旁。

## 连接异常

- `unauthorized`：解锁手机，允许 USB 调试授权。
- `offline`：重新连接设备后重试。
- 列表为空：检查 USB 调试、数据线和设备驱动。
- 多台设备：按提示输入序号选择目标。
- 下载失败：检查网络，或从官方页面手动下载并完整解压到工具旁。

没有可用设备时，处理后按 Enter 重试，输入 Q 退出。同一 Windows 会话只能运行一个抓取工具。

## 开发与验证

`Game_Logcat.ps1` 是工具源码，`Game_Logcat.bat` 是包含同一源码的独立启动文件。

在仓库根目录使用 Windows PowerShell 运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-GameLogcat.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1 -Version 1.0.0
```

打包脚本更新根目录 BAT，并在 `dist` 生成 ZIP 和 SHA-256 校验文件。模拟测试覆盖已有 adb、同意/拒绝安装、设备选择、日志覆盖、清空失败及下载失败，不连接真实手机，也不执行真实安装。

首版已由用户验证 adb 自动安装和 Android 真机短时抓取，并检查生成日志。
