# Why locally built kernels black-screen: test plan

Status 2026-10-29: **unresolved, images ready, nothing run yet.**

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

## Leading explanation (not yet proven)

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
