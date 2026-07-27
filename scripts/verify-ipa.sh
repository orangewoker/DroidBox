#!/usr/bin/env bash
set -euo pipefail
IPA="${1:?usage: verify-ipa.sh path/to/DroidBox-unsigned.ipa}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unzip -q "$IPA" -d "$TMP"
APP="$TMP/Payload/DroidBox.app"
test -d "$APP"
test ! -e "$APP/embedded.mobileprovision"
NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Info.plist")"
MIN="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APP/Info.plist")"
test "$NAME" = "DroidBox"
test "$MIN" = "18.0"
file "$APP/DroidBox" | grep -q 'arm64'
test -f "$APP/j2mejs/index.html"
test -f "$APP/j2mejs/java/classes.jar"
if codesign -dvv "$APP" >/dev/null 2>&1; then echo "Unexpected code signature" >&2; exit 1; fi
if otool -L "$APP/DroidBox" | grep -E '/Users/|/Volumes/|DerivedData'; then echo "Developer path found" >&2; exit 1; fi
echo "Verified unsigned DroidBox IPA: arm64, iOS $MIN, no provisioning profile"
