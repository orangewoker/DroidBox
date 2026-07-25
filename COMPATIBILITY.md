# 兼容性

- iOS/iPadOS 18：最低部署目标，文件导入、SwiftUI、WebKit 和诊断路径。
- iOS 26.0.1：目标实机环境，尚未在当前 Windows 开发机上实机验证。
- iOS/iPadOS 27 Beta：提供 self-hosted Xcode 27 CI 工作流，不宣称 Beta 已通过。
- RPG Maker MV/MZ：识别并提取 `assets/www`，通过隔离 URL Scheme 运行。
- Ren'Py：可识别和整理游戏资源，运行时二进制尚未提供。
- 普通 Android APK：解析、存储和 VM 启动状态机可用；QEMU、显示、音频与 ADB 核心尚未链接。

DroidBox 不宣称兼容所有 APK。x86-only、Play Integrity、DRM 与重型 3D 游戏会被标记为不支持或实验兼容。

