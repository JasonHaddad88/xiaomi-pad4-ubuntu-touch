# Installing Nura to clover's internal storage (replacing Ubuntu Touch)

Done on **25 October 2026**. Nura now boots from the internal eMMC with no SD card and no
`fastboot boot` step. Ubuntu Touch is gone.

**Why move off the SD card:** measured, not assumed.

| | sequential read | bus | size |
|---|---|---|---|
| SD card (SL16G) | **37.9 MB/s** | DDR50, 4-bit, 50 MHz | 13.9 GB |
| internal eMMC | **221.9 MB/s** | HS400 enhanced strobe, 8-bit, 192 MHz | 58.2 GB |

5.9x on sequential read, and far wider on random I/O, which is what makes a desktop OS feel
slow. The rootfs also grew from 14 GB to **49 GB**.

**What it costs:** the camera. Ubuntu Touch had a working camera via the Android container;
mainline has no driver for clover's sensors. See
[`device-fixes/nura/camera/`](../device-fixes/nura/camera/).

## Partition map

```
boot      p12   64 MB     <- Android boot image (kernel + initramfs + appended DTB)
system    p13   3072 MB   <- the pmOS_boot filesystem
vendor    p14   2048 MB   <- UNTOUCHED: TAS2557 firmware, camera configs
userdata  p64   51.9 GB   <- the pmOS_root filesystem
```

`vendor` must not be flashed. `msm-firmware-loader` exposes it at
`/run/msm-firmware-loader/mnt/vendor`, and that is where the speaker amplifier firmware and
the stock camera configuration live.

## The install

```sh
pmbootstrap config device xiaomi-clover
pmbootstrap config ui phosh
pmbootstrap config kernel clover
pmbootstrap -y install --split --password <pw> --filesystem ext4
```

`--split` produces two partition images instead of one disk image:
`xiaomi-clover-boot.img` (512 MB ext2) and `xiaomi-clover-root.img` (2.4 GB ext4).

### The boot image needs the speaker DTB spliced in

The DTB is appended to the gzipped kernel inside the boot image
(`deviceinfo_append_dtb="true"`, header v0). Replace that tail with the patched DTB, fix
`kernel_size` in the header and recompute the `id` SHA1. Method and script:
[`device-fixes/nura/speakers/`](../device-fixes/nura/speakers/). Check the base DTB's md5
matches the one the patch was derived from before reusing a prepared DTB - it did here
(`70bebc54425a50cc577b22aac000cdbd`).

### Flashing

The initramfs finds its filesystems **by UUID**, from the kernel cmdline:

```
pmos_boot_uuid=2356cf0b-...   pmos_root_uuid=ed3374c1-...
```

Those are the UUIDs *inside* the generated images, which is why the boot filesystem can live
on `system` and why **an SD card with another Nura install can stay inserted** - different
UUIDs, no ambiguity about which one boots.

```sh
fastboot flash boot   new-boot-tas2557.img     # 25 MB
fastboot flash system xiaomi-clover-boot.img   # 512 MB
```

### The 2.4 GB rootfs will not flash directly

`fastboot flash userdata xiaomi-clover-root.img` dies with:

```
libc++abi: terminating due to uncaught exception of type std::bad_alloc
```

fastboot (37.0.0) builds the whole sparse image in memory. `-S 256M` does **not** help; it
crashes before sending a byte, so nothing is written and the old rootfs is still intact at
that point. Pre-convert and split instead:

```sh
img2simg xiaomi-clover-root.img root.simg          # 2.4 GB -> 1.8 GB
simg2simg root.simg root.chunk 268435456           # -> root.chunk.0 .. .7
for i in 0 1 2 3 4 5 6 7; do fastboot flash userdata root.chunk.$i; done
```

Each chunk carries its own block offsets, so flashing them in sequence to the same partition
is correct. `max-download-size` on this bootloader is 512 MB. Whole transfer ran at about
42 MB/s. (`img2simg`/`simg2simg` come from `android-sdk-libsparse-utils`.)

Then `fastboot reboot`. pmOS resizes the rootfs to fill the partition on first boot by itself.

## What did NOT need reapplying

Three fixes from the SD-card era turned out unnecessary on a current install:

- **`msm-firmware-loader`** - the missing `mkdir -p "$BASEDIR"` is fixed upstream as of
  **1.9.0-r0**. `/run/msm-firmware-loader/mnt/{vendor,persist}` is populated unpatched.
- **TAS2557 firmware** - no manual copy needed. `msm-firmware-loader` exposes the vendor
  partition and the DTB's `firmware-name = "tas2557s_uCDSP.bin"` finds the blob there, so
  both amps report `PG2.1 left/right ready` at boot.
- **WEP `wpa_supplicant`** - pmbootstrap built 2.11-r99 from the local
  `temp/wpa_supplicant` override and included it in the image automatically.

## What did need reapplying

- **`board-2.bin`** - the stock image ships the 480 KB upstream file; without this device's
  own calibration the firmware crashes (`firmware crashed!`,
  `failed to set 2g txpower 40: -108`). Copy to
  `/lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin` (md5 `5b87ec6e67c8046b56665c1d1c5bfe0e`).
  Takes effect on the next boot.
- **UCM `Speaker` device** - [`device-fixes/nura/speakers/`](../device-fixes/nura/speakers/).
- **DNSSEC** - [`device-fixes/nura/resolved-10-clover-dns.conf`](../device-fixes/nura/resolved-10-clover-dns.conf),
  needed for the home router. Applied before going home rather than after it broke.

## Going back to Ubuntu Touch

`backups/ut-2404-pre-nura-2026-10-15/` holds a verified restore set (all five images pass
`md5sum -c`), with instructions in its `RESTORE.md`. It does not include the UT-side SD-card
protection tweaks, which are moot once UT is not running.
