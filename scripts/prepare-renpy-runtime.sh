#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="8.4.1"
CACHE="$ROOT/build/renpy-cache"
SDK_ROOT="$ROOT/build/renpy-sdk-$VERSION"
SDK="$SDK_ROOT/renpy-$VERSION-sdk"
LOADER="$ROOT/build/renpy-loader"
OUTPUT="$ROOT/Vendor/RenPy/Generated"
MARKER="$OUTPUT/.prepared-$VERSION"

SDK_URL="https://www.renpy.org/dl/$VERSION/renpy-$VERSION-sdk.zip"
RENIOS_URL="https://www.renpy.org/dl/$VERSION/renpy-$VERSION-renios.zip"
SDK_SHA256="b542062465b6a253f4286b0fd48b83dd578bd7b6282a52d4c1eaecbfe21f002d"
RENIOS_SHA256="f631ccd21f6fdc22619882bf55d44653f402dfe832422d1eefa804cba1ee819f"

if [ -f "$MARKER" ] &&
   [ -d "$OUTPUT/base" ] &&
   [ -d "$OUTPUT/prebuilt" ]; then
  exit 0
fi

mkdir -p "$CACHE" "$SDK_ROOT"
download() {
  local url="$1" destination="$2" expected="$3"
  if [ ! -f "$destination" ] || [ "$(shasum -a 256 "$destination" | awk '{print $1}')" != "$expected" ]; then
    rm -f "$destination"
    curl --fail --location --retry 3 --output "$destination" "$url"
  fi
  test "$(shasum -a 256 "$destination" | awk '{print $1}')" = "$expected"
}

SDK_ZIP="$CACHE/renpy-$VERSION-sdk.zip"
RENIOS_ZIP="$CACHE/renpy-$VERSION-renios.zip"
download "$SDK_URL" "$SDK_ZIP" "$SDK_SHA256"
download "$RENIOS_URL" "$RENIOS_ZIP" "$RENIOS_SHA256"

if [ ! -d "$SDK" ]; then
  rm -rf "$SDK_ROOT"
  mkdir -p "$SDK_ROOT"
  unzip -q "$SDK_ZIP" -d "$SDK_ROOT"
fi
rm -rf "$SDK/renios"
unzip -q "$RENIOS_ZIP" -d "$SDK"
chmod +x "$SDK/renpy.sh"

rm -rf "$LOADER" "$OUTPUT"
mkdir -p "$LOADER/game" "$(dirname "$OUTPUT")"
cat > "$LOADER/game/options.rpy" <<'EOF'
define config.name = "DroidBox RenPy Runtime"
define config.version = "1.0"
define build.name = "DroidBoxRenPyRuntime"
EOF

"$SDK/renpy.sh" launcher ios_create "$LOADER" "$OUTPUT"

test -f "$OUTPUT/base/main.py"
test -f "$OUTPUT/prebuilt/release/librenpy.a"
test -f "$OUTPUT/prebuilt/release/librenpython.a"
test -f "$OUTPUT/prebuilt/debug/librenpython.a"
test -f "$OUTPUT/prebuilt/release/libpython3.12.a"
test -d "$OUTPUT/Frameworks/MetalANGLE.xcframework"
# The generated project needs a temporary options.rpy to establish its name, but
# shipping that file would shadow an imported game's own options.rpyc because the
# bundle search path is scanned first. Keep an empty gamedir and load all game scripts
# exclusively from RENPY_SEARCHPATH.
find "$OUTPUT/base/game" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
touch "$MARKER"
