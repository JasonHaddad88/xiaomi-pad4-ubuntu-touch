# tools

## swap-bootimg-kernel.py

Replaces the kernel inside an Android boot image (header v0) and leaves
everything else byte-for-byte alone -- ramdisk, cmdline, load addresses,
page size.

```sh
python3 -I tools/swap-bootimg-kernel.py \
    <src.img> <Image.gz> <dtb> <out.img> [new-cmdline]

python3 -I tools/swap-bootimg-kernel.py --split <src.img> <out.gz> <out.dtb>
```

Why reuse the source image instead of running mkbootimg from scratch: the
installed ramdisk is the initramfs that resolves root **by UUID**, and the
cmdline carries `pmos_boot_uuid` / `pmos_root_uuid` for this specific install.
Regenerating either risks an unbootable image for no benefit when all we want
to change is the kernel.

clover needs the DTB **appended to the gzipped kernel**
(`deviceinfo_append_dtb="true"`), which this script does: the new kernel blob
is `Image.gz || dtb`.

Kernel and DTB come out of the built aport package:

```sh
tar xzf ~/.local/var/pmbootstrap/packages/edge/aarch64/linux-postmarketos-qcom-sdm660-*.apk
# boot/vmlinuz                            <- this is Image.gz
# boot/dtbs/qcom/sda660-xiaomi-clover.dtb  <- clover is the Wi-Fi-only SDA660
```

## The id hash

The header's `id` field (offset 576, 20-byte SHA1) is recomputed with
mkbootimg's recipe:

```
id = SHA1(kernel || le32(len(kernel)) || ramdisk || le32(len(ramdisk))
                 || second || le32(len(second)))
```

Clover's bootloader does **not** appear to check it. Ubuntu Touch's own
header-v0 `boot.img` carries an id that does not match its contents, yet it
booted from flash for weeks, and the Halium image booted via `fastboot boot`.
The script recomputes it anyway because that costs nothing.

An earlier version of this README claimed the opposite: that a zeroed id was
why locally built kernels black-screened. That was refuted when the same
kernel with a correct id failed identically.

## Swapping only the kernel is not enough

This script replaces the kernel but not the modules on the rootfs. This
kernel config has `CONFIG_DEBUG_INFO_BTF_MODULES=y` and does not set
`CONFIG_MODULE_ALLOW_BTF_MISMATCH`, so a kernel whose BTF differs from the one
the installed modules were built against (different compiler point release,
different config) **refuses every module**. The display (`DRM_MSM=m`) and
Wi-Fi (`ath10k`) are modules, so the result is a live kernel with a black
screen and no network. This is the leading explanation for the black screens
on 2026-10-25, not yet proven on the device. For RAM tests, build the test
kernel with `CONFIG_MODULE_ALLOW_BTF_MISMATCH=y`.

## Validate changes offline, not on the device

Repacking a known-good image from its own parts, with its own cmdline, must
reproduce it **byte for byte**:

```sh
python3 -I tools/swap-bootimg-kernel.py --split good.img /tmp/g.gz /tmp/g.dtb
python3 -I tools/swap-bootimg-kernel.py good.img /tmp/g.gz /tmp/g.dtb /tmp/rt.img
cmp good.img /tmp/rt.img && echo IDENTICAL
```

For clover's installed image that is md5 `62cbaf2f3e2d24b0d5322376c7e69931`.
This test is free and needs no device. Run it
after any change here.

## Reading the size report

For a same-version kernel the blob total lands within a few KB of the
original. Use `--split` to see where a difference actually is. Against the
installed image, the locally built r0 kernel differs by 1,659 bytes in
`Image.gz`, and its stock DTB by 1,051 bytes (speaker nodes and capacity
values). An earlier note here said a -1,920-byte delta was "entirely in the
DTB"; that arithmetic was wrong, because both parts differed. The conclusion it
supported still holds on other evidence (both pmaports trees carry no patches,
and the speaker README documents the dtc edit-and-splice workflow): the
speaker and capacity fixes live in the DTB, so a permanent kernel must carry
that DTB or the speakers go silent.
