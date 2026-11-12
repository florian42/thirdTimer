#!/bin/bash
# Captures each ThirdTimer window to proof/<prefix>-<kind>.png, then prints
# the text macOS can read in each capture, so the log shows what was drawn.
set -euo pipefail
prefix="$1"
here="$(dirname "$0")"
swift "$here/windows.swift" > "proof/$prefix-windows.txt"
cat "proof/$prefix-windows.txt"
grep -q " 25 " "proof/$prefix-windows.txt"   # the menu bar item exists
# It must also be on screen: macOS pushes an item that is too wide off the menu bar.
awk '$2 == 25 && $3 < 0 { print "menu bar item is off screen:", $0; bad = 1 } END { exit bad }' "proof/$prefix-windows.txt"
while read -r id layer x y w h; do
  kind=window; [ "$layer" = "25" ] && kind=menubar
  screencapture -x -o -l "$id" "proof/$prefix-$kind.png"
  # Enlarge before reading: the CI screen is low resolution.
  sips -Z $(( (w > h ? w : h) * 3 )) "proof/$prefix-$kind.png" --out "/tmp/$prefix-$kind-large.png" >/dev/null
  echo "TEXT ON SCREEN: $prefix $kind (${w}x${h})"
  swift "$here/ocr.swift" "/tmp/$prefix-$kind-large.png"
done < "proof/$prefix-windows.txt"
