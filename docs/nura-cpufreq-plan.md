> **CORRECTION (2026-10-25).** The plan below was written on a false premise.
> It assumed mainline's `qcom-cpufreq-hw` only needed the right register
> offsets to drive SDM660's OSM. It does not: `qcom-cpufreq-hw` is a
> *read-only consumer* of an OSM LUT that **firmware** is expected to have
> programmed and enabled (true from SDM845 on). On SDM660 the **kernel**
> programs it — downstream `clk-cpu-osm.c` writes `INDEX_REG`/`FREQ_REG`/
> `VOLT_REG` for every row (lines 1562-1564) and then sets `ENABLE_REG = 1`
> itself (line 741), after reading speedbin fuses and deriving open-loop
> voltages, APM thresholds and MEM ACC settings.
>
> The register map and offsets in this document are still correct and still
> needed. What changed is the question. It is no longer "what are the
> offsets" but **"how much of the OSM did clover's bootloader leave live?"**
> The CPUs do run at a programmed rate (A53 1378 MHz, A73 598 MHz — see
> [nura-cpu-clock-measurement.md](nura-cpu-clock-measurement.md)), so the
> OSM is at least partly set up.
>
> That is being settled by a read-only diagnostic kernel
> (`device-fixes/nura/cpufreq/0001-osm-dump-diagnostic.patch`) which dumps
> `ENABLE_REG`, the live perf state and all 40 LUT rows for both clusters.
> Outcomes:
>
> - **LUT programmed and enabled** -> the small patch below is viable
>   (`sdm660_soc_data` + DT node), with the `reg_dcvs_ctrl` fix noted below.
> - **LUT empty or garbage** -> the LUT has to be programmed from scratch,
>   voltages included. Much larger, and it carries real brown-out and
>   over-volt risk.
>
> Do not write a perf state before that dump is read: against an
> unprogrammed LUT, selecting an index selects an undefined voltage.
>
> One further correction to the patch below: `reg_dcvs_ctrl` is read
> **unconditionally** (line 548) with no NULL check, and it sets
> `per_core_dcvs`, which makes the driver write the perf state at
> `reg_perf_state + 4 * core`. On SDM660 that would land on the interrupt
> registers at 0x1f14+. SDM660 writes the perf state once per cluster, so
> `per_core_dcvs` must stay false — and rather than guess at a register
> whose bit 0 happens to read 0, the read should be guarded, mirroring how
> `reg_current_vote` and `reg_intr_clr` are already handled:
>
> ```c
> if (qcom_cpufreq.soc_data->reg_dcvs_ctrl &&
>     readl_relaxed(data->base + qcom_cpufreq.soc_data->reg_dcvs_ctrl) & 0x1)
>         data->per_core_dcvs = true;
> ```
>
> **Retracted 2026-10-29.** An earlier version of this paragraph quoted two
> "downstream SDM660 `freq_val` words" (`0x4000f`, `0x404003a`) and drew a
> conclusion from their `src` bits. Neither value appears anywhere in the
> downstream source: `clk-cpu-osm-660.c` takes `freq_val` from
> `entry[i].freq_data`, which it parses from the device tree at runtime. The
> claim had no basis. What *is* verified: mainline decodes
> `LUT_SRC = GENMASK(31,30)` and computes `freq = xo_rate * lval` only when
> `src != 0`, falling back to `cpu_hw_rate` otherwise. What the live SDM660
> table holds in those bits is unknown until the dump actually runs.

---

# Implementing CPU frequency scaling for SDM660 — everything needed

**The problem:** mainline SDM660 has no cpufreq. Each cluster sits at whatever perf state the
bootloader left it, and the A73 cluster is left at roughly its 300 MHz minimum, so it
delivers **half** the throughput of the A53 cluster. Evidence and measurements:
[`nura-performance.md`](nura-performance.md).

**Nobody has done this upstream.** No branch of `sdm660-mainline/linux` mentions
`cpufreq-hw`, OSM or `freq-domain` in its SoC DTSI.

**The good news:** SDM660's OSM register layout is structurally identical to what mainline's
`qcom-cpufreq-hw` already implements. It appears to need a new offsets table and a DT node,
not a new driver.

## Register map (authoritative)

From the downstream driver `drivers/clk/qcom/clk-cpu-osm-660.c` (LineageOS
`android_kernel_xiaomi_sdm660`, branch `lineage-20`):

```c
#define ENABLE_REG                   0x1004
#define INDEX_REG                    0x1150
#define FREQ_REG                     0x1154
#define VOLT_REG                     0x1158
#define OVERRIDE_REG                 0x115C
#define DCVS_PERF_STATE_DESIRED_REG  0x1F10
#define OSM_TABLE_SIZE               40        /* max LUT rows */
#define OSM_REG_SIZE                 32        /* LUT row stride */
#define OSM_CORE_TABLE_SIZE          8192      /* per-cluster window */
```

The LUT is a linear array with a 32-byte stride — the same shape mainline assumes:

```c
table_entry_offset = i * OSM_REG_SIZE;
write(i,        INDEX_REG + table_entry_offset);
write(freq_val, FREQ_REG  + table_entry_offset);
write(volt_val, VOLT_REG  + table_entry_offset);
```

### Offsets versus mainline

| | mainline `qcom,cpufreq-hw` | mainline `qcom,cpufreq-epss` | **SDM660** |
|---|---|---|---|
| `REG_ENABLE` | 0x0 | 0x0 | **0x1004** |
| `REG_FREQ_LUT` | 0x110 | 0x100 | **0x1154** |
| `REG_VOLT_LUT` | 0x114 | 0x200 | **0x1158** |
| `REG_PERF_STATE` | 0x920 | 0x320 | **0x1F10** |

Row stride is 32 bytes, which matches mainline's `LUT_ROW_SIZE`.

### Per-cluster bases

The driver takes one `"osm"` resource for pwrcl and derives perfcl from it:

```c
pwrcl  base = res->start;                                   /* 0x179c0000 */
perfcl base = pwrcl base + cluster_num * OSM_CORE_TABLE_SIZE; /* 0x179c2000 */
```

So two 8 KB windows: **0x179c0000 (A53/pwrcl)** and **0x179c2000 (A73/perfcl)**. Consistent
with the CPRh controllers at `0x179c4000` and `0x179c8000` sitting immediately above.

## Hardware frequency tables

From the downstream `qcom,clk-cpu-osm` node on this device (speedbin 0):

```
pwrcl  (A53): 300, 633.6, 902.4, 1113.6, 1401.6, 1536, 1747.2, 1843.2 MHz
perfcl (A73): 300, 1113.6, 1401.6, 1747.2, 1958.4, 2150.4, 2457.6 MHz
```

Other speedbins (1, 3, 4) cap lower; the driver selects by fuse. `qcom-cpufreq-hw` reads the
LUT the bootloader programmed, so the speedbin is handled in hardware and **voltages do not
have to be supplied by hand** — which is what makes this safe enough to attempt.

## The patch

### 1. `drivers/cpufreq/qcom-cpufreq-hw.c`

```c
static const u16 cpufreq_sdm660_offsets[REG_ARRAY_SIZE] = {
	[REG_ENABLE]     = 0x1004,
	[REG_FREQ_LUT]   = 0x1154,
	[REG_VOLT_LUT]   = 0x1158,
	[REG_PERF_STATE] = 0x1F10,
};

static const struct qcom_cpufreq_soc_data sdm660_soc_data = {
	.reg_offset = cpufreq_sdm660_offsets,
};
```

plus an `of_device_id` entry for `"qcom,sdm660-cpufreq-hw"`.

### 2. `arch/arm64/boot/dts/qcom/sdm630.dtsi`

```dts
cpufreq_hw: cpufreq@179c0000 {
	compatible = "qcom,sdm660-cpufreq-hw";
	reg = <0x179c0000 0x2000>, <0x179c2000 0x2000>;
	reg-names = "freq-domain0", "freq-domain1";
	clocks = <&rpmcc RPM_SMD_XO_CLK_SRC>, <&gcc GPLL0>;
	clock-names = "xo", "alternate";
	#freq-domain-cells = <1>;
};
```

and on the CPU nodes — **pwrcl is `cpu@0-3` (A53), perfcl is `cpu@100-103` (A73)**:

```dts
cpu@0   { qcom,freq-domain = <&cpufreq_hw 0>; };   /* A53  */
cpu@100 { qcom,freq-domain = <&cpufreq_hw 1>; };   /* A73  */
```

## Why userspace experimentation is not possible first

`CONFIG_STRICT_DEVMEM=y`, so `/dev/mem` cannot reach the OSM registers, and busybox has no
`devmem` applet. Nothing claims `0x179cxxxx` in `/proc/iomem`, so the region is free — but
touching it needs kernel code. There is no way to test the theory without a kernel build.

## Testing safely

`fastboot boot` the result. It is RAM-only, so a bad kernel or DTB cannot brick anything — a
power cycle returns to the installed system. Note `reboot bootloader` does **not** work on
Nura; fastboot needs Power + Volume Down.

Success looks like:

```
/sys/devices/system/cpu/cpu0/cpufreq/   exists
scaling_available_frequencies           300000 .. 1843200
cpu1 (A73) scaling_available_frequencies 300000 .. 2457600
```

and the A73 cluster finally outperforming the A53 cluster on RSA/MD5.

## Risks, honestly

- The driver writes only `REG_PERF_STATE`, which is the register designed for requesting a
  performance level; voltage follows via the LUT and CPRh in hardware. This is the intended
  mechanism, not a poke at unknown registers.
- If the offsets or bases are wrong, the LUT reads return nonsense and the probe should fail,
  or the device hangs on boot — recoverable by power cycle since testing is RAM-only.
- The bootloader may not have programmed or enabled the OSM LUT at all, in which case
  `REG_ENABLE` reads zero and the driver will refuse. That would mean implementing LUT
  programming too, which is a much larger job.

## If it works

Delete both workarounds: the `capacity-dmips-mhz` correction in the DTB
([`nura-performance.md`](nura-performance.md)) and the GPU `performance` governor pin, since
the A73 cluster would then be genuinely the fastest and the GPU could scale on demand again.
