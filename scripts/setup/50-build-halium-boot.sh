#!/usr/bin/env bash
# Phase 2: build halium-boot.img (kernel clover_halium_defconfig + hybris ramdisk).
# Long job — launch detached. Logs to halium-boot-build.log.
#   (resume/relaunch) wsl -e bash -c "setsid bash ~/halium/run-build.sh >/dev/null 2>&1 </dev/null & wait"
set -o pipefail   # NOT -u: build/envsetup.sh references unset vars and would abort under nounset
cd "$HOME/halium/halium-9.0" || exit 1
export USE_CCACHE=1
export LC_ALL=C
source build/envsetup.sh >/dev/null 2>&1
breakfast clover >/dev/null 2>&1
LOG="$HOME/halium/halium-9.0/halium-boot-build.log"
{
  echo "=== build halium-boot START $(date -u) ==="
  echo "host: $(uname -r)  jobs: $(nproc)"
  mka halium-boot
  rc=$?
  echo "=== halium-boot EXIT rc=$rc $(date -u) ==="
  echo "--- boot artifacts (if any) ---"
  ls -la out/target/product/clover/*boot*.img 2>/dev/null || echo "(no boot image produced)"
} 2>&1 | tee "$LOG"
