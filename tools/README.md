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

## The id hash is not optional

The header's `id` field (offset 576, 20-byte SHA1) **is verified by clover's
bootloader**:

```
id = SHA1(kernel || le32(len(kernel)) || ramdisk || le32(len(ramdisk))
                 || second || le32(len(second)))
```

An image with a zeroed id is accepted by fastboot -- `Sending... OKAY`,
`Booting OKAY` -- and then fails **silently**: black screen, never reaches the
network, no console, no panic. It is indistinguishable from a kernel hang.

This cost four boot cycles on 2026-10-25. Three diagnostic kernels "hung" and
the kernel code was blamed and rewritten each time, when the real fault was
this script zeroing the id behind a comment claiming fastboot did not check
it. An untested assumption in a comment. What exposed it was finally booting
a control kernel with no patch at all, which failed identically.

## Validate changes offline, not on the device

Repacking a known-good image from its own parts, with its own cmdline, must
reproduce it **byte for byte**:

```sh
python3 -I tools/swap-bootimg-kernel.py --split good.img /tmp/g.gz /tmp/g.dtb
python3 -I tools/swap-bootimg-kernel.py good.img /tmp/g.gz /tmp/g.dtb /tmp/rt.img
cmp good.img /tmp/rt.img && echo IDENTICAL
```

For clover's installed image that is md5 `62cbaf2f3e2d24b0d5322376c7e69931`.
This test is free, needs no device, and catches exactly the bug above. Run it
after any change here.

## Reading the size report

For a same-version kernel the blob total lands within a few KB of the
original. Against `boot-INSTALLED-speakers+capfix.img` the delta was -1920
bytes, entirely in the DTB -- which proved that image is the *stock* kernel
carrying a *patched* DTB. So the speaker and capacity fixes live in the device
tree, and a permanent kernel build must re-apply those DTB edits or it will
silently lose the speakers.
