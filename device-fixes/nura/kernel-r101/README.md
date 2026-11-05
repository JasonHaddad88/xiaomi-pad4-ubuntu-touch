# Kernel r101 for clover (installed 2026-11-05)

`linux-postmarketos-qcom-sdm660-7.0.14-r101`: r100's 27 patches plus four
(0028-0031), built the same way as r100. The pristine aport is patched only
for the build: `pkgrel=101`, the 31 patches added to `source=`, and the
config in `config-r101.aarch64`. Apk md5 `e892ae4b66aa46b791c1168a9de25b49`
(kept outside git in `~/osm-diag/kept/`).

Config: the four options r100 set, read back from r100's own IKCONFIG
(`ARM_QCOM_CPUFREQ_HW=y`, `QCOM_SPM=y`, `QCOM_CPR3=y`,
`MODULE_ALLOW_BTF_MISMATCH=y`), plus `QCOM_MPM=y`. A first build that set
only two of them came out with CPR3 off. It was caught by reading the built
kernel's IKCONFIG and never booted.

## The four new patches

| patch | what | result on clover |
|---|---|---|
| 0028 drm/msm/a5xx | use the speed-bin catalog for `qcom,sda660` | `GPU speedbin fuse 135 (0x87), mapped to opp-supp-hw 0x10`: 465 and 588 MHz available (was 370 max) |
| 0029 ASoC msm8916-wcd-digital | take MCLK per stream instead of from probe to remove | the audio DSP power collapses (RPM master stats: 2 shutdowns since boot -> dozens a minute); speakers still work (tone heard) |
| 0030 clover DT | PSCI OSI idle (`sda660-xiaomi-clover-psci-osi.dtsi`) and RPM master stats nodes | the source build is semantically identical to the hand-made OSI DTB (`tools/dtb-semantic-diff.py`) |
| 0031 cpuidle-psci | create the faux cpuidle device at `late_initcall_sync` | needed when a CPU PM domain has a late parent (the MPM); otherwise CPU idle is lost entirely |

## Install

`apk add --allow-untrusted` with the md5 checked on the tablet first. The
boot partition was flashed by mkinitfs: `boot.img` md5
`1389864848923ecbf36518767c20f795`, equal to the partition. World pin
`linux-postmarketos-qcom-sdm660><Q1t1gwzUiw+1No+DdBoN8ViAAHTs0=`.
Verified after a normal reboot: OSI idle, retention with 0 rejections, DVFS
1843 / 2208 MHz, GPU at 588 MHz, both TAS2557 amps ready, MCLK 0 when idle,
Wi-Fi up, no failed units.

The stop-gap copy of the codec module in `/usr/lib/modules/.../updates/`
was removed, since the package carries the fix.

**Rollback:** `/boot/boot.img.osi-r100` and `sda660-xiaomi-clover.dtb.osi-r100`
are on the tablet; the r100 apk is in `~/osm-diag/kept/`
(`apk add --allow-untrusted linux-postmarketos-qcom-sdm660-7.0.14-r100-dvfs.apk`).

## Not installed: the MPM / APSS system-sleep layer

`clover-mpm-test.dts` (on top of the r101 DT) adds:
- the MPM (from Android's `qcom,mpm@7781b8`: SPI 171, IPC bit 1, 96 pins, its
  9 real GIC pins, SPMI routed through pin 87)
- TLMM `wakeup-parent`
- an APSS system domain under it with Android's system-PC state
  `0x42000343`, whose huge min-residency keeps it to s2idle

Tested by RAM boot (T27, r101b):

- CPU idle works with the hierarchy (after patch 0031).
- In a 60 s suspend, **APSS shutdowns went 0 -> 3** (with the cable in) and
  3 -> 4 (unplugged): the RPM now sees the CPU subsystem power down.
- The RTC alarm woke it on time both times.
- XO shutdown stays 0 and `vlow`/`vmin` stay 0. The candidate remaining XO
  votes held by Linux are `bi_tcxo` (count 3, `1a300000.remoteproc`: the
  CDSP's proxy vote, apparently never released), `rf_clk1_pin` (Wi-Fi) and
  `gpucc_cxo_clk`.

Pins 81/82 duplicate the GIC lines of 79/80 and are rejected by the driver
(harmless). The power-key wake is untested.

## The last XO blocker: `video_core_clk_src` is `CLK_IS_CRITICAL` (test only)

A clk trace across a 60 s s2idle on the installed r101 (2026-11-05):

- Wi-Fi drops `rf_clk1_pin` when it disconnects.
- The display path drops all its `bi_tcxo` children during `dpm_suspend`:
  `vsync_clk_src`, `mdss_ahb_clk`, `ahb_clk_src`, `mnoc_ahb_clk`,
  `bimc_smmu_ahb_clk`.
- `bi_tcxo` itself is **never disabled**.

The reason is that mmcc-sdm660 marks `video_core_clk_src` (an RCG fed from
XO) `CLK_IS_CRITICAL`. An RCG has no gate, so the flag only pins its parent,
the RPM XO clock, which is voted in **both** active and sleep sets. Linux
therefore always asks the RPM to keep XO on while the CPUs sleep, which
matches APSS shutdowns with 0 APSS XO shutdowns.

`test-r102/0032-...patch` drops the flag. Built as test package r102
(`3ff49b1a62ed21eba35d0f087f73e862`, not installed); RAM-test images in
`backups/kernel-r101-2026-11-05/` (on the installed r101 boot.img):

- `TEST28-r102-mpm.img` (`240528f1...`): r102 + MPM/system-sleep DTB; the real test
- `TEST29-r102.img` (`b981bdc5...`): r102 + normal r101 DTB; control

To check: boot, display, video (Venus) still fine; in an unplugged 60 s
suspend, APSS *XO* shutdown count and `vlow`/`vmin` should finally move.
