# Runtime packages

Large Runtime binaries are never committed here. An Android Runtime ZIP has this root layout:

```text
runtime.json
system.qcow2
firmware/...
```

`runtime.json` follows `Runtimes/manifests/lineage-arm64-default.json`; its SHA-256 describes the uncompressed `system.qcow2`.

