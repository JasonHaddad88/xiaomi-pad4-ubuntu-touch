> **STATUS 2026-10-29: read this first.** The v1-v3 sections below explain
> the black screens first as the dump hanging the SoC, then as an invisible
> console, and (in tools/) as a zeroed boot-image hash. **None of those was
> shown to be the cause.** A control kernel built from the same tree, with no
> patch and a correct hash, failed identically. Ubuntu Touch's own boot image
> shows the bootloader doesn't verify the hash. No OSM register read has been
> shown to hang anything; the dump may have run every time.
>
> Leading explanation, **not yet proven on the device**: the rootfs modules
> were built against the installed r2 kernel, and this config has
> `CONFIG_DEBUG_INFO_BTF_MODULES=y` without `CONFIG_MODULE_ALLOW_BTF_MISMATCH`.
> A locally built kernel (clang 23.1.4 vs 23.1.3, slightly different config)
> has different BTF, so it refuses every module, including the display
> (`DRM_MSM=m`) and Wi-Fi (`ath10k`): a live kernel with a black screen and no
> network. The refusal message, `failed to validate module [%s] BTF`, is in
> the kernel binary.
>
> Test images and the order to run them: `docs/nura-kernel-bisect.md`.
>
> Everything below is kept as a record of what was tried.

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

---

## v1 hung the device. What changed in v2

The first attempt booted to a **black screen** and never reached the network
(a 6-minute LAN sweep found nothing). Two mistakes, one in the code and one
in the test:

1. **The test was blind.** The boot image kept the installed cmdline, which
   starts `quiet splash`. `late_initcall` runs after the display driver but
   before Phosh, so a hang there draws nothing at all — no console, no
   splash, no panic text. There was no way to tell where it died, or even
   whether the dump was the cause.
2. **The dump took ~80 reads before saying anything useful.** If any single
   access aborts, everything after it is lost.

v2 fixes both:

- The boot image is repacked with
  `console=tty0 ignore_loglevel` **replacing** `quiet splash ...`, keeping
  `pmos_boot_uuid`/`pmos_root_uuid`. Kernel messages now land on the panel.
- Every message is `pr_emerg` (loglevel 0, always printed).
- Each risky access is announced *before* it happens, with a 30 ms delay to
  let the console drain, so the **last line on screen names the exact
  register that killed it**.
- `ENABLE_REG` is read first and the 40-row LUT walk only happens if the OSM
  reports itself enabled — fewer accesses, and the headline answer arrives
  before any bulk reading.

### What the outcome will mean

- Banner appears, then `ABOUT TO READ VERSION`, then nothing -> the OSM
  window is not readable from the kernel at all (XPU-protected or
  unclocked). That also rules out the small-patch route, because mainline
  `qcom-cpufreq-hw` reads this same window.
- Reads survive and `ENABLE` has bit 0 set with a real frequency ladder ->
  the small patch is viable.
- Boot hangs *before* the banner -> the dump is innocent and something else
  is wrong with the test kernel.

Verify the right code is in the image before flashing anything, rather than
trusting that the patch applied:

```sh
zcat boot/vmlinuz | strings | grep -E "OSM state \(v2\)|survived the first read"
```

---

## v3: get the log out by panicking on purpose

v2 failed for a reason that made the whole approach unworkable, not just
buggy: **`CONFIG_DRM_MSM=m`**. The display driver is a module, loaded from
userspace, so at `late_initcall` there is no framebuffer console at all.
`console=tty0` prints nowhere. A hang there is invisible no matter what the
cmdline says, so v2's "narrate each step to the screen" could never have
worked, and the black screen said nothing about whether the dump was at
fault.

Meanwhile the device already had the right mechanism configured:

- `ramoops@9fe00000`, `console-size = <0x80000>` in clover's device tree
- `CONFIG_PSTORE=y`, `CONFIG_PSTORE_RAM=y`, `CONFIG_PSTORE_CONSOLE=y`
- confirmed live at boot: `printk: legacy console [ramoops-1] enabled`

So every printk is already recorded into persistent DRAM. The obstacle was a
catch-22: escaping a hang needs a ~10 s power-button hold, and that drops
DRAM power and wipes the buffer. Proven the hard way — after the v2 boot,
`/sys/fs/pstore` was empty.

**v3 ends in a deliberate `panic()`**, with `panic=10` on the cmdline. The
kernel resets itself *warm*: DRAM keeps its contents, the device boots from
flash on its own, and the dump is waiting in `/sys/fs/pstore`. If a register
access aborts first, the oops is captured by the same path. No power-button
hold, nothing wiped, and the self-reboot is the success signal.

It also folds in the control test: if the `osm-dump` banner appears in
pstore, the kernel boots fine and we can see how far the reads got. If pstore
is empty, the kernel never ran, and `kernel-CONTROL-nopatch.apk` (an
unpatched build of the same tree, kept for exactly this) isolates the patch.

### Verified facts worth not re-deriving

- `fastboot boot` **does** work on clover: the known-good image came up in
  36 s. It is not a Xiaomi restriction.
- The installed kernel is `r2`; this tree builds `r0`. The only difference is
  commit `400b925` ("enable Vsmart Active 1 support"), which touches
  netfilter netdev tables, `CDROM`/`BLK_DEV_SR` and
  `DRM_PANEL_HIMAX_HX83112A`. Nothing clover needs, so an `r0` build is a
  valid baseline.
- `# CONFIG_MODVERSIONS is not set` and `# CONFIG_MODULE_SIG_FORCE is not
  set`, and vermagic is `7.0.14-sdm660 SMP preempt mod_unload aarch64` in
  both. The installed modules load against a locally built kernel.
- Build identity: a local build reports `#1-postmarketos-qcom-sdm660`,
  the installed one `#3-...`. That is how to tell which kernel actually ran.
