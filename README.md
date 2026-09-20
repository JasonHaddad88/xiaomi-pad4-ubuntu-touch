# Ubuntu Touch port — Xiaomi Mi Pad 4 (`clover`)

A from-scratch [Ubuntu Touch](https://ubuntu-touch.io/) / [UBports](https://ubports.com/) port for the
Xiaomi Mi Pad 4 & Mi Pad 4 Plus (codename **`clover`**, Qualcomm Snapdragon 660 / SDM660).

## Target

| Layer | Choice | Why |
|-------|--------|-----|
| Hardware base | **Halium 9.0** (Android 9 / LineageOS 16, `sdm660-common`) | Most proven base for this SoC; shared with the active [`lavender`](https://devices.ubuntu-touch.io/device/lavender/) port and the 2021 clover port. |
| OS / rootfs | **Ubuntu Touch Noble (24.04)** | The "modern" UT. The rootfs rides on top of Halium and is largely independent of the Android base version — `lavender` (same SoC) runs Noble on a Halium-9 base. |
| Build host | **WSL2 (Ubuntu) on Windows 11** | 24-core / 31 GB machine; build in the ext4 home, flash from Windows. |

> Strategy: get a stable first boot on the well-trodden Halium-9 SDM660 base, then iterate hardware
> bring-up and stabilize on Noble. See [docs/roadmap.md](docs/roadmap.md).

## This repo is the *coordination hub*, not the build tree

The multi-GB Halium/Android source tree and built images live inside **WSL2** (ext4), not here.
This Windows folder holds the plan, device facts, the `local_manifest`, helper scripts, notes, and the
running log — text we author and version-control.

## Contents

- [docs/roadmap.md](docs/roadmap.md) — phased plan & milestones
- [docs/device-clover.md](docs/device-clover.md) — device hardware facts & partition layout
- [docs/build-environment.md](docs/build-environment.md) — WSL2 + Halium build-env setup (start here)
- [docs/sources.md](docs/sources.md) — upstream repos & references we build from
- [docs/porting-log.md](docs/porting-log.md) — chronological log of decisions, attempts, fixes
- `manifests/` — `local_manifest` (which repos `repo sync` pulls) — *created in Phase 1*
- `scripts/` — helper scripts — *as needed*

## Status

🟢 **Phase 4 — Ubuntu Touch boots with display + touch (2026-09-19).** Ubuntu Touch 16.04 on our own Halium-9
build (kernel `4.4.153`, Adreno 512 GPU via libhybris, Mir at 1200×1920) runs on the tablet; touch works; SSH
over USB tethering (`ssh phablet@10.15.19.82`). Installed **without TWRP** (it hangs on this unit) via the
halium initrd debug shell — full method in [docs/porting-log.md](docs/porting-log.md), tools in
[scripts/device/](scripts/device/).

**Working (2026-09-20):** display + touch, GPU, Wi-Fi, battery reading, screen turn-off, brightness slider,
loud audio, charging while off. **Not working:** rotation (the sensors work, but the vendor HAL cannot
serve both sensorfw and android's sensorservice - attempting it cost screen turn-off and stability, so
it is reverted), camera. **Untested:** Bluetooth, suspend/resume and battery drain.
Every applied fix, with its exact revert command, is in [device-fixes/README.md](device-fixes/README.md).
Next: camera and the remaining unknowns per [docs/roadmap.md](docs/roadmap.md), then the Noble rootfs.
