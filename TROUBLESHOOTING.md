# 故障排查

## 无法导入

确认文件扩展名为 APK/ZIP、归档未损坏且没有路径穿越、重复条目或异常膨胀。默认单文件上限 8 GB。

## Android Runtime 校验失败

检查 ZIP 根目录的 `runtime.json`，`architecture` 必须为 `arm64`，`sha256` 必须是 `system.qcow2` 的 SHA-256。

## QEMU Core 未嵌入

这是当前基础构建的已知限制，不是 JIT 故障。JIT 只提供可执行内存权限，不会自动加入 QEMU、Android 镜像、显示或 ADB。

## RPG Maker 黑屏

查看游戏是否确实包含 `assets/www/index.html`，并检查大小写敏感的资源路径及游戏自身 JavaScript 错误。

