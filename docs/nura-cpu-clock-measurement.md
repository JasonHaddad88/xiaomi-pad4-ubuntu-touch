# The anemia, measured: the A73 cluster runs at 24% of its rated clock

Date: 2026-10-25. Device: Xiaomi Mi Pad 4 (clover), Nura (postmarketOS),
mainline kernel 7.0.14-sdm660.

## Method

There is no cpufreq driver on this platform, so there is no
`/sys/devices/system/cpu/cpu*/cpufreq` to read a frequency from. To get the
real clock I timed a chain of **dependent** `add` instructions. A dependent
integer add has 1-cycle latency on both Cortex-A53 and Cortex-A73, so the
chain retires at exactly one instruction per cycle and the measured
instruction rate *is* the core clock:

```c
"1:\n" ".rept 64\n" "add %1, %1, #1\n" ".endr\n" "subs %0, %0, #1\n" "b.ne 1b\n"
```

64 adds per iteration amortises the 2-instruction loop overhead to ~3%.
Run pinned per core with `taskset -c N`.

## Result

```
cpu0 A53 Silver  1377.8 MHz
cpu1 A73 Gold     598.1 MHz
cpu2 A73 Gold     598.1 MHz
cpu3 A73 Gold     598.0 MHz
cpu4 A73 Gold     598.1 MHz
cpu5 A53 Silver  1378.5 MHz
cpu6 A53 Silver  1378.8 MHz
cpu7 A53 Silver  1378.9 MHz
```

| cluster | cores | measured | hardware max (speedbin 0) | % of max |
|---------|-------|----------|---------------------------|----------|
| A53 Silver (pwrcl)  | cpu0, cpu5, cpu6, cpu7 | 1378 MHz | 1843.2 MHz | 75% |
| A73 Gold   (perfcl) | cpu1-cpu4             |  598 MHz | 2457.6 MHz | **24%** |

Neither value is an exact multiple of the 19.2 MHz crystal (598.1 / 19.2 =
31.15; 1378 / 19.2 = 71.8), so this data alone cannot map them to specific OSM
table rows. (An earlier version said 598 MHz was "~31 x 19.2 MHz, a low entry
in the OSM table". That was a guess and has been removed.)

Why the result is credible despite being one method: cores in a cluster share
one clock, so all four of each kind *should* read the same, and they do to
within 0.2%. Random measurement error would scatter. And the A73s losing to
the A53s was already seen independently in the earlier openssl RSA/MD5 runs.

## What this explains

1. **"The big cores are the slow ones."** An A73 does more work per clock than
   an A53 (very roughly 1.3-2x, depending on the code), but at 598 vs 1378 MHz
   it gets 2.3x fewer clocks, so it loses.
2. **The capacity fix was the right workaround.** `cpu_capacity` reads 1024
   for the A53s and 471 for the A73s, so the scheduler prefers the cores that
   actually deliver today. (471 came from a benchmark ratio, not from these
   clock numbers.)
3. **The anemia itself.** Nothing was throttling or overheating. Mainline
   SDM660 has no CPU frequency driver, so each cluster stays at whatever clock
   the bootloader left it on.

## Size of the prize: a ceiling, not a promise

If both clusters ran at their rated maximum (A53 1843 MHz, A73 2458 MHz), and
an A73 clock is worth ~1.5 A53 clocks (an assumption, not measured here):

| | today | at rated maximum | gain |
|---|---|---|---|
| single thread (best core) | 1.38 | 3.69 | ~2.7x |
| all 8 cores | 9.1 | 22.1 | ~2.4x |

Two caveats. The 1.5 factor is a rule of thumb; the real figure depends on the
workload. And rated clocks need matching voltages, which is exactly the
unsolved OSM problem. Treat these as upper bounds. Single-thread speed is what
makes Settings and app launches feel slow.

## Why no frequency scaling exists

Upstream `sdm630.dtsi` has no CPU OPP tables and no cpufreq node at all, and
SDM660 mainline support is otherwise mature. The reason is architectural:

- Mainline's `qcom-cpufreq-hw` is a **read-only consumer** of the OSM
  (Operating State Manager) LUT. It assumes firmware has already programmed
  and enabled it, which is true from SDM845 onward.
- On SDM660 the **kernel** programs the LUT. The downstream driver
  (`clk-cpu-osm.c`, ~3300 lines) writes `INDEX_REG`/`FREQ_REG`/`VOLT_REG`
  per row and then sets `ENABLE_REG = 1` itself, after reading speedbin
  fuses and deriving open-loop voltages, APM thresholds and MEM ACC settings.

So the open question is **not** "what are the register offsets" (those are
known, see nura-cpufreq-plan.md) but **how much of the OSM did clover's
bootloader already set up**. The CPUs are running at *some* programmed rate,
so the OSM is at least partly live.

Next step: a read-only diagnostic kernel that dumps `ENABLE_REG`, the current
perf state and all 40 LUT rows for both clusters. That single boot decides
between:

- **LUT already programmed** -> add `sdm660_soc_data` + a DT node and
  `qcom-cpufreq-hw` works nearly as-is (small patch).
- **LUT empty/garbage** -> the LUT must be programmed from scratch, including
  voltages. Much larger, and carries real brown-out/over-volt risk.

Do not write perf states before that question is answered: with an
unprogrammed LUT, requesting an index selects an undefined voltage.

## Result (2026-10-30)


- **The OSM is switched off.** Read live from the hardware: `pwrcl` (A53)
  `VERSION = 0x00070000`, `ENABLE = 0`, `PERF_STATE = 0`; `perfcl` (A73)
  `VERSION = 0`, `ENABLE = 0`, `PERF_STATE = 0`. The bootloader never enables
  it. The current fixed clocks (A53 1378 MHz, A73 598 MHz) are set some other
  way at boot.
- **Reading these registers is safe.** Every read survived. Nothing hung.
- **The small-patch route is dead.** Mainline `qcom-cpufreq-hw` checks
  `ENABLE` bit 0 and gives up when it is 0. The sdm660-mainline tree has no
  driver that *programs* OSM, and no sdm630/636/660 device tree has CPU
  scaling. (`pmdomain/qcom/cpr.c` is the older CPR for msm8916/qcs404, not
  the CPRh this SoC needs.)
- Getting more speed means porting OSM programming plus CPRh voltage control,
  which is what downstream `clk-cpu-osm.c` does. That is a large job, and
  setting voltages wrongly can crash or damage the chip.

