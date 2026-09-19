#!/usr/bin/env bash
# Download the UBports Ubuntu Touch rootfs for the Halium-9 arm64 install (~556 MB).
# Resumable (curl -C -) + retries. Lands in ~/halium/install/. Run detached for the long pull.
#   wsl -e bash -c "tr -d '\r' < <this> | bash -s"
set -uo pipefail
D="$HOME/halium/install"
mkdir -p "$D"; cd "$D"
URL="https://ci.ubports.com/job/xenial-hybris-android9-rootfs-arm64/lastSuccessfulBuild/artifact/ubuntu-touch-android9-arm64.tar.gz"
OUT="ubuntu-touch-android9-arm64.tar.gz"
LOG="$D/rootfs-dl.log"
{
  echo "=== rootfs download START $(date -u) ==="
  curl -fL -C - --retry 30 --retry-all-errors --retry-delay 5 -A 'Mozilla/5.0' -o "$OUT" "$URL"
  rc=$?
  echo "=== rootfs download EXIT rc=$rc $(date -u) ==="
  ls -la "$OUT" 2>/dev/null
  echo -n "gzip magic (expect 1f 8b): "; head -c2 "$OUT" | od -An -tx1
  echo "expected size: 583495849 bytes"
} 2>&1 | tee "$LOG"
