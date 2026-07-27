# Runtime packages

Large Runtime binaries are never committed here. The default Android-x86 Runtime ZIP has this root layout:

```text
runtime.json
system.qcow2
kernel
initrd.img
```

`runtime.json` 中的 SHA-256 描述未压缩的 `system.qcow2`。当前 Full Runtime IPA 内置
UTM/QEMU x86_64 Core，因此清单的 `architecture` 必须是 `x86_64`。

## 自定义 qemuArguments

清单可选的 `qemuArguments` 会整体替换默认参数,占位符 `{overlay}`、`{base}`、`{runtime}`、`{qmpPort}`、`{adbPort}`、`{vncDisplay}`、`{memoryMB}` 由应用在启动时填入。

替换默认参数时必须保留三条通道,否则对应功能直接失效:

| 通道 | 必需参数 | 缺失后果 |
|---|---|---|
| 显示与输入 | `-vnc 127.0.0.1:{vncDisplay}` 与 `-device virtio-tablet-pci` | 停在"连接显示通道",或有画面但无触控 |
| 生命周期 | `-qmp tcp:127.0.0.1:{qmpPort},server=on,wait=off` | 无法暂停、恢复和正常关闭 |
| ADB | `hostfwd=tcp:127.0.0.1:{adbPort}-:5555` | 无法安装和启动 APK |

应用只接受本机无密码的 VNC 连接,`-vnc` 上不要加 `password` 或改成 Unix socket。
