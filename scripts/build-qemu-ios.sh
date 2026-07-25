#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UTM="$ROOT/Vendor/UTM"
OUTPUT="$ROOT/Vendor/QEMUCore"

"$ROOT/scripts/fetch-qemu-deps.sh"
cd "$UTM"
export PATH="$(brew --prefix llvm)/bin:$(brew --prefix bison)/bin:$(brew --prefix gettext)/bin:$(brew --prefix glib)/bin:$(brew --prefix libgpg-error)/bin:$PATH"
./scripts/build_dependencies.sh -p ios -a arm64

SYSROOT="$UTM/sysroot-iOS-arm64"
test -d "$SYSROOT/Frameworks/qemu-aarch64-softmmu.framework"
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/Frameworks" "$OUTPUT/licenses"
rsync -a "$SYSROOT/Frameworks/" "$OUTPUT/Frameworks/"
if [ -d "$SYSROOT/share" ]; then rsync -a "$SYSROOT/share/" "$OUTPUT/share/"; fi
cp "$UTM/LICENSE" "$OUTPUT/licenses/UTM-LICENSE" 2>/dev/null || true
printf '%s\n' 'UTM v5.0.3' 'commit e4a4c34b671284263fc69f81b607de494d7e9b65' 'QEMU 10.0.2-utm' > "$OUTPUT/build-version.txt"

mkdir -p "$ROOT/dist"
(cd "$ROOT/Vendor" && zip -qry "$ROOT/dist/QEMUCore-utm-v5.0.3-ios-arm64.zip" QEMUCore)
shasum -a 256 "$ROOT/dist/QEMUCore-utm-v5.0.3-ios-arm64.zip" | awk '{print $1}' > "$ROOT/dist/QEMUCore-utm-v5.0.3-ios-arm64.sha256"

