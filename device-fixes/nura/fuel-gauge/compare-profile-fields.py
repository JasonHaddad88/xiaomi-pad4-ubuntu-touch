import re, sys
F = sys.argv[1]
words = {}
for l in open(F + '/sram-dump.txt'):
    m = re.match(r'word\s+(\d+): ((?:[0-9a-f]{2} ?){4})', l)
    if m: words[int(m.group(1))] = bytes.fromhex(m.group(2).replace(' ', ''))
sram = b''.join(words[w] for w in range(24, 80))
o = (58 - 24) * 4
for name in ('sram', 'zql5018', 'zql6019'):
    p = sram if name == 'sram' else open('%s/%s-profile.bin' % (F, name), 'rb').read()
    print('%-8s nomcap@word58 = %d mAh   bytes 136..147: %s' % (name, p[o] | p[o+1] << 8, p[o:o+12].hex(' ')))
for name in ('zql5018', 'zql6019'):
    p = open('%s/%s-profile.bin' % (F, name), 'rb').read()
    # 16-bit little-endian words: mean relative difference over the 148-byte compare region
    d = [abs((sram[i] | sram[i+1] << 8) - (p[i] | p[i+1] << 8)) for i in range(0, 148, 2)]
    print(name, 'median |diff| of 16-bit fields:', sorted(d)[len(d)//2], ' identical fields:', d.count(0), '/', len(d))
print('words 80-95 (after profile):')
for w in range(80, 96): print(' ', w, words[w].hex(' '))
