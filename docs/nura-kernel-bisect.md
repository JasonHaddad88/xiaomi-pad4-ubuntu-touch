# Why locally built kernels black-screen: test plan

Status 2026-10-30: **resolved. Cause: BTF module validation (confirmed by T4).**

## The problem

Kernels built locally from `cache_git/pmaports` (r0) and booted with
`fastboot boot` never come up: fastboot prints `Booting OKAY`, the screen
stays black, and the tablet never reaches the network. This happened five
times on 2026-10-25, with three versions of the OSM diagnostic **and with a
control kernel carrying no patch at all**.

## What has been ruled out

| suspect | evidence against |
|---|---|
| the OSM register reads | the control kernel had none and failed identically |
| the boot image id hash | a control with a correct hash failed identically; Ubuntu Touch's own header-v0 `boot.img` has a non-matching id and booted from flash for weeks |
| `fastboot boot` itself / Xiaomi restrictions | Nura ran via `fastboot boot` for weeks from SD, and the speaker DTB was tested that way (docs/nura-port.md, speakers/README.md) |
| the repack tool | repacking the installed image from its own parts reproduces it byte for byte (md5 `62cbaf2f3e2d24b0d5322376c7e69931`) |
| the kernel config | embedded configs (IKCONFIG) of installed r2 and local r0 differ only by commit `400b925` (netfilter netdev, CDROM, a Himax panel), and the compiler point release, clang 23.1.3 vs 23.1.4 |
| the DTB | the local DTB differs from the installed one only by the speaker nodes and capacity values, and the stock DTB is what Nura was installed with |

## Cause (confirmed by T4 on 2026-10-30)

The config has `CONFIG_DEBUG_INFO_BTF_MODULES=y` and does **not** set
`CONFIG_MODULE_ALLOW_BTF_MISMATCH`. Every module on the rootfs was built
against the installed r2 kernel. A locally built kernel, with a different
compiler point release and config, has different BTF type information, so it
**refuses every module** (`failed to validate module [%s] BTF` is in the
binary). The display (`CONFIG_DRM_MSM=m`) and Wi-Fi (`ath10k`) are modules,
so the result is a running kernel with a black screen and no network, which
is exactly what was seen.

The earlier check that "installed modules will load" looked only at
`vermagic` and signature enforcement. It missed BTF.

## Test images

In `backups/kernel-bisect-2026-10-29/` (not in git). Every image keeps the
installed ramdisk and cmdline and **adds `nura_bisect=N` to the cmdline**, so
`/proc/cmdline` proves which image actually ran. A local kernel reports
`#1-postmarketos...` in `uname -v`, the installed one `#3-...`.

| image | kernel | DTB | md5 | answers |
|---|---|---|---|---|
| T1 | installed r2 | installed | `1eaf43986bb4adcd0ccb8750e2287c7b` | does any repacked image boot? |
| T2 | installed r2 | local stock | `b50dc7e47b60c076c878d41db9291258` | is the local DTB at fault? |
| T3 | local r0 | installed | `c3feadbd67dddde79d7b6cc808c170f7` | is the local kernel at fault? |
| T4 | local r0 + `ALLOW_BTF_MISMATCH=y` | installed | `42fb18965edca844de40e062931e24cc` | **is it BTF?** |
| T5 | local r0 + `ALLOW_BTF_MISMATCH=y` + read-only OSM dump v4 | installed | `f4abd6c937891f2730071d789cbc81c4` | the original question |

The `ALLOW_BTF_MISMATCH` setting was verified inside the T4 and T5 binaries
(extracted IKCONFIG), not just in the build tree. T4 contains no diagnostic
code. T5 has the v4 dump and no `panic()`.

## Order

1. **T4.** If it comes up with `nura_bisect=4` and `#1`, the BTF explanation is
   confirmed, and T1-T3 are unnecessary. Then run `dmesg | grep -i btf`: it
   should show mismatch warnings instead of refusals.
2. **T5** (only after T4 boots). Read the dump with `dmesg | grep osm-dump`.
   This answers whether the bootloader left the OSM table programmed.
3. Only if T4 fails: **T1**, then **T3** and **T2**.

At best that is two boots instead of five.

## Procedure and escape route

Each test: Power + Volume Down into fastboot, then
`fastboot boot backups/kernel-bisect-2026-10-29/<image>`. Nothing is written
to the boot partition. Then check:

```sh
cat /proc/cmdline | grep -o 'nura_bisect=[0-9]'   # which image ran
uname -v                                            # #1 local, #3 installed
dmesg | grep -iE 'btf|osm-dump'
```

To return to the installed kernel, run `sudo reboot` if it booted, or hold
Power ~10 s if it didn't. That hold drops DRAM power and wipes ramoops, so
prefer `reboot` whenever SSH works.

The rootfs is mounted read-write as in any normal boot. That is the same as
every earlier `fastboot boot` in this project.

## Before any permanent kernel change

- The installed boot partition is backed up and verified:
  `backups/nura-internal-2026-10-25/boot-INSTALLED-speakers+capfix.img`.
- The rootfs backup (`xiaomi-clover-root.img`) is from install day. Changes
  made since then are recorded in `device-fixes/nura/`. Take a fresh rootfs
  image first.
- A permanent kernel must ship **with its own modules** (install the package
  on the device, not just the boot image), and must carry the patched DTB, or
  the speakers and capacity fix are lost.

## Results (2026-10-30)

**T4 booted in ~28 s**, with `uname -v` = `#1-postmarketos-qcom-sdm660 ... Thu
Oct 29 20:30:29` and `nura_bisect=4` in `/proc/cmdline`, which proves the RAM
image ran. The kernel log shows the cause directly:

```
[1.207235] Kernel module BTF mismatch detected, BTF debug info may be unavailable for some modules
[10.213284] missing module BTF, cannot register kfunc
```

That first line is what this kernel prints **instead of refusing** a module,
and only with `CONFIG_MODULE_ALLOW_BTF_MISMATCH=y`. With it on, 119 modules
loaded, including `msm` (display) and `ath10k_snoc`/`ath10k_core` (Wi-Fi). The
speakers and the capacity fix were active. Without the option, the same
mismatch makes module load fail, which explains all five black screens.

One residual variable: the failing control used the local stock DTB, while T4
used the installed one. The log proves the mismatch exists regardless, and
the stock DTB is what Nura was installed with, so the DTB is not a credible
cause. T1-T3 were not needed.

**T5 booted in ~40 s** (`nura_bisect=5`). The read-only OSM dump ran, and
every register read survived:

```
pwrcl-A53:  VERSION = 0x00070000  ENABLE = 0x00000000 -> OSM DISABLED  PERF_STATE = 0
perfcl-A73: VERSION = 0x00000000  ENABLE = 0x00000000 -> OSM DISABLED  PERF_STATE = 0
======== all reads survived ========
```

The tablet was then rebooted normally (`systemctl reboot` works on Nura) and
came back on the installed `#3` kernel with no test marker. Full logs:
`backups/kernel-bisect-2026-10-29/T4-boot-evidence.txt` and
`T5-boot-evidence.txt` (not in git; they contain the device serial).

**Rule for any future RAM test:** build the test kernel with
`CONFIG_MODULE_ALLOW_BTF_MISMATCH=y`, or the rootfs modules will be refused.

## T6: read-only CPRh voltage-controller dump (run 2026-10-30, see result below)

`T6-LOCAL-kernel-BTFALLOW+OSM-CPRh-DUMPv5+installed-dtb.img`, md5
`c898dc52c96be883aea761bb6a0f8ca6`. It is T5's proven kernel (BTF mismatch
allowed, installed DTB, `nura_bisect=6`) with the dump extended to the two
CPRh controllers that drive the CPU rails. Purpose: decide whether any
frequency increase could be voltage-safe without porting CPRh programming
(see docs/nura-pr239-review.md).

Still strictly read-only: the source has zero `writel` calls, and every
access is announced before it happens. For each controller
(`0x179c8000` A53, `0x179c4000` A73, register map from clover's downstream
`cpr3-regulator.c`) it reports:

- `CPR_CTL` bit 0: is the CPR loop running at all
- `HW_CLOSED_LOOP`: 0 means hardware closed loop is on
- `CPRH_CTL`: is the OSM interface enabled, plus the base voltage and step
  size programmed into the hardware
- `CPRH_STATUS`: current corner and last voltage
- all 40 `CPRH_REG_CORNER` entries, decoded with clover's DT units (base
  400 mV, step 4 mV) into start and floor voltages

How to read the result:

| finding | meaning |
|---|---|
| CPR loop off, corner table empty | nobody controls the rail beyond its boot voltage, so raising clocks without porting CPRh is unsafe |
| loop on, OSM interface enabled, table filled | the firmware runs CPRh, so OSM corner requests would be honoured; a TZ-correct OSM driver might suffice |
| something in between | read the values before deciding anything |

After boot, also run (root):

```sh
dmesg | grep osm-dump
cat /sys/kernel/debug/regulator/regulator_summary   # look for the APC / CPU rails
```

Then `sudo systemctl reboot` returns to the installed kernel.

### T6 result (2026-10-30): the CPR loop is off, and the CPRh block is not accessible

The kernel panicked during the dump; the screen showed it (photo kept as
`backups/kernel-bisect-2026-10-29/T6-panic-photo.jpg`). In order:

```
OSM pwrcl-A53:  VERSION=0x00000000 ENABLE=0x00000000 (disabled)
OSM perfcl-A73: VERSION=0x00000000 ENABLE=0x00000000 (disabled)
---- CPRh pwrcl-A53 @ 0x179c8000 ----
CPRh pwrcl-A53: VERSION=0x40020000            <-- first read survived
CPRh pwrcl-A53: CPR_CTL=0xfffffe3e -> CPR loop disabled
CPRh pwrcl-A53: CPR_STATUS=0x00000001 (busy=1)
ABOUT TO READ HW_CLOSED_LOOP (+0x3000)
Internal error: synchronous external abort ... pc : cprh_dump+0x128/0x334
Kernel panic - not syncing: Attempted to kill init!
```

- **The CPR closed loop is not running** on the A53 voltage controller at
  boot (`CPR_CTL` bit 0 = 0). The A73 controller was never reached.
- **The CPRh register block from `+0x3000` up aborts** when read from Linux.
  Clover's Android DT gives this controller a `core_clk` =
  `GCC_HMSS_RBCPR_CLK` (gcc id 72 downstream, 59 in mainline), and Android's
  `cpr3-regulator.c` enables bus, iface and core clocks before touching any
  CPRh register. The low registers answering while the high block aborts
  points to that clock being off, i.e. an unclocked region rather than a
  TrustZone lock. **Not proven.**
- The abort is a refused read on the bus, not a write; nothing was changed.
  It panicked only because the oops hit PID 1 during an initcall.
- `pstore: backend (ramoops) writing error (-28)`: ramoops could not store
  the panic record (`record-size` 0x1000 is too small), so even a warm reset
  would not have saved this dump. The photo was the only record.
- Unexplained: `OSM pwrcl VERSION` read `0x00000000` here but `0x00070000`
  in T5, from the same register. Don't build on either value.

**Consequence:** nothing is running a voltage control loop on the A53 rail
at boot, so the CPU rail voltage is whatever the boot chain left. Raising
clocks without porting and running CPRh (clocks, corner tables, closed
loop) is not voltage-safe. That confirms the large-port conclusion of
docs/nura-pr239-review.md.

**Hazard handled:** v5 panics clover every boot at that read. The repo's
`0001-osm-dump-diagnostic.patch` was reverted to the safe v4; v5 stays
outside git in `~/osm-diag/kept/`.
