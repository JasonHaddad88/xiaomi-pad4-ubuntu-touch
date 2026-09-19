#!/usr/bin/env bash
# Make halium-boot's generic-initramfs download resilient to flaky connectivity.
# Upstream halium/halium-boot/get-initrd.sh does a single `curl ... --silent` (no retry, no --fail),
# so one network blip fails the whole halium-boot build. Patch adds retries + --fail + timeout.
# Idempotent; keeps a .orig backup.  Run before 50-build-halium-boot.sh.
#   wsl -e bash -c "tr -d '\r' < <this> | bash -s"
set -uo pipefail
F="$HOME/halium/halium-9.0/halium/halium-boot/get-initrd.sh"
if grep -q -- '--retry' "$F"; then
  echo "get-initrd.sh already patched (has --retry)"
else
  cp -n "$F" "$F.orig"
  sed -i '33s|.*|curl --location "$LINK_FULL" --output "$TARGET" --silent --fail --retry 20 --retry-all-errors --retry-delay 3 --connect-timeout 30|' "$F"
  echo "patched get-initrd.sh line 33"
fi
echo "--- lines 30-33 now ---"
sed -n '30,33p' "$F"
