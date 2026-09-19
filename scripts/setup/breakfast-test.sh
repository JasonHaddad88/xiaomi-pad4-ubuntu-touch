#!/usr/bin/env bash
# Ground-truth the Task #3 milestone: does `breakfast clover` resolve on this tree/host?
#   wsl -e bash -c "tr -d '\r' < <this> | bash -s"
cd "$HOME/halium/halium-9.0" || exit 1
echo "=== halium/ contents ==="; ls halium/
echo "=== vendor/ subdirs ==="; ls vendor/ 2>/dev/null
echo "=== device/xiaomi/clover/vendorsetup.sh? ==="; ls device/xiaomi/clover/vendorsetup.sh 2>/dev/null || echo "(none)"
echo "=== sourcing build/envsetup.sh (no pipe — defines funcs in THIS shell) ==="
source build/envsetup.sh > /tmp/envsetup.log 2>&1
echo "(envsetup last lines:)"; tail -8 /tmp/envsetup.log
echo "=== breakfast / lunch defined? ==="
type breakfast 2>/dev/null | head -1 || echo "breakfast: NOT defined"
type lunch 2>/dev/null | head -1 || echo "lunch: NOT defined"
echo "=== run: breakfast clover ==="
breakfast clover > /tmp/breakfast.log 2>&1
rc=$?
echo "breakfast exit rc=$rc"
echo "--- breakfast.log tail 60 ---"
tail -60 /tmp/breakfast.log
