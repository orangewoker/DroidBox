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

if [ -d "$ROOT/Vendor/QEMUCore/Frameworks" ]; then
  mkdir -p "$APP/Frameworks"
  ditto "$ROOT/Vendor/QEMUCore/Frameworks" "$APP/Frameworks"
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
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")"
cp "$DIST/DroidBox-unsigned.ipa" "$DIST/DroidBox-$VERSION-unsigned.ipa"
shasum -a 256 "$DIST/DroidBox-unsigned.ipa" | awk '{print $1}' > "$DIST/DroidBox-unsigned.sha256"

BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")"
cat > "$DIST/build-info.json" <<EOF
{"name":"DroidBox","version":"$VERSION","build":"$BUILD","commit":"${GITHUB_SHA:-unknown}","sdk":"$(xcrun --sdk iphoneos --show-sdk-version)","xcode":"$(xcodebuild -version | tr '\n' ' ')"}
EOF
"$ROOT/scripts/verify-ipa.sh" "$DIST/DroidBox-unsigned.ipa"
