# Clover's GPU is capped at 370 MHz by a compatible-string check

Date: 2026-11-02. Found while chasing "the UI is not smooth". **Not fixed on
the installed system** (owner's decision: "not now"); proven by a RAM test.

## Finding

- Clover's GPU speed-bin fuse (kernel nvmem cell `gpu-speed-bin@41a0,15`,
  i.e. 0x41a0 bits 21-28, read through `/sys/bus/nvmem/devices/qfprom0/cells/`)
  is **135 (0x87)**.
- Android's tree maps 0x87 to a 647 MHz maximum (`qcom,gpu-pwrlevels-3`).
  The mainline a512 catalog maps it to bin 4, "up to 647 MHz"
  (`a5xx_catalog.c`: `{135, 4}`). `sdm660.dtsi` enables 465 and 588 MHz for
  that bin; 647 and higher are commented out upstream for every SDM660
  ("lacking support for the GPU regulator").
- The installed kernel (r100) offers only **19.2/160/266/370 MHz**.

## Cause

`a5xx_gpu_init()` uses the speed-bin catalog (`a5xx_set_supported_hw`) only
when the machine is `qcom,sdm630`, `qcom,sdm636` or `qcom,sdm660`. Clover's
root compatible is `"xiaomi,clover-wifi", "qcom,sda660"`, so it falls through
to the legacy `check_speed_bin()`, which computes `1 << 135`. That is an
out-of-range shift; arm64 masks it to `1 << 7` = `0x80`, the "unknown chip"
value, which only matches the `0xff` entries. The catalog path's log line
`GPU speedbin fuse ... mapped to opp-supp-hw` is absent from clover's dmesg.

This is the same `sda660` naming gap that already needed `qcom,sda660` in the
cpufreq-dt-platdev blocklist (docs/nura-cprh-port.md).

**Fix:** add `of_machine_is_compatible("qcom,sda660")` to that check. With bin 4
(`supported-hw` 0x10) the table becomes 19.2/160/266/370/465/588 MHz.

## RAM test T20 (2026-11-02)

`backups/gpu-opp-2026-11-02/TEST-gpu588-r100.img`, md5
`bd35f25a31afb4bd5aaed9be9b30795d` (not in git). It is the installed r100
`boot.img` with the **same kernel binary**, the DTB changed in exactly two
properties (465 MHz `0x78 -> 0xf8`, 588 MHz `0x70 -> 0xf0`, so the fallback
value 0x80 selects the same OPPs bin 4 would), and `nura_bisect=20` added.
Repacking the original from its own parts reproduced it byte for byte.

Result: booted in about 25 s; `available_frequencies` included 465 and 588 MHz;
the GPU ran at 588 MHz (`gpu-performance.service` pins it) for over 15 minutes
of normal use at 44-58 °C, with no hangcheck, GPU fault, IOMMU fault, display
timeout or underrun.

Linux still has no GPU core-voltage control on SDM660 (`supply vdd not found,
using dummy regulator`), so 588 MHz relies on the voltage the bootloader
leaves; it held here, as it does on other SDM660 devices running this kernel.

## What it did not fix

The owner noticed no smoothness change. The sluggishness is mostly in GNOME
Software, which is CPU-bound, not GPU-bound. It runs as a background service
(`gnome-software --gapplication-service`, D-Bus activated) and fetches and
decodes app icons, each in a sandboxed `glycin` loader (`bwrap`), at a steady
20-40 % of a core: 2,342 icons (46 MB) cached so far. Most of that catalog is
Flathub, which is enabled with no Flatpak apps installed. The owner chose to
leave Software as it is.

The rest of the system measured healthy: no PSI pressure, 2.1 GB of RAM
available with no swap in use, 30-38 °C, and phoc rendering on hardware
(`GL renderer: FD512`, Mesa 26.2.6). The GTK 4 apps load `libgallium`
(freedreno), and no software Vulkan (lavapipe) is installed.

## Measurement tooling note

On this rootfs, bash's builtin `echo` fails with `EINVAL` when writing tracefs
files (`/sys/kernel/tracing/...`), while BusyBox `sh` writes them fine. Run
trace setup under `sh`.
