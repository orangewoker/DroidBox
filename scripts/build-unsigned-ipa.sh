#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"
DIST="$ROOT/dist"
"$ROOT/scripts/prepare-renpy-runtime.sh"
"$ROOT/scripts/prepare-qemu-core.sh"
rm -rf "$DERIVED" "$DIST/Payload"
mkdir -p "$DIST/Payload"

xcodebuild -project "$ROOT/DroidBox.xcodeproj" -scheme DroidBox -configuration Release \
  -sdk iphoneos -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build

APP="$DERIVED/Build/Products/Release-iphoneos/DroidBox.app"
test -d "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")"

if [ -d "$ROOT/Vendor/QEMUCore/Frameworks" ]; then
  mkdir -p "$APP/Frameworks"
  ditto "$ROOT/Vendor/QEMUCore/Frameworks" "$APP/Frameworks"
  # LiveContainer may retain a dlopened framework across guest app updates. A
  # build-specific install name prevents dyld from reusing an older QEMU image
  # whose one-shot global registries have already been populated.
  QEMU_SOURCE="$APP/Frameworks/qemu-x86_64-softmmu.framework"
  # Keep the new Mach-O install name shorter than UTM's original name because
  # the release binary was not linked with extra load-command header padding.
  QEMU_NAME="qdb$BUILD"
  QEMU_DEST="$APP/Frameworks/$QEMU_NAME.framework"
  test -f "$QEMU_SOURCE/qemu-x86_64-softmmu"
  mv "$QEMU_SOURCE" "$QEMU_DEST"
  mv "$QEMU_DEST/qemu-x86_64-softmmu" "$QEMU_DEST/$QEMU_NAME"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $QEMU_NAME" "$QEMU_DEST/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.droidbox.qemu.b$BUILD" "$QEMU_DEST/Info.plist" || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.droidbox.qemu.b$BUILD" "$QEMU_DEST/Info.plist"
  # install_name_tool cannot rewrite this very large prebuilt image reliably on
  # current runners. Replace only the fixed-size LC_ID_DYLIB string in place.
  python3 - "$QEMU_DEST/$QEMU_NAME" "@rpath/$QEMU_NAME.framework/$QEMU_NAME" <<'PY'
import pathlib
import sys

binary = pathlib.Path(sys.argv[1])
replacement = sys.argv[2].encode("utf-8")
original = b"@rpath/qemu-x86_64-softmmu.framework/qemu-x86_64-softmmu"
if len(replacement) > len(original):
    raise SystemExit("versioned QEMU install name is too long")
data = binary.read_bytes()
if data.count(original) != 1:
    raise SystemExit("QEMU LC_ID_DYLIB string was not found exactly once")
binary.write_bytes(data.replace(original, replacement + b"\0" * (len(original) - len(replacement)), 1))
PY
  otool -D "$QEMU_DEST/$QEMU_NAME" | grep -Fx "@rpath/$QEMU_NAME.framework/$QEMU_NAME"
fi
if [ -d "$ROOT/Vendor/QEMUCore/share" ]; then
  mkdir -p "$APP/qemu"
  ditto "$ROOT/Vendor/QEMUCore/share" "$APP/qemu"
fi
if [ -d "$ROOT/Vendor/QEMUCore/licenses" ]; then
  mkdir -p "$APP/ThirdPartyLicenses"
  ditto "$ROOT/Vendor/QEMUCore/licenses" "$APP/ThirdPartyLicenses/UTM-QEMU"
fi
ditto "$APP" "$DIST/Payload/DroidBox.app"
(cd "$DIST" && zip -qry "DroidBox-unsigned.ipa" Payload)
cp "$DIST/DroidBox-unsigned.ipa" "$DIST/DroidBox-$VERSION-unsigned.ipa"
shasum -a 256 "$DIST/DroidBox-unsigned.ipa" | awk '{print $1}' > "$DIST/DroidBox-unsigned.sha256"

cat > "$DIST/build-info.json" <<EOF
{"name":"DroidBox","version":"$VERSION","build":"$BUILD","commit":"${GITHUB_SHA:-unknown}","sdk":"$(xcrun --sdk iphoneos --show-sdk-version)","xcode":"$(xcodebuild -version | tr '\n' ' ')"}
EOF
"$ROOT/scripts/verify-ipa.sh" "$DIST/DroidBox-unsigned.ipa"
