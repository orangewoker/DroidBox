#!/usr/bin/env bash
set -euo pipefail
command -v xcodebuild >/dev/null
command -v zip >/dev/null
xcodebuild -version
"$(cd "$(dirname "$0")" && pwd)/prepare-renpy-runtime.sh"
echo "DroidBox Ren'Py 8.4.1 runtime is ready."
