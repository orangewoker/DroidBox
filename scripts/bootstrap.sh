#!/usr/bin/env bash
set -euo pipefail
command -v xcodebuild >/dev/null
command -v zip >/dev/null
xcodebuild -version
echo "DroidBox uses only Apple system frameworks for the base build."

