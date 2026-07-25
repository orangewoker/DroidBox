#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$ROOT/Vendor/UTM"
echo "UTM source is pinned and fetched. Its QEMUKit build requires UTM's dependency bootstrap and GPL-compatible distribution."
echo "This base DroidBox target intentionally does not claim a QEMU build until the native adapter target is linked."
exit 2

