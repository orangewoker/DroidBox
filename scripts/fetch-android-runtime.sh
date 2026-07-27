#!/usr/bin/env bash
set -euo pipefail
BASE="https://github.com/orangewoker/DroidBox/releases/download/android-runtime-v1"
NAME="DroidBox-Android-x86_64-9.0-r2-droidbox.1-runtime.zip"
mkdir -p Runtimes/downloads
curl -fL --retry 5 -C - "$BASE/$NAME" -o "Runtimes/downloads/$NAME"
curl -fL --retry 5 "$BASE/$NAME.sha256" -o "Runtimes/downloads/$NAME.sha256"
(cd Runtimes/downloads && shasum -a 256 -c "$NAME.sha256")
