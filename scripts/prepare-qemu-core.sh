#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/Vendor/QEMUCore"
CACHE="$ROOT/Vendor/cache"
UTM_VERSION="5.0.3"
UTM_SHA256="5d47da1d5eafc02191f39992624e1e51b0e9e7060785c431236f9ae304a20d22"
UTM_IPA="$CACHE/UTM-$UTM_VERSION.ipa"
UTM_URL="https://github.com/utmapp/UTM/releases/download/v$UTM_VERSION/UTM.ipa"

FRAMEWORKS=(
  qemu-x86_64-softmmu.framework
  Hypervisor.framework
  pixman-1.0.framework
  jpeg.62.framework
  epoxy.0.framework
  gio-2.0.0.framework
  gobject-2.0.0.framework
  glib-2.0.0.framework
  zstd.1.framework
  slirp.0.framework
  spice-server.1.framework
  virglrenderer.1.framework
  usbredirparser.1.framework
  usb-1.0.0.framework
  gmodule-2.0.0.framework
  intl.8.framework
  ffi.8.framework
  iconv.2.framework
  ssl.1.1.framework
  crypto.1.1.framework
  opus.0.framework
  gstreamer-1.0.0.framework
  gstapp-1.0.0.framework
  vulkan.1.framework
  gstbase-1.0.0.framework
)

mkdir -p "$CACHE"
if [ ! -f "$UTM_IPA" ]; then
  curl -fL --retry 5 --retry-delay 3 "$UTM_URL" -o "$UTM_IPA"
fi
echo "$UTM_SHA256  $UTM_IPA" | shasum -a 256 -c -

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for framework in "${FRAMEWORKS[@]}"; do
  unzip -q "$UTM_IPA" "Payload/UTM.app/Frameworks/$framework/*" -d "$TMP"
done
unzip -q "$UTM_IPA" "Payload/UTM.app/qemu/*" -d "$TMP"

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/Frameworks" "$OUTPUT/share" "$OUTPUT/licenses"
for framework in "${FRAMEWORKS[@]}"; do
  ditto "$TMP/Payload/UTM.app/Frameworks/$framework" "$OUTPUT/Frameworks/$framework"
  executable="${framework%.framework}"
  codesign --remove-signature "$OUTPUT/Frameworks/$framework/$executable" 2>/dev/null || true
  rm -rf "$OUTPUT/Frameworks/$framework/_CodeSignature"
done

# Fail the build when the pinned framework set is not a complete @rpath closure.
# dlopen otherwise discovers a missing nested dependency only on the user's device.
for framework in "${FRAMEWORKS[@]}"; do
  executable="${framework%.framework}"
  binary="$OUTPUT/Frameworks/$framework/$executable"
  while IFS= read -r dependency; do
    relative="${dependency#@rpath/}"
    if [ ! -e "$OUTPUT/Frameworks/$relative" ]; then
      echo "Missing QEMU dependency: $framework -> $dependency" >&2
      exit 1
    fi
  done < <(otool -L "$binary" | awk '$1 ~ /^@rpath\// { print $1 }')
done
ditto "$TMP/Payload/UTM.app/qemu" "$OUTPUT/share"
curl -fsSL "https://raw.githubusercontent.com/utmapp/UTM/e4a4c34b671284263fc69f81b607de494d7e9b65/LICENSE" \
  -o "$OUTPUT/licenses/UTM-LICENSE"
printf '%s\n' \
  "UTM v$UTM_VERSION" \
  "commit e4a4c34b671284263fc69f81b607de494d7e9b65" \
  "Official release asset SHA-256 $UTM_SHA256" \
  > "$OUTPUT/build-version.txt"

test -f "$OUTPUT/Frameworks/qemu-x86_64-softmmu.framework/qemu-x86_64-softmmu"
test -f "$OUTPUT/share/bios.bin"
echo "Prepared UTM/QEMU x86_64 core from the pinned official UTM release."
