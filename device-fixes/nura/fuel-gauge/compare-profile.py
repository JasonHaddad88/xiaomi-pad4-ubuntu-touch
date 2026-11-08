import re, sys
F = sys.argv[1]
words = {}
for l in open(F + '/sram-dump.txt'):
    m = re.match(r'word\s+(\d+): ((?:[0-9a-f]{2} ?){4})', l)
    if m:
        words[int(m.group(1))] = bytes.fromhex(m.group(2).replace(' ', ''))
sram = b''.join(words[w] for w in range(24, 80))
integ = words[79][3]
print('profile area (words 24-79): %d bytes' % len(sram))
print('integrity byte (word 79, byte 3): 0x%02x -> loaded bit %d, flags %s' % (integ, integ & 1,
      {0: 'none', 2: 'bootloader load', 6: 'bootloader load+restart', 8: 'HLOS restart'}.get(integ & ~1, 'garbage 0x%02x' % (integ & ~1))))
for name in ('zql5018', 'zql6019'):
    p = open('%s/%s-profile.bin' % (F, name), 'rb').read()
    same148 = sram[:148] == p[:148]
    diff = [i for i in range(148) if sram[i] != p[i]]
    print('%s: first 148 bytes %s; %d of 148 differ; first diffs at %s' % (name, 'MATCH' if same148 else 'differ', len(diff), diff[:12]))
nom = words[58][0] | words[58][1] << 8
print('NOM_CAP (word 58): %d mAh' % nom)
print('words 24-27 sram:', sram[:16].hex(' '))
print('zql5018 first 16:', open(F + '/zql5018-profile.bin', 'rb').read()[:16].hex(' '))
