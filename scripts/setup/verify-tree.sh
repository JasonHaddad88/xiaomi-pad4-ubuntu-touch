#!/usr/bin/env bash
# Verify the synced Halium tree is build-ready for clover. Read-only.
#   wsl -e bash -c "tr -d '\r' < <this> | bash -s"
set -uo pipefail
cd "$HOME/halium/halium-9.0" || exit 1
echo "=== top-level build pieces ==="
for d in build/make build/soong halium hybris-patches vendor/halium \
         device/xiaomi/clover kernel/xiaomi/clover vendor/xiaomi/clover; do
  if [ -e "$d" ]; then printf "OK   %-26s (%s entries)\n" "$d" "$(ls -1 "$d" 2>/dev/null | wc -l)"; else printf "MISS %-26s\n" "$d"; fi
done
echo "=== key files ==="
for f in build/envsetup.sh hybris-patches/apply-patches.sh \
         device/xiaomi/clover/BoardConfig.mk; do
  [ -f "$f" ] && echo "OK   $f" || echo "MISS $f"
done
echo "=== clover device makefiles ==="
ls device/xiaomi/clover/*.mk 2>/dev/null || echo "(none)"
echo "=== clover kernel defconfig(s) ==="
find kernel/xiaomi/clover -name '*clover*defconfig' 2>/dev/null | head
echo "=== does clover depend on sdm660-common? ==="
hits=$(grep -rsl 'sdm660-common\|sdm660_common' device/xiaomi/clover 2>/dev/null | head)
[ -n "$hits" ] && { echo "YES — referenced in:"; echo "$hits"; } || echo "no direct reference found"
echo "=== sdm660-common trees present? ==="
ls -d device/xiaomi/sdm660-common kernel/xiaomi/sdm660 vendor/xiaomi/sdm660-common 2>/dev/null || echo "(none synced — may need adding to local_manifest)"
echo "=== AndroidProducts / product name sanity ==="
grep -rhs 'PRODUCT_NAME\|PRODUCT_DEVICE' device/xiaomi/clover/*.mk 2>/dev/null | head
