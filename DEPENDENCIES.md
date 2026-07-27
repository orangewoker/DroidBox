# 依赖

## 已进入 Full Runtime 构建

| 项目 | 固定版本 | 校验 | 用途 |
|---|---|---|---|
| Ren'Py SDK | 8.4.1 | SHA-256 `b542062465b6a253f4286b0fd48b83dd578bd7b6282a52d4c1eaecbfe21f002d` | Python/Ren'Py 基础资源 |
| Renios | 8.4.1 | SHA-256 `f631ccd21f6fdc22619882bf55d44653f402dfe832422d1eefa804cba1ee819f` | iOS arm64/Simulator 静态库、SDL2、FFmpeg、MetalANGLE |

`scripts/prepare-renpy-runtime.sh` 只从 Ren'Py 官方下载地址获取上述固定文件，校验通过后才生成构建目录。二进制不会提交到 Git。

Renios 包含 MIT、LGPL 及其他第三方许可组件。分发 IPA 时必须保留 Ren'Py 官方许可清单要求的声明。

## 尚未进入默认 IPA

| 项目 | 固定版本 | 许可 | 用途 |
|---|---|---|---|
| UTM | v5.0.3 / `e4a4c34b671284263fc69f81b607de494d7e9b65` | Apache-2.0 / GPL-2.0-or-later | QEMU iOS 构建基础 |
| QEMU | `10.0.2-utm` | GPL-2.0-or-later | ARM64 Android VM |
| LineageOS/AOSP runtime | `21.0-qemu-2026.07` 占位 | Apache-2.0 等 | Android guest |
| J2ME.js / FreeJ2ME Web runtime | 内置 | 上游组件各自许可 | Java ME/MIDP 游戏解释执行 |
