# Phase 3 — install / flash runbook (clover)

> Status: **planning + prep.** Both images are built; this is the procedure for getting them (plus the UT
> rootfs) onto the tablet. Several steps need the tablet + the one-time fastboot driver, so this is the
> runbook we execute once those are ready — not yet done.

## Inputs
| Input | State |
|---|---|
| `halium-boot.img` (52 MB) | ✅ built — `~/halium/halium-9.0/out/target/product/clover/halium-boot.img` |
| `system.img` (217 MB) | ✅ built — same dir |
| UT rootfs `ubuntu-touch-android9-arm64.tar.gz` — **556 MB** | ✅ downloaded + verified (gzip OK, 583495849 B) → `~/halium/install/` |
| `halium-install` | ✅ `~/halium/tools/halium-install` (gitlab.com/JBBgameich/halium-install) |
| Built images staged for Windows fastboot | ✅ `flash/halium-boot.img` + `flash/system.img` |
| Windows fastboot WinUSB driver | ❌ **Task #7** (`tools/zadig-2.9.exe`) — REQUIRED to flash |
| clover **TWRP** `twrp-3.7.0_9-0-clover.img` (3.7.0, 2022-10-06) | ⚠ **download MANUALLY** at flash time from <https://twrp.me/clover/> into `flash/` — TWRP's site is JS/referer-gated (curl only gets HTML) |

## ⚠ Two blockers from the device's current state (2026-06-04 dump)
1. **/data is ENCRYPTED** (`ro.crypto.state=encrypted`, file-based). `halium-install` needs `/data` as
   **unencrypted ext4**, so we must **Format Data** in recovery — which **ERASES everything on the tablet's
   internal storage**. Back up anything wanted first.
2. **Recovery is probably PE's own, not TWRP** (recovery adb came up *unauthorized*, no busybox/root —
   2026-06-04). `halium-install` pushes files via a **busybox recovery (TWRP)** over adb, so we must
   **flash a clover TWRP** to `recovery` (p51) first.

## Prerequisites checklist
- [ ] **Task #7**: `fastboot devices` lists `XXXXXXXX` (Zadig WinUSB bound to 18D1:D00D).
- [ ] **Task #1**: `fastboot getvar unlocked` → `yes`; capture `fastboot getvar all` (confirm p13/p14 sizes fit 217 MB — they will).
- [ ] Clover **TWRP** image downloaded + verified.
- [ ] **Backup** taken (Format Data below wipes the tablet).
- [ ] Rootfs downloaded (556 MB): `curl -fL --retry 20 --retry-all-errors -o ubuntu-touch-android9-arm64.tar.gz 'https://ci.ubports.com/job/xenial-hybris-android9-rootfs-arm64/lastSuccessfulBuild/artifact/ubuntu-touch-android9-arm64.tar.gz'`
- [ ] Decide WSL↔Windows USB path (see below).

## Procedure (UBports Halium-9 flow)
1. `adb reboot bootloader` (or hold Vol-Down+Power) → fastboot.
2. *(Recommended)* `fastboot flash recovery twrp-clover.img`; boot TWRP; **TWRP → Backup** boot/system/vendor/data to PC/SD.
3. In **TWRP → Wipe → Format Data** (removes encryption). Reboot back to TWRP. Confirm `/data` is ext4 + unencrypted.
4. Install rootfs + system (device in TWRP with adb; from WSL this needs **usbipd-win** so WSL can see the
   device — see below). First install halium-install's host deps in WSL:
   ```
   sudo apt install -y qemu-user-static binfmt-support e2fsprogs android-sdk-libsparse-utils
   ```
   Then run it — note **`system.img` is the LAST positional arg**, and **`-s` is the system-as-root flag**
   (verified from `halium-install --help`), not the system-image option:
   ```
   ~/halium/tools/halium-install/halium-install -p ut20.04 -s -m img \
       ~/halium/install/ubuntu-touch-android9-arm64.tar.gz \
       ~/halium/halium-9.0/out/target/product/clover/system.img
   ```
   - `-s`/`--system-as-root` ✅ (clover is system-as-root) · `-m img` = install as an image on `/data`
     (supported by all halium initramfs) · `-p ut20.04` = UT post-install (try `ut16.04` if the rootfs turns
     out xenial-based — the CI job is named `xenial-…`). It pushes rootfs **and** the system image to `/data`
     over adb — so **no separate `fastboot flash system`** needed.
5. `fastboot flash boot halium-boot.img` (→ boot p12).
6. `fastboot reboot`.

## First boot → Phase 4
- The halium-boot **initrd** opens a debug shell over **telnet `<device-ip>:5555`** (USB-RNDIS, often `10.15.19.82`).
- Once the rootfs hands off: `adb shell` / `ssh phablet@…`; check `/android` HAL mount, then Mir + hwcomposer
  + touch (`fts_ts`). See [roadmap.md](roadmap.md) Phase 4.

## WSL ↔ Windows USB boundary
WSL2 has no native USB. Two options (also in [build-environment.md](build-environment.md)):
- **Simple:** copy `*.img` to Windows and run **`fastboot` from Windows** (where the Zadig driver lives). For
  `halium-install` (needs adb to TWRP), run its steps with Windows `adb`, or:
- **Integrated:** `usbipd-win` (`winget install usbipd`) → `usbipd attach --wsl` to expose the device to WSL,
  then run `halium-install` and `fastboot` inside WSL.

## Open questions to resolve at flash time
- ~~`halium-install` system-as-root behavior~~ → **resolved:** use `-s --system-as-root -m img`; it puts the
  system image on `/data` (no `fastboot flash system`). Open: `-p ut20.04` vs `ut16.04` (depends on rootfs base).
- Clover **TWRP** version that can Format-Data on this PE13 / 4.19 state.
- Best USB path for `halium-install` (usbipd-win vs manual Windows-adb push).
- **Noble:** first boot uses the proven `android9-arm64` (Focal-era) rootfs; moving to **Noble (24.04)** is the
  later stabilization step (per [roadmap.md](roadmap.md) / the same-SoC `lavender` Noble channel).
