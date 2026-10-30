# Review of the HiBy RS6 CPRh + OSM series against clover's own data

Date: 2026-10-30. Offline review, nothing booted. Same method as
`docs/nura-pr239-review.md`: every value compared with clover's Android
device tree (`backups/clover-downstream-reference/`) and clover's vendor
kernel source (`ubuntu-touch-clover/halium_kernel_xiaomi_clover`, Linux
4.4.153: `cpr3-regulator.c`, `cprh-kbss-regulator.c`, `clk-cpu-osm.c`).

## What was reviewed

https://github.com/noas-slopware/linux-hiby-rs6 (branch `senpai`, pushed
2026-10-27), a 94-patch series on sdm660-mainline `qcom-sdm660-7.2.y` for the
HiBy RS6, an SDM660 audio player. The relevant patches:

| patches | what |
|---|---|
| 0001-0014 | Del Regno / Maggio: CPR3/CPRh voltage-control driver (`pmdomain/qcom/cpr3.c`) and "CPRh-aware OSM programming" in `qcom-cpufreq-hw`, plus bring-up fixes |
| 0019 | SDM630/660 CPRh data (Noa Himesaka) |
| 0020 | SDM630/660 OSM programming |
| 0021 | block SDM630/660 in cpufreq-dt-platdev |
| 0022 | DT bindings |
| 0023 | SDM660 L2 SAW AVS fix |
| 0041 | SoC device tree: cpufreq-hw node, CPRh node, CPRh corners, fuse cells |
| 0042 | RS6 board DT, which carries the CPU frequency tables |

Status according to its own README: "CPU frequency/voltage scaling (CPRh +
OSM port for SDM630/SDM660) ... Whether each part was verified on the unit is
not recorded." The SDM660 patches are marked `Assisted-by:
Claude:claude-opus-5-5`. The README credits "the Nura project" among others.

## The two problems that ruled out PR #239 are handled here

**TrustZone ownership.** Clover's Android tree omits `qcom,osm-no-tz`, so
the OSM sequencer's secure registers are written only through TrustZone.
This series does the same: the SDM660 data sets `uses_tz = false` ("Linux
programs the OSM"), and the secure sequencer registers (MEM-ACC thresholds,
APM crossover/threshold) go through `qcom_scm_io_writel`. It also enables all
six OSM state machines, which matches clover's Android tree (all six
`qcom,*-fsm-en` flags are present).

**Voltage control.** It ships a real CPRh driver, and its device tree gives
the controller a `"ref"` clock = `GCC_HMSS_RBCPR_CLK`, enabled by the driver.
That is exactly the clock our T6 dump found off, whose absence made the CPRh
block abort (`docs/nura-kernel-bisect.md`, T6).

## Data comparison: everything matches

| item | clover source | result |
|---|---|---|
| fuse reference voltages, both clusters | vendor `sdm660_kbss_fuse_ref_volt` | identical (A53 644/724/788/868/1068, A73 724/788/868/988/1068 mV) |
| ceilings / floors per fuse corner | DT `qcom,cpr-voltage-ceiling/-floor` | identical |
| floor-to-ceiling ranges | DT `qcom,cpr-floor-to-ceiling-max-range` | identical |
| open-loop fuse adjustments | DT (one row for every fuse combo) | identical: A53 -4/4/7/19/-8, A73 16/27/39/39/20 mV |
| closed-loop fuse adjustments | DT (one row for every fuse combo) | identical: A53 -32/-30/-29/-23/-21, A73 -22/-9/-7/-2/11 mV |
| sensor (RO) scaling factors | DT `qcom,cpr-ro-scaling-factor` | identical, both clusters |
| per-chip fuse positions | vendor `sdm660_kbss_{init_voltage,target_quot,ro_sel,quot_offset}_param` | **37 of 37** fields at identical fuse bits; fusing revision `{71,28,30}` = cell `0x423b` bits 4-6, identical |
| speed-bin fuse | vendor OSM: efuse `0x784130`, shift 29, mask 7 | identical: cell `0x4133` bits 5-7 |
| corner to fuse-corner map | DT `qcom,cpr-corner-fmax-map` | identical in every speed bin: A53 `<2 3 4 5 8>`, A73 `<2 3 4 6 7>` |
| CPU frequencies per corner | DT `qcom,corner-frequencies` | RS6 uses clover's **speed bin 1** table exactly |

This data is SoC-level, so it is the same on clover. That is also why
clover's Android tree has a single row for every fuse combination.

## The one clover-specific piece: the speed bin

The CPU frequency tables live in the RS6 **board** DT, and the RS6 author
inferred speed bin 1 from the stock top frequency rather than reading the
fuse. Clover's Android tree carries four bins:

| bin | A53 (MHz) | A73 (MHz) |
|---|---|---|
| 0 | 300 633.6 902.4 1113.6 1401.6 1536 1747.2 1843.2 | 300 1113.6 1401.6 1747.2 1958.4 2150.4 **2457.6** |
| 1 | same as bin 0 | 300 1113.6 1401.6 1747.2 1958.4 2150.4 2208 |
| 3 | ... **1612.8** ... 1843.2 | 300 1113.6 1401.6 1747.2 **1804.8** 2150.4 2208 |
| 4 | same as bin 0 | same as bin 1 |

So clover needs its own CPU OPP tables in its board DT, chosen by **reading
its fuse**. That is a read-only check on the running installed system:

```sh
# qfprom@780000 nvmem, byte 0x4133, bits 5-7
dd if=/sys/bus/nvmem/devices/<qfprom>/nvmem bs=1 skip=$((0x4133)) count=1 | od -An -tu1
```

It was not run yet (the tablet was offline at review time).

## Evidence it works on real silicon

Not on SDM660 yet. On the sibling **MSM8998** (same OSM "v1" block), patch
0013 (Giuseppe Maggio, 2026-08-19) reports that after the SAW4 AVS fix the OSM
"deliver[s] on both domains (silver 6.55x for a 6.34x request, gold 8.00x
for 7.87x, same-boot controlled)", i.e. measured speed-ups matching the
requests. Patch 0023 is the SDM660 counterpart of that SAW AVS fix.

## Built-in safety: staged bring-up gates

The series keeps two kernel command-line gates from its own bring-up:

- `cprh_init_stop=N`: stop CPRh setup after phase N (0 = no hardware access)
- `osm_setup_stop=N`: stop OSM programming after step N (0 = program nothing)

Both default to "all", but they allow a staged, one-phase-per-boot test where
`0` is the known-good control. That is exactly how this should be tested.

## Verdict

Unlike PR #239, **this series is a credible candidate for clover.** Its
set-up model matches clover's firmware (TrustZone-owned sequencer, Linux-run
CPRh with the RBCPR clock), and every piece of SoC data, including all 37
per-chip fuse positions, matches clover's vendor sources exactly. The open
items:

1. Read clover's speed bin (read-only, on the installed system) and write
   clover's CPU OPP tables from its Android bin.
2. Kernel version: the series targets `qcom-sdm660-7.2.y`; the installed
   system is 7.0.14. A RAM test needs either a backport to 7.0.14, which
   keeps the rootfs modules usable with `ALLOW_BTF_MISMATCH`, or a 7.2
   kernel plus its own modules.
3. Test one phase per boot with the gates, starting from
   `cprh_init_stop=0 osm_setup_stop=0`, with the root filesystem mounted
   read-only (`pmos_rootfsopts=ro`) so a crash can't corrupt the installed
   system. Measure the result with the dependent-add clock method, not just
   cpufreq sysfs.
4. Nobody has verified it on an SDM660 yet. Clover would be the first.
