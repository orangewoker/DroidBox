# 兼容性

## 原生快速路径

| 类型 | 状态 | 说明 |
|---|---|---|
| Ren'Py 8.4.1 / Python 3.12 | 优秀 | 支持标准 RAPT APK、`assets/x-game` 路径还原、WebP/MP3/WebM 等 Renios 媒体能力 |
| 其他 Ren'Py 8.x | 阻止启动 | 字节码或原生扩展版本不匹配时明确报告，不跨版本强行运行 |
| Ren'Py 7.x | 待加入 | 需要独立的 Python 2/旧版 Renios 构建 |
| RPG Maker MV/MZ | 优秀 | 提取 `assets/www` 并通过 WKWebView 运行 |
| J2ME / Java ME JAR | 优秀 | 内置 J2ME 运行时，支持 MIDP/CLDC、虚拟键盘、分辨率切换与 RMS 存档 |

## Android VM 路径

普通 Android APK 仍依赖尚未随仓库发布的 UTM/QEMU 核心与 Android guest 镜像。状态机、QCOW2、QMP、ADB 与 VNC/RFB 通道已实现，但不能用它们代替缺失的可执行核心。

“Android Runtime”指 Android VM 的 `system.qcow2` 客体磁盘镜像，不是 APK、游戏数据包或可单独安装的插件。当前 IPA 的 QEMU Core 未嵌入，因此只导入 Runtime ZIP 也不能启动 Android VM；Ren'Py 8.4.1 快速路径完全不需要它。

x86-only、Play Integrity、DRM 与重型 3D 游戏会标记为不支持或实验兼容。

## 系统

- iOS/iPadOS 18：最低部署目标
- iOS 26：主要构建目标
- iOS/iPadOS 27 Beta：提供 self-hosted Xcode 27 编译工作流
