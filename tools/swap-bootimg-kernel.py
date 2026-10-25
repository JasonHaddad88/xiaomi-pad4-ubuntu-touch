#!/usr/bin/env python3
"""Swap the kernel in an Android boot image (header v0), keeping everything else.

Usage:
    swap-bootimg-kernel.py <src.img> <Image.gz> <dtb> <out.img> [new-cmdline]

The ramdisk, load addresses and page size are copied verbatim from <src.img>.
The DTB is appended to the gzipped kernel, which is what clover needs
(deviceinfo_append_dtb="true"). The header id/hash is zeroed; `fastboot boot`
does not check it.

Pass [new-cmdline] to replace the kernel command line -- e.g. to drop
"quiet splash" so kernel messages reach the screen. Keep the pmos_boot_uuid
and pmos_root_uuid values from the original, or the initramfs cannot find
root; the script warns if either disappears.
"""
import struct
import sys

HDR = 1632


def rd(path):
    with open(path, 'rb') as f:
        return f.read()


def pad(data, page):
    rem = len(data) % page
    return data + (b'\0' * (page - rem) if rem else b'')


def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)

    src, newk, dtb, out = sys.argv[1:5]
    new_cmdline = sys.argv[5] if len(sys.argv) > 5 else None

    img = rd(src)
    if img[:8] != b'ANDROID!':
        sys.exit("not an Android boot image: %s" % src)

    (ksz, kaddr, rsz, raddr,
     ssz, saddr, tags, ps, hv, osv) = struct.unpack_from('<10I', img, 8)
    cmdline_raw = img[64:576]
    cmdline_txt = cmdline_raw.rstrip(b'\0').decode(errors='replace')

    print("--- source: %s" % src)
    print("  page_size      = %d" % ps)
    print("  header_version = %d" % hv)
    print("  kernel  %9d @ 0x%08x" % (ksz, kaddr))
    print("  ramdisk %9d @ 0x%08x" % (rsz, raddr))
    print("  second  %9d @ 0x%08x" % (ssz, saddr))
    print("  tags              @ 0x%08x" % tags)
    print("  cmdline = %r" % cmdline_txt)

    # carve out the existing parts
    off = (HDR + ps - 1) // ps * ps
    off += (ksz + ps - 1) // ps * ps          # skip the old kernel
    ramdisk = img[off:off + rsz]
    off += (rsz + ps - 1) // ps * ps
    second = img[off:off + ssz]

    # new kernel blob = Image.gz with the DTB appended
    k = rd(newk)
    d = rd(dtb)
    kern_new = k + d
    print("")
    print("--- new kernel blob")
    print("  Image.gz       = %d" % len(k))
    print("  DTB            = %d" % len(d))
    print("  total          = %d  (old was %d, delta %+d)"
          % (len(kern_new), ksz, len(kern_new) - ksz))

    # rebuild the header: new kernel size, everything else identical
    h = bytearray(img[:HDR])
    struct.pack_into('<I', h, 8, len(kern_new))
    struct.pack_into('<32x', h, 576)          # zero the id/hash

    if new_cmdline is not None:
        cb = new_cmdline.encode()
        if len(cb) > 511:
            sys.exit("cmdline too long: %d > 511" % len(cb))
        h[64:576] = cb + b'\0' * (512 - len(cb))
        print("")
        print("--- cmdline REPLACED")
        print("  old = %r" % cmdline_txt)
        print("  new = %r" % new_cmdline)
        for key in ('pmos_boot_uuid', 'pmos_root_uuid'):
            if key in cmdline_txt and key not in new_cmdline:
                print("  !! WARNING: %s dropped - root may not mount" % key)

    blob = pad(bytes(h), ps) + pad(kern_new, ps) + pad(ramdisk, ps)
    if ssz:
        blob += pad(second, ps)

    with open(out, 'wb') as f:
        f.write(blob)

    print("")
    print("--- wrote %s: %d bytes" % (out, len(blob)))
    print("  ramdisk reused verbatim: %d bytes" % len(ramdisk))


if __name__ == '__main__':
    main()
