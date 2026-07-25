# LiveContainer

1. 将 `DroidBox-unsigned.ipa` 导入 LiveContainer。
2. 由 LiveContainer 对应用重签名；需要 Android VM 时启用 JIT-required，并使用 StikDebug 或宿主提供的 JIT 脚本。
3. 启动 DroidBox，在“运行时”页检查 JIT。应用只报告实际探测结果。
4. Android Runtime ZIP 必须包含 `runtime.json` 与 `system.qcow2`，且清单 SHA-256 与镜像一致。
5. 在游戏库点加号导入 APK 或 ZIP。

JIT 未启用不影响 RPG Maker Web 快速路径。当前基础构建没有嵌入 QEMU Core，因此 Android VM 会在启动时明确停止。

