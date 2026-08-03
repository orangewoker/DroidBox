# DroidBox

DroidBox 是面向 iPhone 与 iPad 的 APK 游戏库与运行器，最低系统为 iOS 18。

1.2.0 增加了 Ren'Py 8.4.1 原生 iOS 快速路径，目标是直接导入并运行采用 Python 3.12 字节码的 Ren'Py 8 Android APK。构建时从 Ren'Py 官方站点下载并校验 Renios，运行时不执行 APK 内的 Android `.so`，而是解包游戏脚本和资源，由同版本的 iOS 原生 Ren'Py 引擎解释执行。

## 功能

- 安全导入 APK/ZIP，解析 Binary XML Manifest 与 `resources.arsc`
- 识别 ABI、Ren'Py、RPG Maker、Unity、Godot 与 LibGDX
- 直接导入并运行 J2ME/Java ME `.jar` 游戏
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


1.2.4 不再使用在 SDL 手动托管窗口中丢失回调的 SwiftUI `fileImporter`，改为由长期存活的 UIKit `UIDocumentPickerDelegate` 直接接收结果，并以“打开原文件”模式避免选择 3 GB APK 时先发生无提示复制。应用启动时还会创建公开的 `DroidBox/Import` 目录，可从设置或游戏库菜单打开、扫描。JIT 检测同时支持 `MAP_JIT` 和 StikDebug 留下的 `CS_DEBUGGED`/`P_TRACED` 调试器路径。

## 构建

在 macOS 运行：

```bash
chmod +x scripts/*.sh
./scripts/bootstrap.sh
./scripts/build-unsigned-ipa.sh
```

产物位于 `dist/DroidBox-unsigned.ipa`。Windows 使用 GitHub Actions 构建，详见 [BUILDING.md](BUILDING.md)。

## 1.2.5

内置 J2ME/Java ME 运行时，可直接导入 `.jar`；修复系统文件选择器点“打开”后没有回调的问题，并加入游戏内分辨率、虚拟按键与退出设置。

## 1.2.6

“+”选择的 APK、ZIP、JAR 现在会先流式复制到公开的 `Import` 目录，再使用同一条解析与解压流程导入，并实时显示文件名、批次和进度。扫描 `Import` 会一次连续处理全部游戏，成功后删除原文件、失败文件继续保留。JAR 游戏界面完整复用 JavaPocket 的诺基亚 Manic EMU 皮肤、方向键、数字键盘、快照、静音和倍速控制；其他运行模式继续使用 DroidBox 原有虚拟按键。

## 1.2.7

系统文件选择器改用 app-owned copy 回调：点击“打开”后不再转存到 `Import`，而是直接解析并解压到 `Games`，同时显示逐文件进度。游戏播放器改为真正的全屏封面，JAR 皮肤使用等比缩放，避免状态栏、半屏 Sheet 和非等比拉伸造成机身按键错位。左上角菜单同时提供游戏设置和 JavaPocket 实时内存修改器。

## 1.2.8

游戏库中的游戏现在可通过长按菜单修改显示名称。Java ME 播放器增加设备温控与低电量模式诊断，并减少重复的画布缩放调用、空闲修改器轮询和修改器刷新频率，以降低不必要的 CPU 占用与发热。

## Android Runtime 第二阶段

Full Runtime IPA 现在从固定 SHA-256 的 UTM 5.0.3 官方发行包提取并内置
`qemu-x86_64-softmmu` 及其依赖。运行时页面可以在线下载或手动导入持久化的
Android-x86 9.0-r2 Runtime，QEMU 启动后通过本机 QMP、ADB 和 VNC/RFB 完成 APK
安装、入口解析、启动、显示与触控。Android VM 需要 JIT 才能达到可用速度，且 APK
必须包含 x86_64 原生库或为纯 Java 应用。

1.3.1 修复 Android Runtime 校验文件携带 CI 绝对路径的问题，离线下载脚本现在可以直接校验发行资产。

1.3.2 修复 LiveContainer 下 `Bundle.main` 指向宿主导致 QEMU Core 误报未嵌入的问题；Android Runtime 在线安装和 ZIP 导入不再被 Core 检测结果锁死，JIT 重新检测会弹出明确结果。

1.3.3 针对 Android VM 点启动后被 iOS 直接终止的问题，将默认客体内存降为 1024 MB、TCG 缓存从 512 MB 降为 128 MB，并改用进程 Jetsam 可用内存检测。QEMU 启动会保留日志和异常中断标记。

1.3.4 将 QEMU 启动生命周期对齐 UTM 5.0.3：框架先同步加载，再由高优先级 pthread 运行。`Documents/Android/qemu-bridge.log` 会在动态库加载、符号解析和 QEMU 初始化前后同步记录阶段；异常退出后 DroidBox 会直接显示最后记录。

1.3.5 将 QEMU 的标准输出和错误输出临时写入桥接日志，并记录完整启动参数，便于定位 QEMU 在初始化阶段主动退出的原因。

1.3.6 修复 SwiftUI 重复触发 Android VM 启动的问题，并在控制器和原生 QEMU 桥接层增加单实例保护；QEMU 原始错误会直接显示在启动失败界面。

1.3.7 为每个构建使用独立的 QEMU framework 标识，避免 LiveContainer 复用旧 QEMU 全局状态；启动前还会检测并清理残留的 QEMU 配置注册表，修复 `ran out of space in drive_config_groups`。
