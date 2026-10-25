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

598 MHz is ~31 x 19.2 MHz, i.e. a low entry in the OSM table, not a
derated maximum.

## What this explains

Three earlier observations were all one bug:

1. **"The big cores are the slow ones."** An A73 at 598 MHz is genuinely
   slower than an A53 at 1378 MHz, despite the A73's ~1.5x higher IPC.
   The benchmark was right; the hardware is misconfigured.
2. **The capacity fix was correct as a workaround.** `cpu_capacity` now reads
   1024 for the A53s and 471 for the A73s, so the scheduler prefers the cores
   that actually deliver today. 471/1024 = 0.46, which matches
   (0.598 x 1.5) / 1.378 = 0.65 in the right direction and confirms the
   clusters are not interchangeable.
3. **The anemia itself.** Nothing was throttling or overheating. The CPUs
   were simply never told to go fast.

## Size of the prize

Treating an A53 cycle as 1.0 and an A73 cycle as ~1.5:

| | today | with full OSM range | gain |
|---|---|---|---|
| single thread (best core) | 1.38 | 3.69 | **2.7x** |
| all 8 cores | 9.1 | 22.1 | **2.4x** |

Single-thread is what makes Settings and app launches feel slow, so the
~2.7x is the number that matters for the reported symptom.

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
