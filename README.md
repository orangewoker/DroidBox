# DroidBox

DroidBox 是面向 iPhone 与 iPad 的 APK 游戏库与运行器，最低系统为 iOS 18。

1.2.0 增加了 Ren'Py 8.4.1 原生 iOS 快速路径，目标是直接导入并运行采用 Python 3.12 字节码的 Ren'Py 8 Android APK。构建时从 Ren'Py 官方站点下载并校验 Renios，运行时不执行 APK 内的 Android `.so`，而是解包游戏脚本和资源，由同版本的 iOS 原生 Ren'Py 引擎解释执行。

## 功能

- 安全导入 APK/ZIP，解析 Binary XML Manifest 与 `resources.arsc`
- 识别 ABI、Ren'Py、KiriKiri、RPG Maker、Unity、Godot 与 LibGDX
- Ren'Py 8.4.1 / Python 3.12 原生运行，支持 RAPT 的 `x-` 路径还原
- 大型 Ren'Py APK 直接解包，不额外保留 APK 副本
- RPG Maker MV/MZ 通过隔离 URL Scheme 的 WebKit 快速路径运行
- Android VM 状态机、ADB Host Client、QMP 与 VNC/RFB 显示输入通道
- 可持久化的导入上限、VM 内存、屏幕常亮与系统按键设置

## 参考 APK

针对 `特工17 v0.26.9.apk` 的分析结果：

- 包名：`hexatail.agent17`
- 引擎：Ren'Py 8.4.1
- Python：3.12（`bytecode-312.rpyb`）
- ABI：arm64-v8a、armeabi-v7a、x86_64
- 游戏资源：约 2.86 GB，11,879 个 `assets/x-game/` 条目
- 媒体：WebP、MP3、WAV、WebM

该包进入 Ren'Py 原生快速路径，不启动完整 Android 虚拟机。

1.2.2 修复该 APK 中 `res/Ms.png` 与 `res/mS.png` 仅大小写不同而被误判为重复条目的问题。ZIP 规范及 Android 资源路径区分大小写；DroidBox 现在只拒绝完全相同的归档路径，并仍会在真正解压时阻止两个条目覆盖同一目标文件。

1.2.3 为文件选择、读取、解析、解压、成功和失败增加全流程可见反馈；JIT 改为实际探测 `MAP_JIT`。构建同时内置固定校验的 Kirikiroid2 1.3.9 iOS 配套 IPA，可在 KiriKiri 游戏详情中导出后通过 LiveContainer 或证书重签安装。

## 构建

在 macOS 运行：

```bash
chmod +x scripts/*.sh
./scripts/bootstrap.sh
./scripts/build-unsigned-ipa.sh
```

产物位于 `dist/DroidBox-unsigned.ipa`。Windows 使用 GitHub Actions 构建，详见 [BUILDING.md](BUILDING.md)。
