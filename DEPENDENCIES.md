# 依赖

基础 DroidBox 目标仅链接 Apple 系统框架：SwiftUI、WebKit、UniformTypeIdentifiers、CryptoKit、GameController（预留）和系统 zlib。

计划中的 Android VM 依赖固定如下，但尚未链接进应用目标：

| 项目 | 固定版本 | 许可证 | 用途 |
|---|---|---|---|
| UTM | tag `v5.0.3`, commit `e4a4c34b671284263fc69f81b607de494d7e9b65` | Apache-2.0 / GPL-2.0-or-later（按组件） | QEMUKit、显示、输入和 QEMU iOS 构建基础 |
| QEMU | `10.0.2-utm`（UTM v5.0.3 patches） | GPL-2.0-or-later | ARM64 Android VM |
| QEMUKit | commit `589765abff27a8764d58b1a90999a204ac09881e` | Apache-2.0 | QMP/生命周期设计参考 |
| CocoaSpice | commit `52b1535824657354fc3089eab24f1827280f9143` | Apache-2.0 | SPICE 显示、输入和音频接入目标 |
| LineageOS/AOSP QEMU runtime | `21.0-qemu-2026.07` 占位清单 | Apache-2.0 及相应开源许可证 | Android guest 镜像 |
| Ren'Py | 7.x 与 8.x，版本待可复现构建确认 | MIT 及第三方许可证 | Ren'Py 快速路径 |

`scripts/fetch-qemu-deps.sh` 只拉取固定 UTM commit，并已通过 UTM 官方 GitHub 仓库校验。没有可验证产物时，构建脚本会失败并明确报告，而不是生成来源不明的二进制。
