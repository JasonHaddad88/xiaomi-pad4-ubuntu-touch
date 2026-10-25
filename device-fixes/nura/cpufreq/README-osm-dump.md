# Read-only OSM diagnostic kernel

`0001-osm-dump-diagnostic.patch` adds `drivers/soc/qcom/osm-dump.c` (built
unconditionally via `obj-y`) and a `late_initcall` that dumps SDM660's
Operating State Manager state to dmesg at boot.

**It writes nothing.** Every access is `readl_relaxed`. The point is to answer
one question before any register is written: how much of the OSM did clover's
bootloader actually program?

It reports, for each cluster (`pwrcl` A53 at 0x179c0000, `perfcl` A73 at
0x179c2000):

- `VERSION` (+0x0000) — sanity check that the mapping is real
- `ENABLE_REG` (+0x1004) bit 0 — is the OSM switched on at all
- `DCVS_PERF_STATE_DESIRED` (+0x1f10) — which LUT row is live right now
- all 40 LUT rows: `INDEX` (+0x1150), `FREQ` (+0x1154), `VOLT` (+0x1158),
  stride 32 — decoded as `src`, `lval` and `lval * 19.2 MHz`

## Why it is needed

Mainline `qcom-cpufreq-hw` only *reads* a LUT that firmware programmed. On
SDM660 the downstream kernel programs it (`clk-cpu-osm.c` writes the rows,
then `ENABLE_REG = 1`). So the viability of a small cpufreq patch depends
entirely on what the bootloader left behind, and that is not knowable from
source — only from the hardware.

`CONFIG_STRICT_DEVMEM=y` blocks reading these registers from userspace, which
is why this has to be in-kernel.

## How to apply

Drop the patch into the kernel aport and add it to `source=`:

```
~/.local/var/pmbootstrap/cache_git/pmaports/device/testing/linux-postmarketos-qcom-sdm660/
```

Note that pmbootstrap uses `cache_git/pmaports`, **not** any other pmaports
checkout on the machine. Then:

```sh
pmbootstrap -y checksum linux-postmarketos-qcom-sdm660
pmbootstrap -y build linux-postmarketos-qcom-sdm660 --force
```

## How it is tested

Via `fastboot boot` only — RAM-only, nothing is flashed, and a power cycle
returns the device to the installed kernel. The installed boot partition is
unchanged and still backed up at
`backups/nura-internal-2026-10-25/boot-INSTALLED-speakers+capfix.img`
(md5 `62cbaf2f3e2d24b0d5322376c7e69931`).

Residual risk is low but not zero: reading an unclocked or unpowered register
window on Qualcomm hardware can abort. The OSM block sits in the APCS domain,
which is necessarily powered because the CPUs are executing. Worst case is a
hang during boot, recoverable by holding power.

## Removing it

Delete the patch from `source=`, re-run `pmbootstrap checksum`, rebuild. It is
a diagnostic and must not ship in an installed kernel.
