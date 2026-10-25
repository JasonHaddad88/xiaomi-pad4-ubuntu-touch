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

## What is NOT the problem

- **The GPU is fine.** `freedreno` / `FD512`, OpenGL ES 3.1 on Mesa 26.2.5 — real hardware
  acceleration. The `a530_pm4.fw` load failure at 3.8 s in dmesg is a first attempt during
  early boot that succeeds later once the rootfs is mounted; it looks alarming and is not.
- **Thermals are fine.** Zones read 29–50 °C at idle, nowhere near throttling.
- **Memory is adequate.** 3.6 GB total with zram swap configured; ~1.8 GB free with a browser
  open.
