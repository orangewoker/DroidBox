#!/usr/bin/env bash
set -euo pipefail
MANIFEST="${1:-Runtimes/manifests/lineage-arm64-default.json}"
URL="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["downloadURL"])' "$MANIFEST")"
SHA="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["sha256"])' "$MANIFEST")"
test "$URL" != "RELEASE_ASSET_URL_REQUIRED"
mkdir -p Runtimes/downloads
curl -fL --retry 3 -C - "$URL" -o Runtimes/downloads/android-runtime.zip
echo "$SHA  Runtimes/downloads/android-runtime.zip" | shasum -a 256 -c -

