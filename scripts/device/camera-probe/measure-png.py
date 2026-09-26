#!/usr/bin/env python3
"""Decide whether a grabbed viewfinder PNG contains an image or nothing at all.

A camera frame of a dark room still carries sensor noise, so it has a non-zero
standard deviation. A frame that never received data is mathematically uniform.
That distinction is the whole point - it separates "the viewfinder is dark"
from "the viewfinder is dead", which look identical on a screen.

Measured on clover, same scene, either side of the vndk-sp-28 fix:

  before:  min=0 max=0   mean=0.00   stddev=0.00   non-zero=0.00%    10,843 bytes
  after:   min=0 max=255 mean=138.67 stddev=67.05  non-zero=96.48% 1,335,729 bytes

Usage: measure-png.py vf.png [more.png ...]     (pure stdlib, no Pillow needed)
"""
import struct
import sys
import zlib


def read_png(path):
    data = open(path, "rb").read()
    pos, idat, w, h, depth, colour = 8, b"", None, None, None, None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            w, h, depth, colour = struct.unpack(">IIBB", chunk[:10])
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + length

    raw = zlib.decompress(idat)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
    bpp = channels * depth // 8
    stride = w * bpp

    out, prev, pos = bytearray(), bytearray(stride), 0
    for _ in range(h):
        filt = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if filt == 1:
                line[x] = (line[x] + a) & 255
            elif filt == 2:
                line[x] = (line[x] + b) & 255
            elif filt == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif filt == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pred) & 255
        out += line
        prev = line
    return w, h, channels, bytes(out)


for path in sys.argv[1:]:
    w, h, channels, px = read_png(path)

    # Sample the centre, away from any letterboxing around the video rect.
    values = []
    for y in range(h // 4, 3 * h // 4, 3):
        for x in range(w // 8, 7 * w // 8, 3):
            o = (y * w + x) * channels
            values.append((px[o] + px[o + 1] + px[o + 2]) // 3)

    mean = sum(values) / len(values)
    stddev = (sum((v - mean) ** 2 for v in values) / len(values)) ** 0.5
    non_zero = sum(1 for v in values if v > 0)

    print("%s: %dx%d  min=%d max=%d mean=%.2f stddev=%.2f non-zero=%.2f%%"
          % (path, w, h, min(values), max(values), mean, stddev,
             100 * non_zero / len(values)))
    print("  verdict: %s" % ("NO DATA (uniform)" if stddev == 0 else "real image data"))
