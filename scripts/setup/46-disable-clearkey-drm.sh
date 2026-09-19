#!/usr/bin/env bash
# The ClearKey @1.1 DRM HIDL service fails to build in this LineageOS-16 frameworks/av:
# DrmPlugin.h references type `DeviceFiles`, which does not exist anywhere in the clearkey plugin
# (incomplete tree). ClearKey software-DRM is non-essential for a Halium first boot, so drop the
# service from clover PRODUCT_PACKAGES (keeps drm@1.0-impl / drm@1.0-service). Idempotent; .orig backup.
#   wsl -e bash -c "tr -d '\r' < <this> | bash -s"
set -uo pipefail
F="$HOME/halium/halium-9.0/device/xiaomi/clover/device.mk"
if grep -q 'drm@1.1-service.clearkey' "$F"; then
  cp -n "$F" "$F.orig"
  sed -i '/android.hardware.drm@1.1-service.clearkey/d' "$F"          # remove the broken service
  sed -i 's/\(android.hardware.drm@1.0-service\) \\$/\1/' "$F"        # drop now-dangling line continuation
  echo "removed android.hardware.drm@1.1-service.clearkey from clover PRODUCT_PACKAGES"
else
  echo "clearkey @1.1 service already removed"
fi
echo "--- DRM block now ---"
grep -n -A4 '# DRM' "$F" | head -8
