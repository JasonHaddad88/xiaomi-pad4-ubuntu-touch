# Sources & references

## Official docs (authoritative — verify commands here as we go)
- UBports porting guide — https://docs.ubports.com/en/latest/porting/introduction/
- Halium docs (porting / first steps) — https://docs.halium.org/en/latest/porting/first-steps.html
- Halium install (boot + GSI + rootfs) — https://docs.ubports.com/en/latest/porting/build_and_boot/Halium_install.html
- Halium manifest (android) — https://github.com/Halium/android  (branch `halium-9.0`)

## SDM660 / clover ecosystem we build from
- **`sdm660-common` (Halium, SDM660):** https://github.com/ubports-xiaomi-sdm660
  - `android_device_xiaomi_sdm660-common`
  - `android_kernel_xiaomi_sdm660` (Halium boot kernel, updated 2023)
  - `android_vendor_xiaomi_sdm660-common`
  - `hybris-boot`, `local_manifests`
- **Reference port — Redmi Note 7 `lavender` (same SoC, has Noble):**
  https://devices.ubuntu-touch.io/device/lavender/ · org: https://github.com/ubports-lavender
- **Old clover UT port (Halium 9, abandoned 2021 — reference only):**
  https://github.com/ubuntu-touch-clover
  - `halium_device_xiaomi_clover`, `halium_kernel_xiaomi_clover`, `halium_vendor_xiaomi_clover`, `ubports-ci`
- **Active clover LineageOS trees (for device-tree material):**
  - https://github.com/kyasu/android_device_xiaomi_clover
  - https://github.com/kyasu/android_device_xiaomi_sdm660-common
  - https://github.com/kyasu/android_kernel_xiaomi_sdm660
  - LOS 22/23 (Android 15/16) thread: https://xdaforums.com/t/rom-15-16-clover-lineageos-22-23-for-xiaomi-mi-pad-4-unofficial.4514507/

## Community threads
- Ubuntu Touch Mi Pad 4 (GSI) — https://xdaforums.com/t/gsi-arm64-a-ab-ubuntu-touch-mi-pad-4-plus.4351699/
- Focal build for Xiaomi clover (UBports forum) — https://forums.ubports.com/topic/9395/focal-build-for-xiaomi-clover
- Noble status update (Dec 2024) — https://forums.ubports.com/topic/10675/

## Tools
- usbipd-win (USB → WSL2) — https://github.com/dorssel/usbipd-win
- UBports Installer — https://devices.ubuntu-touch.io/installer/
