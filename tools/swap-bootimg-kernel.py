#!/usr/bin/env python3
"""Swap the kernel in an Android boot image (header v0), keeping everything else.

Usage:
    swap-bootimg-kernel.py <src.img> <Image.gz> <dtb> <out.img> [new-cmdline]
    swap-bootimg-kernel.py --split <src.img> <out-Image.gz> <out.dtb>

The ramdisk, load addresses and page size are copied verbatim from <src.img>.
The DTB is appended to the gzipped kernel, which is what clover needs
(deviceinfo_append_dtb="true").

The header `id` field (a SHA1 over the contents) is recomputed with
mkbootimg's recipe. Clover's bootloader does not appear to verify it (see
tools/README.md), but a correct id costs nothing:

    id = SHA1(kernel || le32(ksize) || ramdisk || le32(rsize)
                     || second || le32(ssize))

This swaps the kernel only, not the rootfs modules. With BTF module
validation enabled, a kernel whose BTF differs from the installed modules'
refuses them all (no display, no Wi-Fi). Build RAM-test kernels with
CONFIG_MODULE_ALLOW_BTF_MISMATCH=y.

Pass [new-cmdline] to replace the kernel command line. Keep the
pmos_boot_uuid and pmos_root_uuid values from the original or the initramfs
cannot find root; the script warns if either disappears.

--split extracts a source image's own Image.gz and DTB, which is how to
round-trip test this script: repacking an image from its own parts with its
own cmdline must reproduce it byte for byte.
"""
import hashlib
import struct
import sys

HDR = 1632
DTB_MAGIC = bytes([0xd0, 0x0d, 0xfe, 0xed])


def rd(path):
    with open(path, 'rb') as f:
        return f.read()


def pad(data, page):
    rem = len(data) % page
    return data + (b'\0' * (page - rem) if rem else b'')


def parse(img):
    if img[:8] != b'ANDROID!':
        sys.exit("not an Android boot image")
    (ksz, kaddr, rsz, raddr,
     ssz, saddr, tags, ps, hv, osv) = struct.unpack_from('<10I', img, 8)
    off = (HDR + ps - 1) // ps * ps
    kernel = img[off:off + ksz]
    off += (ksz + ps - 1) // ps * ps
    ramdisk = img[off:off + rsz]
    off += (rsz + ps - 1) // ps * ps
    second = img[off:off + ssz]
    return dict(ksz=ksz, kaddr=kaddr, rsz=rsz, raddr=raddr, ssz=ssz,
                saddr=saddr, tags=tags, ps=ps, hv=hv,
                kernel=kernel, ramdisk=ramdisk, second=second,
                cmdline=img[64:576], id=img[576:608])


def bootimg_id(kernel, ramdisk, second):
    """The SHA1 mkbootimg stores in the header's id field."""
    h = hashlib.sha1()
    for part in (kernel, ramdisk, second):
        h.update(part)
        h.update(struct.pack('<I', len(part)))
    return h.digest()


def do_split(src, out_gz, out_dtb):
    p = parse(rd(src))
    i = p['kernel'].find(DTB_MAGIC)
    if i < 0:
        sys.exit("no appended DTB found in %s" % src)
    with open(out_gz, 'wb') as f:
        f.write(p['kernel'][:i])
    with open(out_dtb, 'wb') as f:
        f.write(p['kernel'][i:])
    print("split %s: Image.gz=%d -> %s, DTB=%d -> %s"
          % (src, i, out_gz, p['ksz'] - i, out_dtb))


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == '--split':
        if len(sys.argv) != 5:
            sys.exit(__doc__)
        return do_split(*sys.argv[2:5])

    if len(sys.argv) < 5:
        sys.exit(__doc__)

    src, newk, dtb, out = sys.argv[1:5]
    new_cmdline = sys.argv[5] if len(sys.argv) > 5 else None

    img = rd(src)
    p = parse(img)
    ps = p['ps']
    cmdline_txt = p['cmdline'].rstrip(b'\0').decode(errors='replace')

    print("--- source: %s" % src)
    print("  page_size      = %d" % ps)
    print("  header_version = %d" % p['hv'])
    print("  kernel  %9d @ 0x%08x" % (p['ksz'], p['kaddr']))
    print("  ramdisk %9d @ 0x%08x" % (p['rsz'], p['raddr']))
    print("  second  %9d @ 0x%08x" % (p['ssz'], p['saddr']))
    print("  id             = %s" % p['id'][:20].hex())
    print("  cmdline = %r" % cmdline_txt)

    kern_new = rd(newk) + rd(dtb)
    print("")
    print("--- new kernel blob")
    print("  Image.gz       = %d" % len(rd(newk)))
    print("  DTB            = %d" % len(rd(dtb)))
    print("  total          = %d  (old was %d, delta %+d)"
          % (len(kern_new), p['ksz'], len(kern_new) - p['ksz']))

    h = bytearray(img[:HDR])
    struct.pack_into('<I', h, 8, len(kern_new))

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

    # recompute the id: the bootloader checks it
    new_id = bootimg_id(kern_new, p['ramdisk'], p['second'])
    h[576:608] = new_id + b'\0' * 12
    print("")
    print("--- id recomputed")
    print("  old = %s" % p['id'][:20].hex())
    print("  new = %s" % new_id.hex())

    blob = pad(bytes(h), ps) + pad(kern_new, ps) + pad(p['ramdisk'], ps)
    if p['ssz']:
        blob += pad(p['second'], ps)

    with open(out, 'wb') as f:
        f.write(blob)

    print("")
    print("--- wrote %s: %d bytes" % (out, len(blob)))
    print("  ramdisk reused verbatim: %d bytes" % len(p['ramdisk']))


if __name__ == '__main__':
    main()
