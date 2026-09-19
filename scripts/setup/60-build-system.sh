#!/usr/bin/env bash
# Phase 3: build the Halium system image (hybris-hal + systemimage). Long job — launch detached.
# Logs to system-build.log.  (NOT -u: envsetup references unset vars.)
#   (relaunch) wsl -e bash -c "setsid bash ~/halium/run-system.sh >/dev/null 2>&1 </dev/null & wait"
set -o pipefail
cd "$HOME/halium/halium-9.0" || exit 1
export PATH=/opt/halium-py2bin:$PATH   # AOSP-9 wants python==python2 (build-local; system python stays py3)
export USE_CCACHE=1
export LC_ALL=C
source build/envsetup.sh >/dev/null 2>&1
breakfast clover >/dev/null 2>&1
LOG="$HOME/halium/halium-9.0/system-build.log"
{
  echo "=== build systemimage START $(date -u) ==="
  echo "host: $(uname -r)  jobs: $(nproc)"
  mka systemimage
  rc=$?
  echo "=== system EXIT rc=$rc $(date -u) ==="
  ls -la out/target/product/clover/system.img 2>/dev/null || echo "(no system.img produced)"
} 2>&1 | tee "$LOG"
