#!/bin/bash
# Captures each ThirdTimer window to proof/<prefix>-<kind>.png and prints
# small previews into the log as base64 JPEG.
set -euo pipefail
prefix="$1"
swift "$(dirname "$0")/windows.swift" > "proof/$prefix-windows.txt"
cat "proof/$prefix-windows.txt"
grep -q " 25 " "proof/$prefix-windows.txt"   # the menu bar item exists
while read -r id layer x y w h; do
  kind=window; [ "$layer" = "25" ] && kind=menubar
  screencapture -x -o -l "$id" "proof/$prefix-$kind.png"
  sips -s format jpeg -s formatOptions 45 -Z 560 "proof/$prefix-$kind.png" --out "/tmp/$prefix-$kind.jpg" >/dev/null
  echo "PREVIEW $prefix-$kind $(base64 -i "/tmp/$prefix-$kind.jpg" | tr -d '\n')"
done < "proof/$prefix-windows.txt"
