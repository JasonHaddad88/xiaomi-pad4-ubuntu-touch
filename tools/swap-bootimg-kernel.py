#!/usr/bin/env python3
"""Swap the kernel in an Android boot image (header v0), keeping everything else."""
import struct, sys, os

HDR = 1632

def rd(p):
    with open(p, 'rb') as f:
        return f.read()

def pad(b, ps):
    r = len(b) % ps
    return b + (b'\0' * (ps - r) if r else b'')

src, newk, dtb, out = sys.argv[1:5]
img = rd(src)
assert img[:8] == b'ANDROID!', "not an Android boot image"

(ksz, kaddr, rsz, raddr, ssz, saddr, tags, ps, hv, osv) = struct.unpack_from('<10I', img, 8)
name = img[48:64]
cmdline = img[64:576]
extra = img[608:1632]

print(f"--- source: {src}")
print(f"  page_size      = {ps}")
print(f"  header_version = {hv}")
print(f"  kernel  {ksz:>9} @ 0x{kaddr:08x}")
print(f"  ramdisk {rsz:>9} @ 0x{raddr:08x}")
print(f"  second  {ssz:>9} @ 0x{saddr:08x}")
print(f"  tags             @ 0x{tags:08x}")
print(f"  cmdline = {cmdline.rstrip(chr(0).encode()).decode(errors='replace')!r}")

# carve out the existing parts
off = (HDR + ps - 1) // ps * ps
kern_old = img[off:off+ksz]; off += (ksz + ps - 1)//ps*ps
ramdisk  = img[off:off+rsz]; off += (rsz + ps - 1)//ps*ps
second   = img[off:off+ssz]

# new kernel = Image.gz with DTB appended (deviceinfo_append_dtb="true")
k = rd(newk)
d = rd(dtb)
kern_new = k + d
print(f"\n--- new kernel blob")
print(f"  Image.gz       = {len(k)}")
print(f"  DTB            = {len(d)}")
print(f"  total          = {len(kern_new)}  (old was {ksz}, delta {len(kern_new)-ksz:+d})")

# rebuild header with the new kernel size, everything else identical
h = bytearray(img[:HDR])
struct.pack_into('<I', h, 8, len(kern_new))
struct.pack_into('<32x', h, 576)   # blank the id/hash; fastboot boot does not verify it

blob = pad(bytes(h), ps) + pad(kern_new, ps) + pad(ramdisk, ps) + (pad(second, ps) if ssz else b'')
with open(out, 'wb') as f:
    f.write(blob)
print(f"\n--- wrote {out}: {len(blob)} bytes")
print(f"  ramdisk reused verbatim: {len(ramdisk)} bytes")
