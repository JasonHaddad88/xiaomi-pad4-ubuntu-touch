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

- **[docs/how-this-port-works.md](docs/how-this-port-works.md) — start here.** The whole system
  explained from scratch: what every component is, how it was built and installed, what broke and why,
  and the rules that came out of it. Assumes no Android-porting knowledge.
- [docs/roadmap.md](docs/roadmap.md) — phased plan & milestones
- [docs/device-clover.md](docs/device-clover.md) — device hardware facts & partition layout
- [docs/build-environment.md](docs/build-environment.md) — WSL2 + Halium build-env setup (start here)
- [docs/sources.md](docs/sources.md) — upstream repos & references we build from
- [docs/porting-log.md](docs/porting-log.md) — chronological log of decisions, attempts, fixes
- `manifests/` — `local_manifest` (which repos `repo sync` pulls) — *created in Phase 1*
- `scripts/` — helper scripts — *as needed*

## Status

🟢 **Phase 5 — running Ubuntu Touch 24.04 (noble) on Halium 9 (2026-09-20).** Upgraded from the 16.04
rootfs to `24.04-1.x/arm64/android9plus/stable`, keeping our own Halium-9 boot and system images; the
old rootfs is kept on the device as `rootfs.img.xenial` for a two-rename rollback. Ubuntu Touch on our own Halium-9
build (kernel `4.4.153`, Adreno 512 GPU via libhybris, Mir at 1200×1920) runs on the tablet; touch works; SSH
over USB tethering (`ssh phablet@10.15.19.82`). Installed **without TWRP** (it hangs on this unit) via the
halium initrd debug shell — full method in [docs/porting-log.md](docs/porting-log.md), tools in
[scripts/device/](scripts/device/).

**Now on Ubuntu Touch 24.04** (channel `24.04-1.x/arm64/android9plus/stable`) — see
[docs/upgrade-2404.md](docs/upgrade-2404.md).

**Working (2026-09-26):** display + touch, GPU, Wi-Fi, audio (loud), battery reading, charging while
off, screen dim/blank/wake with a correct backlight range, brightness slider, all 30 sensors,
**rotation**, Morph browser, Libertine desktop apps, and the **camera**.
**Untested:** Bluetooth (deliberately masked), suspend/resume and battery drain.
Current device state and every md5 is in
[device-fixes/INSTALLED-STATE-2404.md](device-fixes/INSTALLED-STATE-2404.md); each fix with its exact
revert command is in [device-fixes/README.md](device-fixes/README.md).
