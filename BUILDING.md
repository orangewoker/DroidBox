# 构建 DroidBox

需要 macOS、Xcode 26 或可用的 Xcode 18+ iOS SDK。工程最低部署版本为 iOS 18.0，只构建设备 arm64 发布产物。

```bash
chmod +x scripts/*.sh
./scripts/bootstrap.sh
./scripts/build-unsigned-ipa.sh
```

脚本使用 `CODE_SIGNING_ALLOWED=NO`，生成 IPA、SHA-256 和构建信息。Windows 上将仓库推送到 `main` 或 `ios` 分支，工作流会在 macOS Runner 构建并发布到 `ios-v<version>` prerelease。不要同时 push 和手动 dispatch 同一次构建。

