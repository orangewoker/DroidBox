# 构建 DroidBox

需要 macOS、Xcode 16+ 与约 2 GB 的临时下载/解压空间。工程最低部署版本为 iOS 18。

```bash
chmod +x scripts/*.sh
./scripts/bootstrap.sh
./scripts/build-unsigned-ipa.sh
```

`bootstrap.sh` 会：

1. 下载 Ren'Py SDK 8.4.1 与 Renios 8.4.1；
2. 校验固定 SHA-256；
3. 生成空的 iOS Ren'Py `base`；
4. 准备 device 与 Simulator 的静态库和 MetalANGLE。

`build-unsigned-ipa.sh` 使用 `CODE_SIGNING_ALLOWED=NO`，生成：

- `dist/DroidBox-unsigned.ipa`
- `dist/DroidBox-1.2.5-unsigned.ipa`
- `dist/DroidBox-unsigned.sha256`
- `dist/build-info.json`

Windows 上将代码推送到 `ios` 分支后，`Build Unsigned IPA` 工作流会执行相同步骤并发布 `ios-v1.2.5` prerelease。
