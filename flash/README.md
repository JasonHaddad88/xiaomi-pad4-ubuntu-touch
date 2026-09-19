# Flash kit — clover (Ubuntu Touch / Halium-9)

Built artifacts staged for flashing. **Full runbook: [../docs/flashing.md](../docs/flashing.md).**
(The `*.img` here are git-ignored — re-copy from WSL `out/target/product/clover/` if missing.)

## In this folder
- `halium-boot.img` (52 MB) → `fastboot flash boot` (p12)
- `system.img` (217 MB) → `system` partition (p13)
- `twrp-3.7.0_9-0-clover.img` → ⚠ **download manually** from <https://twrp.me/clover/> and drop it here.
  (TWRP's site is JS/referer-gated, so it can't be scripted with curl — but it's a one-click browser download.)

The UT rootfs `ubuntu-touch-android9-arm64.tar.gz` lives in **WSL** (`~/halium/install/`) — it's consumed by
`halium-install`, not flashed via fastboot.

## Before flashing
1. **Fastboot driver** — Task #7 ([../docs/fastboot-driver-windows.md](../docs/fastboot-driver-windows.md)); run `tools/zadig-2.9.exe` as admin, bind WinUSB to `18D1:D00D`.
2. ⚠ **Back up the tablet** — the install **wipes `/data`** (it's encrypted → must Format Data in TWRP).
3. **Download TWRP** into this folder (link above).

Then follow the step-by-step in [../docs/flashing.md](../docs/flashing.md).
