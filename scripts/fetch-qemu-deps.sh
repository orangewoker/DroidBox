#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; VENDOR="$ROOT/Vendor"; mkdir -p "$VENDOR"
UTM_COMMIT="04c4f2be115a0bd9e632a53af1db18a38e9d74d6"
if [ ! -d "$VENDOR/UTM/.git" ]; then git clone --filter=blob:none https://github.com/utmapp/UTM.git "$VENDOR/UTM"; fi
git -C "$VENDOR/UTM" fetch origin "$UTM_COMMIT" --depth 1
git -C "$VENDOR/UTM" checkout --detach "$UTM_COMMIT"
echo "$UTM_COMMIT" > "$VENDOR/UTM.commit"

