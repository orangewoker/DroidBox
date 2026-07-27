# 故障排查

## 无法导入

确认文件扩展名为 APK/ZIP、归档未损坏且没有路径穿越、完全相同的重复条目或异常膨胀。Android APK 可以合法包含仅大小写不同的资源名，1.2.2 起不会再因此误拒绝整个 APK。默认单文件上限 8 GB。

1.2.4 起右上角“+”使用 UIKit 文件选择器直接打开原文件，不再经过 SwiftUI `fileImporter`。如果所用容器仍阻止系统选择器回调，进入“文件 → 我的 iPhone → DroidBox → Import”放入 APK/ZIP，然后在 DroidBox 的游戏库菜单或设置中点击“扫描 Import 目录”。

## StikDebug 启动后仍显示无 JIT

1.2.4 会先实测 `MAP_JIT`；失败后继续检查当前进程的 `CS_DEBUGGED` 与 `P_TRACED` 状态，并在调试器路径下验证 RW→RX 转换。通过 StikDebug 启动时应显示“可用（StikDebug/调试器）”。如果 StikDebug 在 DroidBox 启动后才附加，回到“运行时”页面点击“重新检测”。

## Ren'Py 游戏版本不匹配

Full Runtime 当前固定为 Ren'Py 8.4.1 / Python 3.12。APK 应包含 `assets/x-game/cache/x-bytecode-312.rpyb`（导入时会还原为 `cache/bytecode-312.rpyb`）；其他字节码版本会停止导入，避免崩溃或存档损坏。

## Android Runtime 校验失败

仅在 IPA 已嵌入 QEMU Core 时才可导入。ZIP 根目录应有 `runtime.json`，`architecture` 必须为 `arm64`，`sha256` 必须是 `system.qcow2` 的 SHA-256。项目当前没有发布可供下载的 Android Runtime 镜像。

## QEMU Core 未嵌入

这是当前基础构建的已知限制,不是 JIT 故障。JIT 只提供可执行内存权限,不会自动加入 QEMU、Android 镜像、显示或 ADB。

## 停在"连接显示通道"

应用会连接 QEMU 的 VNC 端口(`5900 + 显示号`)。若一直失败,检查 Runtime 清单的 `qemuArguments` 是否保留了 `-vnc 127.0.0.1:{vncDisplay}`;自定义参数改成 Unix socket 或去掉 `-vnc` 后画面无法接通。要求密码认证的服务器同样会被拒绝,DroidBox 只接受本机无认证连接。

## 画面正常但触控无反应

指针事件依赖 guest 中的 `virtio-tablet-pci` 绝对定位设备。自定义 `qemuArguments` 时保留该设备,否则 Android 收不到坐标。

## RPG Maker 黑屏

查看游戏是否确实包含 `assets/www/index.html`,并检查大小写敏感的资源路径及游戏自身 JavaScript 错误。

## JAR 导入后无法启动

只支持包含 `META-INF/MANIFEST.MF` 与 MIDlet 声明的 J2ME/MIDP 游戏。普通桌面 Java JAR 或 Android 工具 JAR 不属于 Java ME 游戏。
