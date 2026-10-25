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

## The big cores are the slow cores

With no cpufreq, each cluster sits at whatever fixed clock the bootloader left it — and the
two clusters are left at very different clocks. Measured with `openssl speed -evp
aes-128-cbc` at 16 KB blocks, one core at a time on an idle system:

| Linux CPU | part | microarchitecture | kernel capacity | **measured** |
|---|---|---|---|---|
| cpu1, 2, 3, 4 | `0x800` | Kryo 260 **Gold** (A73) | 1024 | **476 MB/s** |
| cpu0, 5, 6, 7 | `0x801` | **Silver** (A53) | 640 | **1035 MB/s** |

**The cores the scheduler is told are fast deliver less than half the throughput.**
`capacity-dmips-mhz` is correct by microarchitecture — the A73 really is the bigger core —
but wrong about *delivered* performance here, because the A73 cluster is stuck low.

Note the interleaved enumeration: the DTB lists the Gold cluster (`cpu@100-103`) first, so
Linux numbers them cpu1–cpu4, with the Silver cores at cpu0 and cpu5–cpu7. Pinning a
benchmark to "cpu7" expecting a big core measures a little one — that mistake was made here
first and produced a backwards conclusion.

Proof it is placement and not capability — taking the Gold cluster offline:

```
all 8 cores online:        AES unpinned  476 MB/s
cpu1-4 offline (Silver only): AES unpinned 1038 MB/s     2.2x
```

### It is not a crypto artefact - confirmed with three workload types

The first measurement used `openssl speed -evp aes-128-cbc`, which exercises the ARMv8
**hardware AES unit** rather than general CPU performance. That is a poor proxy, and the
conclusion was briefly withdrawn on those grounds. Re-measured with workloads that have no
hardware acceleration:

| benchmark | type | cpu1 (Gold/A73) | cpu5 (Silver/A53) | ratio |
|---|---|---|---|---|
| RSA-2048 sign | pure integer bignum | 64.9/s | **127.4/s** | Silver **1.96x** |
| MD5 | not accelerated on ARM | 115,800k | **198,246k** | Silver **1.71x** |
| AES-128-CBC | hardware accelerated | 476,244k | **1,038,117k** | Silver **2.18x** |

The inversion is real across every workload type, so the original finding stands. An A73 at
equal clock should *beat* an A53 by 1.5-2x; this one delivers half, which puts the Gold
cluster at roughly a quarter to a third of the Silver cluster's clock - almost certainly
pinned at its **300 MHz minimum**, the lowest entry in the OSM table.

The lesson: when a surprising result rests on one benchmark, resolve the doubt by measuring
something different, not by reasoning about whether the benchmark was fair. Reasoning about
it led to withdrawing a correct conclusion and reaching for a mechanism that hung the device.

### The fix used

**Adopted: a device-tree capacity correction, flashed to the boot partition.**
`capacity-dmips-mhz` is set from measured performance - Silver 1024, Gold 471 - so the
scheduler prefers the cores that actually deliver, while **all eight stay available to
everything**. Overflow still lands on the Gold cluster when the fast cores are busy, so
nothing can starve.

Verified on the running system after flashing:

```
cpu0,5,6,7  part 0x801 (Silver)  cap 1024     online: 0-7
cpu1,2,3,4  part 0x800 (Gold)    cap  471

unpinned AES: 476,244k -> 1,025,545k    (2.15x)
unpinned MD5: 115,800k ->   197,465k    (1.70x)
```

Owner's verdict: "much better". Speakers and Wi-Fi unaffected.

### Rejected: confining the user session with cgroups

The first attempt used a `user.slice` drop-in with `AllowedCPUs=0,5-7`, since `cpu_capacity`
in sysfs is read-only and cannot be corrected at runtime. It produced the same throughput
gain **and hung the tablet**: with the whole session restricted to four cores, one heavy app
(`gnome-control-center` had already been seen consuming 907 MB and 4m21s of CPU) could starve
everything in the session, including new ssh logins. sshd accepted connections but could not
complete a banner exchange, and a power cycle was required.

That drop-in was removed. **Confining a session to a subset of cores removes the headroom a
runaway process needs**, which the device-tree approach preserves. If it is ever reinstated,
it should apply to a narrower slice than all user processes.

Full file with rationale:
[`device-fixes/nura/user-slice-90-fast-cores.conf`](../device-fixes/nura/user-slice-90-fast-cores.conf).
Applies live via `systemctl set-property user.slice AllowedCPUs=0,5-7`; no reboot, no
flashing, nothing written to the device tree.

**Trade-off:** user apps can no longer use the Gold cluster, so heavily parallel user
workloads lose four (slower) cores — aggregate throughput across all eight is about 46%
higher than the four fast ones alone. For UI responsiveness on a tablet, preferring the fast
cores is the right trade; for a build machine it would not be.

### Flashing it without fastboot

`reboot bootloader` does not work on Nura, so reaching fastboot needs the hardware key
combination. That is only required for *testing* via `fastboot boot`; to make it permanent
the boot partition can be written from the running system, because the running kernel is in
RAM:

```sh
B=$(readlink -f /dev/disk/by-partlabel/boot)      # /dev/mmcblk1p12, 64 MB
dd if=/dev/disk/by-partlabel/boot of=/tmp/boot-before.img bs=1M count=25   # keep a fallback
dd if=boot-cap.img of="$B" bs=1M conv=fsync
# verify, do not trust the write:
dd if="$B" bs=1 count=$(stat -c %s boot-cap.img) | md5sum
```

Installed image kept as `backups/nura-internal-2026-10-25/boot-INSTALLED-speakers+capfix.img`
(md5 `62cbaf2f3e2d24b0d5322376c7e69931`), read back and verified byte-for-byte after writing.

### The proper fix

Upstream cpufreq for SDM660 would let the Gold cluster reach its rated 2.46 GHz and make it
genuinely the fastest, after which both workarounds above should be deleted. The hardware
pieces are identified: OSM at `0x179c0000`, CPRh at `0x179c4000` and `0x179c8000`, with the
full frequency tables in the downstream device tree (`qcom,clk-cpu-osm`):

```
pwrcl (A53):  300, 633.6, 902.4, 1113.6, 1401.6, 1536, 1747.2, 1843.2 MHz
perfcl (A73): 300, 1113.6, 1401.6, 1747.2, 1958.4, 2150.4, 2457.6 MHz
```

The kernel already ships `qcom-cpufreq-hw`, which binds the generic `qcom,cpufreq-hw`
compatible and reads frequency tables from the OSM hardware LUT — so voltages would not have
to be supplied by hand. What is missing is the per-cluster register layout for this OSM
revision, which differs from the SDM845 generation the driver was written against. Guessing
it would mean the driver writing into the CPU voltage-control region, which is why it was not
attempted here.

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
