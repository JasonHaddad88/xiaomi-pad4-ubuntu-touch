# Why Nura feels slow on clover: there is no CPU frequency scaling

**Mainline SDM660 does not implement CPU frequency scaling.** The CPUs run at whatever clock
the bootloader programmed and cannot boost under load. This is the dominant cause of the
"anemic" feel, and it is an upstream gap, not a misconfiguration — there is no governor to
change and no frequency to raise.

## Evidence

```
$ ls /sys/devices/system/cpu/cpu0/cpufreq
   (does not exist, for any of the 8 cores)

$ cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver
   none

$ dmesg | grep -iE "cpufreq|opp|cpr"
   (nothing — no cpufreq driver ever binds)

$ grep -iE "cpu|apcs|pwrcl|perfcl" /sys/kernel/debug/clk/clk_summary
   (nothing — no CPU clocks registered with the clock framework)
```

`CONFIG_CPUFREQ_DT=y` and `CONFIG_CPUFREQ_DT_PLATDEV=y` are both set, so the driver is
compiled in. It never binds because the device tree gives it nothing to work with:

```
cpu@0 {
    device_type = "cpu";
    compatible = "qcom,kryo260";
    enable-method = "psci";
    cpu-idle-states = <...>;        /* idle states ARE described */
    capacity-dmips-mhz = <0x280>;
    /* no operating-points-v2 */
    /* no clocks */
};
```

No OPP tables, no clock references, and no CPR/AVS node anywhere in the tree. Idle states
work — so power saving functions — but there is no performance scaling in either direction.

CPU parts read `0x800` (Kryo 260 Gold, A73) and `0x801` (Silver, A53), so the silicon is
correctly identified. Only the frequency control is missing.

## What this means

- **Moving the rootfs from SD to eMMC does not fix it.** That change was real and worth doing
  (37.9 MB/s to 221.9 MB/s, 14 GB to 49 GB) but storage was never the main bottleneck. The
  lesson: measure the CPU before accepting a storage explanation, even when the reporter
  mentions storage.
- **Fixing it properly is upstream kernel work:** CPU clock controller support for SDM660,
  OPP tables for both clusters, and the CPR/AVS driver for the matching voltage scaling.
  Comparable in scale to the camera work.

## What helps today

The stock Phosh install runs a lot that is pointless on a Wi-Fi-only tablet with no modem and
no cpufreq. All of the following are masked/disabled on this device, and all are reversible:

| masked service | why |
|---|---|
| `cups.service` / `.socket` / `.path` | no printing |
| `avahi-daemon.service` / `.socket` | no mDNS needed |
| `fwupd.service` | no firmware updates for this hardware |
| `flatpak-system-helper.service` | was consuming 12% CPU in the background |
| `tuned.service`, `tuned-ppd.service` | manage CPU power profiles that do not exist here |

| disabled autostart | why |
|---|---|
| `org.gnome.Calls-daemon.desktop` | telephony — no modem |
| `sm.puri.Chatty-daemon.desktop` | SMS — no modem |
| `org.kop316.vvmplayer-daemon.desktop`, `vvmd.desktop` | visual voicemail — no modem |

Those four daemons were holding roughly 300 MB between them.

Undo with `systemctl unmask <service>`, or by removing the `Hidden=true` line appended to the
`.desktop` file.

**Firefox is the other big consumer** — three processes at ~36% CPU combined. On a tablet
with no frequency scaling, a lighter browser (GNOME Web) is noticeably better.

## Two real bugs that were mistaken for slowness

Both were found by reading the journal rather than by tuning, and both are config fixes that
persist. Neither has anything to do with the missing cpufreq.

### Settings "always crashed": a 25-second ModemManager timeout

```
gnome-control-center: Error connecting to ModemManager:
  StartServiceByName for org.freedesktop.ModemManager1: Timeout was reached
dbus-:1.4-org.gnome.Settings@0.service: Consumed 6.053s CPU over 34.364s wall clock
phosh: Failed to launch app 'Settings'
```

`gnome-control-center` blocks on D-Bus activation of ModemManager. This is the Wi-Fi-only
SDA660 — there is no modem — so activation times out after 25 s and Phosh gives up on the
app. It looks like a crash and is a timeout.

**Fix:** `systemctl mask ModemManager.service`. With the unit masked, D-Bus activation fails
immediately instead of hanging, and Settings opens. Confirmed faster by the owner.

### "Every app takes ages to load": gnome-software enumerating the whole repository

```
apk-polkit-server: Getting package details for [... several hundred packages ...]
  repeated at 10:27:00, 10:27:07, 10:27:37, 10:27:43
```

`gnome-software` was repeatedly asking `apk-polkit-server` for details of **thousands** of
packages — the entire Alpine repo, in batches, over and over. On a CPU that cannot boost,
that starves everything else.

**Fix:**

```sh
gsettings set org.gnome.software download-updates false
gsettings set org.gnome.software download-updates-notify false
```

The app stays usable; only the background metadata refresh stops. `apk-polkit-server`
activity went to zero afterwards. gnome-software is D-Bus activated (`org.gnome.Software.service`,
plus a `static` systemd user unit), so it is not in `/etc/xdg/autostart` and disabling an
autostart entry would not have helped.

## Measured result of the two fixes

Verified on a clean boot with **only** the permanent config fixes active — no kernel-level
tuning:

```
load average: 0.96, 1.22, 0.63        (was 3.2 - 6.3 before the fixes)
apk-polkit "Getting package details": 0 occurrences this boot
ModemManager: masked      gnome-software download-updates: false
cups / avahi / tuned: masked      telephony autostarts: disabled
```

**Load average fell from 3–6 to about 1 at idle.** On a CPU that cannot boost, work that
competes with the foreground is felt directly, so removing it is worth more here than on
hardware that can simply clock up. Settings opens instead of dying, confirmed by the owner.

This is the honest baseline for the port: bugs fixed, background bloat removed, nothing
risky applied. Whatever sluggishness remains from here is the fixed CPU clock.

## Tuning that was tried and withdrawn

Three live tunings were applied and **not** made permanent, because the tablet hard-froze
while they were active — unreachable over SSH, requiring a power cycle:

| tuning | status |
|---|---|
| GPU devfreq pinned to 370 MHz (from 19.2 MHz idle, `simple_ondemand`) | withdrawn, but **no heat** was observed |
| 12 deep CPU idle states disabled (2336 us exit latency) | withdrawn — **prime suspect** |
| swappiness 180 -> 100 | withdrawn, harmless but unproven |

The idle-state change is the prime suspect: it alters low-level power management, and the
kernel logged `driver: Idle state 1 target residency too low` right afterwards, which was
noticed and not investigated. The freeze is not proven to be caused by it — this port has an
unexplained freeze history — but three simultaneous changes meant nothing could be attributed.

**If retesting, change one thing at a time.** The GPU governor is the most promising and
showed no thermal cost.

## What is NOT the problem

- **The GPU is fine.** `freedreno` / `FD512`, OpenGL ES 3.1 on Mesa 26.2.5 — real hardware
  acceleration. The `a530_pm4.fw` load failure at 3.8 s in dmesg is a first attempt during
  early boot that succeeds later once the rootfs is mounted; it looks alarming and is not.
- **Thermals are fine.** Zones read 29–50 °C at idle, nowhere near throttling.
- **Memory is adequate.** 3.6 GB total with zram swap configured; ~1.8 GB free with a browser
  open.
