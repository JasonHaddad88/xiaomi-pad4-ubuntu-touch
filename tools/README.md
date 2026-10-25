# tools

## swap-bootimg-kernel.py

Replaces the kernel inside an Android boot image (header v0) and leaves
everything else byte-for-byte alone — ramdisk, cmdline, load addresses,
page size.

```sh
python3 -I tools/swap-bootimg-kernel.py \
    <source-boot.img> <Image.gz> <device.dtb> <output-boot.img>
```

Why reuse the source image instead of running mkbootimg from scratch: the
installed ramdisk is the initramfs that resolves root **by UUID**, and the
cmdline carries `pmos_boot_uuid` / `pmos_root_uuid` for this specific install.
Regenerating either risks an unbootable image for no benefit when all we want
to change is the kernel.

clover needs the DTB **appended to the gzipped kernel**
(`deviceinfo_append_dtb="true"`), which this script does: the new kernel blob
is `Image.gz || dtb`. The header's `id` hash is zeroed, which `fastboot boot`
does not check.

Kernel and DTB come out of the built aport package:

```sh
tar xzf ~/.local/var/pmbootstrap/packages/edge/aarch64/linux-postmarketos-qcom-sdm660-*.apk
# boot/vmlinuz                           <- this is Image.gz
# boot/dtbs/qcom/sda660-xiaomi-clover.dtb <- clover is the Wi-Fi-only SDA660
```

### Useful sanity check

Print the sizes it reports. For a same-version kernel the blob total should
land within a couple of KB of the original. When this was first run against
`boot-INSTALLED-speakers+capfix.img` the delta was **-1920 bytes**, entirely
in the DTB — which proved the installed image was the *stock* kernel carrying
a *patched* DTB, i.e. the speaker and capacity fixes were made by editing the
device tree and repacking, not by rebuilding the kernel. Worth remembering:
a permanent kernel build must re-apply those DTB edits or it will silently
lose the speakers.
