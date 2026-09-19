# Device facts — Xiaomi Mi Pad 4 / 4 Plus (`clover`)

Model-level facts come from the clover device trees + community docs. A **full live dump was taken
from this unit on 2026-06-04** (raw artifacts in [`dumps/`](dumps/)); the confirmed on-device facts are
consolidated in the section directly below. The only things still genuinely needing the tablet are the
**physical `system`/`vendor` partition sizes** and a **definitive bootloader-unlock check** — both need
`fastboot` (bootloader mode) because `/proc/partitions` is root-only on the PE13 user build.

## Live dump — 2026-06-04 (confirmed on this unit, serial `XXXXXXXX`)

- **Identity:** `clover` / "Mi PAD 4", Xiaomi. This unit = **4 GB RAM / 64 GB** (`MemTotal` 3.76 GB;
  `/data` 51 GB), **WiFi-only** ⇒ the regular **Mi Pad 4** (the *Plus* was LTE-only). Not a Plus.
- **Silicon: `SDA660`** — the **modem-less** variant of SDM660 (`ro.boot.baseband=sda`; `/proc/cpuinfo`
  Hardware = "Qualcomm Technologies, Inc **SDA660**"). `ro.board.platform=sdm660`. This is *why* there's
  no telephony at the hardware level.
- **CPU/GPU:** 8× Kryo 260 (4× big `0x801` + 4× little `0x800`), **Adreno 512**, OpenGL ES **3.2**
  (`0x30002`), **Vulkan 1.1** (+AEP). `ro.hardware.egl/vulkan = adreno`.
- **Display:** **1200×1920** (portrait-native), density **320**. Touch = **`fts_ts`** (FocalTech),
  10-point, axes X 0–1200 / Y 0–1920, `INPUT_PROP_DIRECT`.
- **Kernel:** **`4.19.294-ga64e6b49d671`** aarch64 SMP PREEMPT, clang 14.0.6, built 2023-09-26.
- **Current ROM:** **PixelExperience 13** OFFICIAL `20230926-1341`, security patch 2023-09-01, SDK 33,
  VNDK 33.
- **Partitions = retrofit dynamic, NON-A/B (live-confirmed):** `ro.boot.dynamic_partitions=true`,
  `…_retrofit=true`, `ro.boot.super_partition=system`. Logical `system`→`dm-0` (1.9 GB, mounted `/`,
  system-as-root) and `vendor`→`dm-1` (249 MB) live inside `super`. **Physical GPT by-name:**
  `boot`→`mmcblk0p12`, `recovery`→`p51`, **`system`→`p13`**, **`vendor`→`p14`**, `cache`→`p49`,
  `persist`→`p48`, `userdata`→`p64` (51 GB), `modem`→`p25`, `dsp`→`p27`, `cust`→`p62`, `misc`→`p50`.
  No `_a/_b` slots (firmware `*bak` partitions are backups, not A/B). → Halium-9 legacy images flash to
  the **physical** `p13`/`p14`; sizes of those still to confirm via fastboot.
- **⚠ Bootloader/AVB — verify before flashing:** props report a **locked** state
  (`flash.locked=1`, `vbmeta.device_state=locked`, `verifiedbootstate=green`, `oem_unlock_allowed=0`).
  But a truly locked bootloader **cannot** run an unofficial PE13 build — PixelExperience is known to
  **spoof these props for Play Integrity**. So the real bootloader is almost certainly **unlocked**
  (matches our prior note), and these values are cosmetic. **Confirm definitively** with
  `fastboot getvar unlocked` / `fastboot oem device-info` before any flash. (Task #1.)
- **GPS/GNSS: PRESENT** ✅ (resolves the old open question) — `gnss_service` running,
  `android.hardware.gnss@2.1-service-qti` + `vendor.qti.gnss@4.0-impl`, feature `location.gps`.
- **Sensors (30 h/w):** accel+gyro = **Bosch BMI120**, light/ALS = **Capella CM3232**, plus QTI/SSC
  fusion (gravity, rot-vector, step, sig-motion, tilt). Feature list also advertises
  compass/barometer/proximity — confirm physical parts during Phase 4.
- **Audio:** `sdm660-snd-card`, headset + button jack, Dirac. **Folio/hall** lid switch present
  (`uinput-folio` + `folio_daemon`).
- **❗ Spurious telephony flags:** PE advertises `android.hardware.telephony.*` features, but the
  hardware has **no radio** (`baseband=Wi-Fi Only`, `ro.radio.noril=yes`, SDA660). Ignore those flags —
  telephony stays **out of scope**.

## Hardware (known)
| | |
|---|---|
| Codename | `clover` (covers Mi Pad 4 **and** Mi Pad 4 Plus) |
| SoC | Qualcomm **Snapdragon 660 (SDM660)**, octa-core Kryo 260 |
| GPU | Adreno 512 |
| RAM / Storage | 3/4 GB · 32/64/128 GB (eMMC) |
| Display | 8.0″ **1920×1200** IPS (16:10), ~283 ppi |
| Variants | Mi Pad 4 (WiFi / LTE), Mi Pad 4 Plus (LTE) — **this unit: Mi Pad 4 WiFi-only** |
| Battery | 6000 mAh (Pad 4) · 8620 mAh (Plus) |
| Bootloader | Unlocked ✅ · **TWRP installed** ✅ |

## Current on-device state (matters for flashing)
- **ROM:** PixelExperience **13** (Android 13), official build.
- **Kernel:** **4.19** (PE uses an upgraded kernel, not the 4.4 stock).
- **Partitions:** **retrofit dynamic partitions** (`super`) + `fastbootd`. Retrofit = the **physical GPT
  is unchanged** (`super` is a logical layer over the existing `system`/`vendor`), so the real
  `system` (3 GB) and `vendor` (800 MB) partitions still exist at their original sizes.
- **Implication:** our Halium-9 base is **legacy / non-dynamic / system-as-root**. We flash to the
  physical `system`/`vendor`, replacing the boot ramdisk with `halium-boot` (which won't look for
  `super`). See Phase 3 plan below.

## Halium-9 target config (from `halium_device_xiaomi_clover` @ `halium-9.0`)
| Property | Value |
|---|---|
| A/B | **No** (single slot) |
| system-as-root | **Yes** (`BOARD_BUILD_SYSTEM_ROOT_IMAGE := true`) |
| Dynamic partitions | **No** (legacy layout) |
| Kernel source / defconfig | `kernel/xiaomi/clover` / **`clover_halium_defconfig`** |
| Kernel image | `Image.gz-dtb`, pagesize 4096, base `0x0` |
| Kernel cmdline | `console=ttyMSM0,115200,n8 earlycon=msm_serial_dm,0xc170000` (+ permissive) |
| Recovery fstab | `rootdir/etc/fstab.qcom` |

### Partition sizes (build limits, ≈ GPT)
| Partition | Size |
|---|---|
| boot | 64 MB |
| recovery | 64 MB |
| system | 3 GB (3,221,225,472 B) |
| vendor | 800 MB (838,860,800 B) |
| cache | 256 MB |
| persist | 32 MB |
| userdata | ~45 GB |

### fstab — by-name device → mount (flash targets)
| Device (`/dev/block/bootdevice/by-name/…`) | Mount | FS |
|---|---|---|
| `boot` | (boot) | emmc — **flash `halium-boot.img` here** |
| `system` | `/system` | ext4 ro — **flash Halium `system.img` here** |
| `vendor` | `/vendor` | ext4 ro — **flash Halium vendor here** |
| `userdata` | `/data` | ext4 — rootfs lives here (Halium puts Ubuntu in `/data/...`) |
| `cache` | `/cache` | ext4 |
| `persist` | `/mnt/vendor/persist` (+bind `/persist`) | ext4 |
| `modem` | `/vendor/firmware_mnt` | vfat (modem FW) |
| `bluetooth` | `/vendor/bt_firmware` | vfat |
| `dsp` | `/vendor/dsp` | ext4 (adsp FW) |
| `cust` | `/cust` | ext4 |
| `misc` | `/misc` | emmc |
| (sdcard) | `/storage/sdcard1` | vfat |

## Phase 3 plan for the PE13 → Halium-9 transition
1. **TWRP backup** of current boot/system/vendor/data = restore point.
2. **Vendor/firmware consistency:** Halium-9 expects Android-9-era vendor. Two options to test:
   - (a) Rely on the **Halium build's own `vendor`** (we flash it) and keep low-level firmware as-is.
   - (b) Flash a **LineageOS 16 (Android 9) firmware/base** first as a clean donor, then Halium.
   - → Decide empirically at first boot; (a) first, fall back to (b) if modem/adsp/audio misbehave.
3. Flash `halium-boot.img`→`boot`, Halium `system.img`→`system`, vendor→`vendor`; push Noble rootfs to `/data`.

## Scope: WiFi-only ⇒ no telephony
This unit is **WiFi-only**, so **modem / RIL / ofono / SMS / mobile-data / VoLTE are all OUT of scope.**
We don't run the telephony stack at all — one of the biggest Halium pain points is simply gone.
(GPS/GNSS **is present** on this WiFi unit — confirmed live 2026-06-04, `gnss@2.1` HAL running.)

## Still to verify live (cheap, do at flash time)
- [x] Variant: **Mi Pad 4 WiFi-only**, non-Plus, **4 GB / 64 GB** (confirmed 2026-06-04; WiFi-only ⇒ not Plus).
- [x] Screen density **320** @ **1200×1920** (confirmed 2026-06-04).
- [x] GPS/GNSS **present** (confirmed 2026-06-04).
- [ ] **Physical `system` (p13) / `vendor` (p14) sizes** — *deferred (unreadable without root/fastboot).*
  On running PE13, both `/proc/partitions` and `/sys/block/*/size` are SELinux-denied to shell uid 2000;
  device isn't rooted; recovery adb came up unauthorized (2026-06-04). Get sizes from `fastboot getvar all`
  (needs the Windows fastboot driver — **Task #7**) or a root recovery, at flash time. Retrofit keeps the
  factory GPT, so these ≈ the build limits above (system 3 GB, vendor ~0.8 GB) — **not a build blocker.**
- [ ] **Bootloader unlock** — *deferred.* Confirm with `fastboot getvar unlocked` once the fastboot driver
  is bound (**Task #7 → Task #1**). Live props say "locked" but that's almost certainly PE Play-Integrity
  spoofing (can't run unofficial PE13 on a genuinely locked bootloader).
- [ ] **TWRP on `recovery` (p51)?** — *likely replaced.* `adb reboot recovery` (2026-06-04) gave an
  **unauthorized** adb with no RSA prompt → probably PE's own recovery, not TWRP. Plan to (re)flash TWRP
  or use fastboot at Phase 3. See [fastboot-driver-windows.md](fastboot-driver-windows.md).

## Manual references
- postmarketOS clover wiki (anti-bot blocked for me; open in a browser): https://wiki.postmarketos.org/wiki/Xiaomi_Mi_Pad_4_(xiaomi-clover)
- XDA "list of partitions": https://xdaforums.com/t/mi-pad-4-list-of-partitions-in.3884204/
- TWRP device page: https://twrp.me/xiaomi/xiaomimipad4.html
- PE13 (dynamic partition, 4.19) thread: https://xdaforums.com/t/rom-13-official-4-19-dynamicpartition-pixelexperience-plus-for-mi-pad-4-4-plus-9-26-updated-check-2-for-faq-and-changelog.4551151/
