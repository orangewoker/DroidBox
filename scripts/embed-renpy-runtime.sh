#!/usr/bin/env bash
set -euo pipefail

RUNTIME="$SRCROOT/Vendor/RenPy/Generated"
APP_RESOURCES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
APP_FRAMEWORKS="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"

test -f "$RUNTIME/base/main.py"
mkdir -p "$APP_RESOURCES" "$APP_FRAMEWORKS"
rm -rf "$APP_RESOURCES/base" "$APP_FRAMEWORKS/MetalANGLE.framework"
ditto "$RUNTIME/base" "$APP_RESOURCES/base"
rm -rf "$APP_RESOURCES/j2mejs"
ditto "$SRCROOT/DroidBox/Resources/j2mejs" "$APP_RESOURCES/j2mejs"
rm -rf "$APP_RESOURCES/ManicJ2MESkin"
ditto "$SRCROOT/DroidBox/Resources/ManicJ2MESkin" "$APP_RESOURCES/ManicJ2MESkin"
ditto "$SRCROOT/THIRD_PARTY_NOTICES.md" "$APP_RESOURCES/THIRD_PARTY_NOTICES.md"

if [ "$PLATFORM_NAME" = "iphonesimulator" ]; then
  SLICE="ios-arm64_i386_x86_64-simulator"
else
  SLICE="ios-arm64_armv7"
fi
ditto "$RUNTIME/Frameworks/MetalANGLE.xcframework/$SLICE/MetalANGLE.framework" \
  "$APP_FRAMEWORKS/MetalANGLE.framework"
