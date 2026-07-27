#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"
DIST="$ROOT/dist"
"$ROOT/scripts/prepare-renpy-runtime.sh"
rm -rf "$DERIVED" "$DIST/Payload"
mkdir -p "$DIST/Payload"

xcodebuild -project "$ROOT/DroidBox.xcodeproj" -scheme DroidBox -configuration Release \
  -sdk iphoneos -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build

APP="$DERIVED/Build/Products/Release-iphoneos/DroidBox.app"
test -d "$APP"

# Bundle the upstream, unencrypted Kirikiroid2 iOS companion. A regular iOS
# process cannot execute a nested app binary, so DroidBox exposes this pinned
# IPA for export/re-signing from a KiriKiri game's detail screen.
KIRIKIRI_VERSION="1.3.9"
KIRIKIRI_SHA256="96bb5c01631e2c5927c761b14839dfb53fabaf09d8a20e24250cbc29686a364b"
KIRIKIRI_CACHE="$ROOT/build/Kirikiroid2-$KIRIKIRI_VERSION.ipa"
if [ ! -f "$KIRIKIRI_CACHE" ] || [ "$(shasum -a 256 "$KIRIKIRI_CACHE" | awk '{print $1}')" != "$KIRIKIRI_SHA256" ]; then
  curl -fL --retry 4 --retry-delay 3 \
    "https://github.com/zeas2/Kirikiroid2/releases/download/$KIRIKIRI_VERSION/Kirikiroid2_$KIRIKIRI_VERSION.ipa" \
    -o "$KIRIKIRI_CACHE.download"
  echo "$KIRIKIRI_SHA256  $KIRIKIRI_CACHE.download" | shasum -a 256 -c -
  mv "$KIRIKIRI_CACHE.download" "$KIRIKIRI_CACHE"
fi
mkdir -p "$APP/EmbeddedRuntimes"
cp "$KIRIKIRI_CACHE" "$APP/EmbeddedRuntimes/Kirikiroid2-$KIRIKIRI_VERSION.ipa"

if [ -d "$ROOT/Vendor/QEMUCore/Frameworks" ]; then
  mkdir -p "$APP/Frameworks"
  ditto "$ROOT/Vendor/QEMUCore/Frameworks" "$APP/Frameworks"
fi
if [ -d "$ROOT/Vendor/QEMUCore/share" ]; then
  mkdir -p "$APP/qemu"
  ditto "$ROOT/Vendor/QEMUCore/share" "$APP/qemu"
fi
ditto "$APP" "$DIST/Payload/DroidBox.app"
(cd "$DIST" && zip -qry "DroidBox-unsigned.ipa" Payload)
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")"
cp "$DIST/DroidBox-unsigned.ipa" "$DIST/DroidBox-$VERSION-unsigned.ipa"
shasum -a 256 "$DIST/DroidBox-unsigned.ipa" | awk '{print $1}' > "$DIST/DroidBox-unsigned.sha256"

BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")"
cat > "$DIST/build-info.json" <<EOF
{"name":"DroidBox","version":"$VERSION","build":"$BUILD","commit":"${GITHUB_SHA:-unknown}","sdk":"$(xcrun --sdk iphoneos --show-sdk-version)","xcode":"$(xcodebuild -version | tr '\n' ' ')"}
EOF
"$ROOT/scripts/verify-ipa.sh" "$DIST/DroidBox-unsigned.ipa"
