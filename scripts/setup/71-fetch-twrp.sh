#!/usr/bin/env bash
# Fetch clover TWRP 3.7.0 into the Windows flash kit. TWRP's site gates the binary (referer) / serves HTML
# download pages, so try several mirrors and verify the Android boot magic (ANDR = 41 4e 44 52).
#   wsl -e bash -c "tr -d '\r' < <this> | bash -s"
set -uo pipefail
DST="/mnt/c/Users/User/Desktop/Projects/Xiaomi Pad 4 Ubuntu Touch/flash"
OUT="$DST/twrp-3.7.0_9-0-clover.img"
mkdir -p "$DST"
is_android() { [ "$(head -c4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' ')" = "414e4452" ]; }
urls=(
  "https://eu.dl.twrp.me/clover/twrp-3.7.0_9-0-clover.img"
  "https://dl.twrp.me/clover/twrp-3.7.0_9-0-clover.img"
  "https://sourceforge.net/projects/twrp/files/clover/twrp-3.7.0_9-0-clover.img/download"
  "https://master.dl.sourceforge.net/project/twrp/clover/twrp-3.7.0_9-0-clover.img"
)
ok=0
for u in "${urls[@]}"; do
  echo "== trying: $u"
  if curl -fsL --retry 10 --retry-all-errors --retry-delay 3 -A 'Mozilla/5.0' -e 'https://twrp.me/clover/' -o "$OUT" "$u"; then
    sz=$(stat -c%s "$OUT" 2>/dev/null || echo 0)
    if is_android "$OUT"; then echo "  OK: Android image, $sz bytes"; ok=1; break; else echo "  got non-image ($sz bytes)"; fi
  else
    echo "  curl failed"
  fi
done
if [ "$ok" = 1 ]; then
  echo "TWRP staged -> $OUT ($(stat -c%s "$OUT") bytes)"
else
  rm -f "$OUT"
  echo "TWRP AUTO-FETCH FAILED — grab it manually at flash time from https://twrp.me/clover/ (twrp-3.7.0_9-0-clover.img) into: $DST"
fi
