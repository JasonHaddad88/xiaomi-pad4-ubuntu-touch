# SDM660 cpufreq reference material

`clk-cpu-osm-660.c` is the **downstream** OSM clock driver, kept here only as the
authoritative source of the register layout needed to add SDM660 support to mainline's
`qcom-cpufreq-hw`. It is GPL-2.0, taken from
`LineageOS/android_kernel_xiaomi_sdm660`, branch `lineage-20`,
`drivers/clk/qcom/clk-cpu-osm-660.c`.

It is **not** used or built on this device. Mainline has no OSM clock driver, and the plan is
not to port this one — `qcom-cpufreq-hw` already does the equivalent job generically, and the
only thing missing is the per-SoC register offsets this file documents.

What was extracted from it:

| | value |
|---|---|
| `ENABLE_REG` | 0x1004 |
| `FREQ_REG` (LUT) | 0x1154 |
| `VOLT_REG` (LUT) | 0x1158 |
| `DCVS_PERF_STATE_DESIRED_REG` | 0x1F10 |
| LUT row stride (`OSM_REG_SIZE`) | 32 bytes |
| per-cluster window (`OSM_CORE_TABLE_SIZE`) | 8192 bytes |
| pwrcl (A53) base | 0x179c0000 |
| perfcl (A73) base | 0x179c2000 |

Full plan: [`docs/nura-cpufreq-plan.md`](../../../docs/nura-cpufreq-plan.md).
