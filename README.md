# DroidBox

DroidBox 是面向 iPhone 与 iPad 的 APK 游戏库和运行器，最低系统为 iOS 18。它可在设备上安全导入 APK/ZIP、解析 Android Binary XML Manifest、识别 ABI 和常见游戏引擎，并为 RPG Maker MV/MZ 提供 WebKit 快速运行路径。

当前仓库可以构建基础无签名 IPA。Android VM 的产品接口、状态机、Runtime 校验、JIT 探测、内置 ADB Host Client 以及 VNC/RFB 显示与触控输入通道已实现，但 UTM/QEMU 可执行核心与 Android 镜像尚未链接，因此普通 APK 会显示明确的“QEMU Core 未嵌入”，不会假装启动成功。Ren'Py Runtime 同样需要后续按许可证和体积独立构建。

## 功能

- APK/ZIP 安全导入，解析 Binary XML Manifest 与 `resources.arsc`，提取应用名和图标
- 识别 ABI 与 RPG Maker、Ren'Py、Unity、Godot、LibGDX 引擎，生成兼容性报告
- RPG Maker MV/MZ 通过隔离 URL Scheme 的 WebKit 快速路径运行
- Android VM 状态机：Runtime 校验、QCOW2 overlay、QMP 生命周期、ADB 安装与启动
- 内置 RFB 3.8 客户端，渲染 QEMU VNC 画面并把触控映射为指针事件
- 可持久化设置：VM 内存、导入上限、屏幕常亮、系统按键

## 构建

在 macOS 运行：

```bash
./scripts/bootstrap.sh
./scripts/build-unsigned-ipa.sh
```

产物位于 `dist/DroidBox-unsigned.ipa`。Windows 使用 GitHub Actions 构建，详见 [BUILDING.md](BUILDING.md)。
