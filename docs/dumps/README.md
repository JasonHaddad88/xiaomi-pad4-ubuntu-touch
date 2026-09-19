# Raw device dumps

Verbatim captures from the live tablet — committed for reference during bring-up. Synthesised facts
live in [`../device-clover.md`](../device-clover.md); this folder is the unedited source.

## 2026-06-04 — Mi Pad 4 `clover` (serial `XXXXXXXX`), booted in PixelExperience 13

| File | Command | Notes |
|---|---|---|
| `getprop-2026-06-04.txt` | `adb shell getprop` | Full property list (identity, build, AVB/boot, HAL svc state) |
| `partitions-by-name-2026-06-04.txt` | `adb shell ls -la /dev/block/bootdevice/by-name/` | Real GPT by-name → `mmcblk0pN` map |
| `mapper-2026-06-04.txt` | `adb shell ls -la /dev/block/mapper/` | Logical (super) partitions — retrofit dynamic |
| `df-2026-06-04.txt` | `adb shell df -h` | Mounts & current logical sizes (system 1.9 G, vendor 249 M, data 51 G) |
| `cpuinfo-2026-06-04.txt` | `adb shell cat /proc/cpuinfo` | 8× Kryo 260; Hardware = **SDA660** (modem-less) |

**Not capturable without root on the PE13 user build** (deferred to `fastboot` / later): `/proc/cmdline`,
`/proc/partitions` (physical partition sizes), battery `charge_full_design`.

Sensors / input / feature lists were captured to the porting session log rather than files: touch
`fts_ts` (10-pt, 1200×1920), accel+gyro Bosch **BMI120**, ALS Capella **CM3232**, audio `sdm660-snd-card`,
GNSS `gnss@2.1` present.
