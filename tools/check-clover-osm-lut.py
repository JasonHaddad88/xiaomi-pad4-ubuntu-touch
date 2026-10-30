import re, struct, sys
S = sys.argv[1]
K = "/home/projkt88/cprh-port/linux/arch/arm64/boot/dts/qcom/"
osm = S + "/dsref/base/soc/qcom,clk-cpu-660@179c0000/"
def android(prop):
    d = open(osm + prop, 'rb').read(); v = struct.unpack('>%dI' % (len(d)//4), d)
    return [v[i:i+5] for i in range(0, len(v), 5)]
def parse(dtsi, label):
    blk = dtsi.split(label + ":")[1].split("\n\t};")[0]
    out = []
    for node in re.findall(r"opp-\d+ \{(.*?)\n\t\t\};", blk, re.S):
        g = lambda k, d=None: (int(re.search(k + r" = <(?:/bits/ 64 )?([0-9a-fx]+)>", node).group(1), 0) if re.search(k + r" = ", node) else d)
        out.append(dict(hz=int(re.search(r"opp-hz = /bits/ 64 <(\d+)>", node).group(1)), ov=g("qcom,pll-override"), sp=g("qcom,spare-data"), div=g("qcom,pll-div", 0)))
    return out
XO, CORES = 19200000, 4
total = bad = 0
for b in (0, 1, 3, 4):
    dt = open(K + "sda660-xiaomi-clover-cpufreq-bin%d.dtsi" % b).read()
    for cl in ("pwrcl", "perfcl"):
        ours, ref = parse(dt, cl + "_opp_table"), android("qcom,%s-speedbin%d-v0" % (cl, b))
        assert len(ours) == len(ref)
        for i, (o, r) in enumerate(zip(ours, ref)):
            # HiBy qcom-cpufreq-hw: f_src = i ? 1 : 0, shifted to LUT_SRC_8998 (bits 27:26)
            freq_word = ((1 if i else 0) << 26) | (o["hz"] // XO) | (CORES << 16) | (o["div"] << 24)
            ok = (freq_word == r[1] and o["ov"] == r[2] and o["sp"] == r[3])
            total += 1; bad += (not ok)
            if not ok:
                print("MISMATCH bin%d %s row%d: ours freq=0x%08x ov=0x%x sp=%d | android freq=0x%08x ov=0x%x sp=%d" % (b, cl, i, freq_word, o["ov"], o["sp"], r[1], r[2], r[3]))
print("%d of %d LUT rows: the driver's FREQ / OVERRIDE / SPARE words equal clover's Android words exactly" % (total - bad, total))
