# Review of sdm660-mainline PR #239 against clover's own data

Date: 2026-10-30. This is step 1 of the plan in `docs/nura-cpufreq-plan.md`:
check the PR's voltage tables against clover's Android tables before running
anything on the tablet. Nothing was booted for this review.

- PR: https://github.com/sdm660-mainline/linux/pull/239,
  "clk: qcom: add SDM660-Family CPU OSM driver" (glavakartela, opened
  2026-10-09 against `qcom-sdm660-7.2.y`, open and unreviewed).
- Reviewed at its head commit `5f750308d509ed8113a68dac68ebd5b1a9869b61`:
  `drivers/clk/qcom/clk-cpu-osm-sdm660.c` and the OSM node in `sdm660.dtsi`.
- Clover's data comes from the Android device tree dump in
  `backups/clover-downstream-reference/` and the Android driver in
  `device-fixes/nura/cpufreq/clk-cpu-osm-660.c`.

## What checks out

**The voltages match clover exactly.** The PR's `qcom,{pwrcl,perfcl}-corner-uv`
values are the CPR ceilings of the first stock corner at or above each row's
frequency. Mapped row by row against clover's own CPRh nodes, every value
matches:

| cluster | clover corners (MHz) | clover CPR ceiling (mV) | clover CPR floor (mV) | PR |
|---|---|---|---|---|
| A53 `cprh-ctrl@179c8000` | 300 633 902 1113 1401 1536 1747 1843 | 724 724 724 788 868 1068 1068 1068 | 588 588 596 652 712 744 784 844 | all 21 rows match the ceilings |
| A73 `cprh-ctrl@179c4000` | 300 1113 1401 1747 1958 2150 2457 | 724 724 788 868 988 988 1068 | 588 596 652 712 744 784 844 | all 28 rows match the ceilings |

So the voltage *numbers* are at the top of clover's allowed range and never
below it. They are not an undervolt risk in themselves.

**The frequencies are conservative.** The A73 table tops out at 2342.4 MHz
(clover allows 2457.6), and the A53 table at 1824 MHz (clover allows 1843.2).

**The register map matches ours.** The PR uses the same OSM base and window
stride. An SDM660 tester's devmem reads of `0x179C1004` / `0x179C3004`
returned 1 with the driver loaded; our read-only dump found the same ENABLE
registers at 0 without it.

**The frequency encoding matches clover's table.** Clover's rows use the
same `freq_data` words, e.g. `0x0404003a` = lval 58 = 1113.6 MHz.

## Two structural problems for clover

### 1. It uses the wrong ownership model

The OSM has two set-up modes, selected in the stock device tree by
`qcom,osm-no-tz`:

- **no-TZ** (`secure_init = true`): Linux writes every sequencer register
  directly and loads the OSM microcode itself.
- **TZ-owned** (`secure_init = false`): TrustZone owns the sequencer. Linux
  still writes the frequency table and ENABLE, but the secure sequencer
  registers can only be written through TrustZone (`scm_io_write`): APM
  crossover `SEQ_REG(72, 15, 31, 76)` and memory-voltage thresholds
  `SEQ_REG(55-58, 88, 32)`. No microcode load.

**Clover's Android tree does not set `qcom,osm-no-tz`, so clover is
TZ-owned.** The PR implements the no-TZ path: direct MMIO for all of those
registers plus its own microcode load. Its TrustZone variant
(`clk_osm_apm_vc_setup_scm`) is marked "NOT currently called".

The PR's justification for choosing no-TZ is that ENABLE and FREQ read back
as zero on whyred, so "TZ has NOT brought up OSM". Clover shows that inference
doesn't hold: ENABLE also reads 0 at boot on clover (our dump), yet clover's
Android treats the OSM as TZ-owned. ENABLE = 0 only means nobody has switched
the OSM on yet, and Android's driver does that itself in both modes. (Whyred's
stock tree may genuinely differ; that wasn't checked here.)

Expected result on clover: the direct writes to secure registers are either
ignored (no speed change at all, which matches the SDM660 tester's "same
benchmark at max and min"), or rejected by the hardware protection, which on
Qualcomm can reset the device.

### 2. Nothing turns the voltage requests into actual voltage

On clover the CPU rails are driven by two CPRh controllers. Android's kernel
programs them with per-chip fused data: open-loop and closed-loop fuse
adjustments, floors, ceilings, and the corner-to-fmax map. The OSM only
*requests* a corner. The PR writes `corner | open-loop mV` into each row's
`VOLT_REG` but never programs CPRh. So it is unknown whether any rail voltage
follows the requested corner.

Also, the PR numbers its virtual corners 1-21 / 1-28 (finer tables), while
clover's CPRh knows 8 / 7 corners. Even with CPRh programmed, those numbers
would not line up.

If the OSM did raise the clock while the rail stayed at the boot voltage, the
CPU would be undervolted at high clocks: crashes, and possibly silent data
corruption while the rootfs is mounted read-write. Undervolting rarely damages
hardware, but corrupted writes put the installed system at risk.

## Verdict

**Do not boot PR #239 on clover as it stands.** Its voltage numbers are right
for clover, but it takes the wrong set-up path for this firmware and leaves
the voltage controller untouched. The most likely outcome is no effect; the
worse ones are a reset, or high clocks at too low a voltage.

What a clover-correct version would need:

1. The **TZ-owned path**: secure sequencer registers through
   `qcom_scm_io_writel`, no microcode load, matching the Android driver's
   `secure_init == false` branches.
2. **CPRh programming** for both controllers from clover's data. This is the
   larger half. Del Regno's and Maggio's CPR3/CPRh driver (2021, unmerged,
   carried forward by the HiBy RS6 project) is the existing starting point.
3. A virtual-corner numbering that matches clover's CPRh corners, or clover's
   own 8/7-row tables instead of the finer whyred-derived ones.

For any eventual test, boot with the root filesystem **read-only** (change
`pmos_rootfsopts=defaults` to `ro` in the test image's cmdline). Then an
undervolt crash cannot corrupt the installed system. Measure the result with
the dependent-add clock method from `docs/nura-cpu-clock-measurement.md`, not
just the cpufreq sysfs values.

The PR author lacks three facts that clover provides: a stock tree that is
TZ-owned while ENABLE reads 0 at boot, the CPRh tables, and the boot-time
register dump. Posting them to the PR would help the other SDM660 owners.
Doing so is a public post on the user's behalf, so it is the user's decision.
