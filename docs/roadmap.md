# Roadmap — clover Ubuntu Touch port

A realistic, phased plan. Each phase has a **milestone** that proves it worked before moving on.
This is a multi-week project; bring-up (Phase 4+) is where most time goes.

---

## Phase 0 — Environment & device prep  ✅
- [x] Scaffold workspace + docs + git
- [ ] Install Windows **adb/fastboot**; confirm the tablet is detected (Task #2)
- [ ] Capture **device facts** — partitions, A/B, fstab, current ROM (Task #3)
- [ ] Install **WSL2 + Ubuntu**; set up the Halium build environment (Task #4)

**Milestone:** WSL2 builds "hello world", device shows up in `fastboot devices`.

## Phase 1 — Sources
- [ ] `repo init` the **Halium 9.0** manifest
- [ ] Write **`local_manifest/clover.xml`** pulling clover + `sdm660-common` device/vendor/kernel trees
- [ ] `repo sync` the full tree (Task #5)

**Milestone:** `breakfast clover` resolves with no missing repos.

## Phase 2 — halium-boot
- [ ] Apply hybris patches; adapt `BoardConfig`/fstab for Halium
- [ ] `mer-kernel-check` → enable required kernel configs
- [ ] Build **`halium-boot.img`** (Task #6)

**Milestone:** Flash halium-boot; reach the initrd debug shell over **telnet (5555)** / adb.

## Phase 3 — system.img + rootfs
- [ ] **Back up first:** full TWRP backup (boot/system/vendor/data) as a restore point
- [ ] **Base prep:** device runs PE13 (dynamic partitions / Android 13). Get to an Android-9-consistent
      base for Halium — try Halium's own vendor first; fall back to flashing LOS16 firmware/base
      (see [device-clover.md](device-clover.md) Phase 3 plan)
- [ ] Build Halium **`system.img`** (`hybris-hal`) (Task #7)
- [ ] Download UBports **Noble** rootfs; assemble & flash from Windows fastboot (Task #8)

**Milestone:** Device powers into Halium; reachable over **ssh/telnet**, `/android` HAL mounts.

## Phase 4 — First boot bring-up
- [ ] Display (Mir + hwcomposer) + **touch** → usable UI (Task #9)
- [ ] Then iterate: **WiFi, Bluetooth, audio, sensors, GPU, battery, cameras** (Task #10)

**Milestone:** Ubuntu Touch UI on screen, responds to touch, connects to WiFi. ✅ **Reached 2026-09-19** *(we are here)*

**Bring-up status (2026-09-20):** ✅ display + touch, GPU (Adreno 512), Wi-Fi, battery reading,
**screen turn-off**, **brightness slider**, **audio** (loud), charging while off ·
🟡 **rotation** - all 30 sensors work (accelerometer, gyroscope, light, hall effect) but sensorfw and
android's sensorservice cannot both hold the sensors HAL, so rotation and screen turn-off are
currently mutually exclusive; screen turn-off is the one enabled (one-line swap, see device-fixes) ·
❌ **camera** · ❓ Bluetooth, suspend/resume + battery drain.
Rule: full backup of the working state first, then one reversible fix at a time.
All applied fixes and their exact revert commands: [`device-fixes/README.md`](../device-fixes/README.md).

## Phase 5 — Stabilize & ship
- [ ] Fix Noble-specific issues; document working/broken features
- [ ] Package images; installer/CI config; optionally submit upstream (Task #11)

**Milestone:** Reproducible build + install; daily-driver-ish device.

## Future suggestions / features
- **Dark mode** (system-wide dark theme in the Lomiri UI)

---

### Known hard parts (set expectations)
- **Kernel config** for Halium (mer-kernel-check) — fiddly but mechanical.
- **Display/graphics** (hwcomposer/Mir, Adreno 512) — classic first-boot blocker.
- **Audio routing** (PulseAudio + Android HAL) — finicky. *(Modem/RIL/telephony OUT of scope — WiFi-only unit.)*
- USB passthrough: flash from **Windows**, not WSL2 (or use `usbipd-win`).
