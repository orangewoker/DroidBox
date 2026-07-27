#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/prepare-qemu-core.sh"
mkdir -p "$ROOT/dist"
(cd "$ROOT/Vendor" && zip -qry "$ROOT/dist/QEMUCore-utm-v5.0.3-ios-x86_64.zip" QEMUCore)
shasum -a 256 "$ROOT/dist/QEMUCore-utm-v5.0.3-ios-x86_64.zip" | awk '{print $1}' \
  > "$ROOT/dist/QEMUCore-utm-v5.0.3-ios-x86_64.sha256"
