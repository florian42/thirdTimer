#!/bin/bash
# Builds Third Timer, copies it to /Applications and starts it.
set -euo pipefail
cd "$(dirname "$0")"

./build-app.sh
pkill -x ThirdTimer 2>/dev/null || true
rm -rf /Applications/ThirdTimer.app
cp -R build/ThirdTimer.app /Applications/ThirdTimer.app
open /Applications/ThirdTimer.app
echo "Third Timer is running. Look for it in the menu bar."
