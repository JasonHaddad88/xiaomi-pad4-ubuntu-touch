import os, re, struct, sys
S = sys.argv[1]
K = "/home/projkt88/cprh-port/linux/arch/arm64/boot/dts/qcom/"
P = open(S + "/hiby/p/" + [f for f in os.listdir(S + "/hiby/p") if f.startswith("0041")][0]).read()

def hunk_added(header_prefix):
    lines = P.splitlines(); out = []; on = False
    for l in lines:
        if l.startswith("@@"):
            on = l.startswith(header_prefix); continue
        if l.startswith("diff --git"): on = False
        if on and l.startswith("+"): out.append(l[1:])
    return out

soc_nodes = hunk_added("@@ -435,6 +766,142 @@")
tail = hunk_added("@@ -444,3 +911,321 @@")
hdr = """// SPDX-License-Identifier: BSD-3-Clause
/*
 * SDM660 CPU DVFS: CPRh voltage controllers, OSM (cpufreq-hw), L2 SAW AVS
 * ports, CPR fuse cells and CPRh virtual corners.
 *
 * Taken verbatim from the CPU-DVFS hunks of the HiBy RS6 series, patch 0041
 * (github.com/noas-slopware/linux-hiby-rs6, Noa Himesaka). The idle, GPU,
 * display and watchdog parts of that patch are deliberately left out.
 * Every value here was checked against clover's Android device tree and
 * vendor kernel: docs/nura-hiby-cprh-review.md.
 *
 * All nodes are disabled; a board enables them.
 */

&soc {"""
body = "\n".join(soc_nodes).strip("\n")
open(K + "sdm660-cprh-osm.dtsi", "w").write(hdr + "\n" + body + "\n};\n" + "\n".join(tail).rstrip() + "\n")
print("sdm660-cprh-osm.dtsi: %d SoC-node lines + %d fuse/corner lines" % (len(soc_nodes), len(tail)))

# ---------- per-bin CPU OPP tables from clover's Android OSM node ----------
osm = S + "/dsref/base/soc/qcom,clk-cpu-660@179c0000/"
def rows(name):
    d = open(osm + name, 'rb').read(); v = struct.unpack('>%dI' % (len(d)//4), d)
    return [v[i:i+5] for i in range(0, len(v), 5)]
def table(label, node, prop):
    t = ["\t%s: %s {" % (label, node), '\t\tcompatible = "operating-points-v2-qcom-osm";', "\t\topp-shared;", ""]
    for i, (hz, fd, ov, sp, vc) in enumerate(rows(prop)):
        assert vc == i + 1, "virtual corner %d at row %d" % (vc, i)
        t += ["\t\topp-%d {" % hz, "\t\t\topp-hz = /bits/ 64 <%d>;" % hz,
              "\t\t\trequired-opps = <&cprh_opp%d>;" % vc,
              "\t\t\tqcom,pll-override = <0x%x>;" % ov, "\t\t\tqcom,spare-data = <%d>;" % sp]
        pd = (fd >> 24) & 3
        if pd: t.append("\t\t\tqcom,pll-div = <%d>;" % pd)
        t += ["\t\t};", ""]
    t[-1] = "\t};"
    return t

for b in (0, 1, 3, 4):
    out = ["// SPDX-License-Identifier: BSD-3-Clause",
           "/*",
           " * Xiaomi Mi Pad 4 (clover): CPU DVFS for speed bin %d." % b,
           " * CPU OPP rows generated from clover's own Android OSM tables",
           " * qcom,{pwrcl,perfcl}-speedbin%d-v0: opp-hz = column 1, pll-override =" % b,
           " * column 3, spare-data = column 4, required CPRh corner = column 5,",
           " * pll-div = freq_data bits 25:24. Voltages are NOT here: the CPRh",
           " * driver computes them per chip from the fuses.",
           " *",
           " * cpu0-3 = cpu@100-103 = gold (perfcl, OSM domain 1, CPRh thread 1),",
           " * cpu4-7 = cpu@0-3 = silver (pwrcl, OSM domain 0, CPRh thread 0).",
           " * The CPUs have no PSCI power domain on this kernel, so the CPRh one",
           ' * is the only entry; the driver finds it by its "cpr" name.',
           " */", "", "/ {"]
    out += table("pwrcl_opp_table", "opp-table-pwrcl", "qcom,pwrcl-speedbin%d-v0" % b) + [""]
    out += table("perfcl_opp_table", "opp-table-perfcl", "qcom,perfcl-speedbin%d-v0" % b)
    out += ["};", ""]
    for cpu in range(8):
        dom = 1 if cpu < 4 else 0
        tbl = "perfcl_opp_table" if cpu < 4 else "pwrcl_opp_table"
        out += ["&cpu%d {" % cpu, "\toperating-points-v2 = <&%s>;" % tbl,
                "\tpower-domains = <&apc_cprh %d>;" % dom, '\tpower-domain-names = "cpr";',
                "\tqcom,freq-domain = <&cpufreq_hw %d>;" % dom, "};", ""]
    for n in ("apc_cprh", "cpufreq_hw", "saw_gold_l2", "saw_silver_l2"):
        out += ["&%s {" % n, '\tstatus = "okay";', "};", ""]
    open(K + "sda660-xiaomi-clover-cpufreq-bin%d.dtsi" % b, "w").write("\n".join(out).rstrip() + "\n")
    open(K + "sda660-xiaomi-clover-cpufreq-bin%d.dts" % b, "w").write(
        "// SPDX-License-Identifier: BSD-3-Clause\n/*\n * TEST ONLY: clover with CPU DVFS, speed bin %d.\n"
        " * Boot it with fastboot boot and the bring-up gates, never flash it untested.\n */\n\n"
        '#include "sda660-xiaomi-clover.dts"\n#include "sdm660-cprh-osm.dtsi"\n'
        '#include "sda660-xiaomi-clover-cpufreq-bin%d.dtsi"\n' % (b, b))
    print("bin %d: pwrcl %s / perfcl %s" % (b, [r[0]//100000/10 for r in rows("qcom,pwrcl-speedbin%d-v0" % b)][-1], [r[0]//100000/10 for r in rows("qcom,perfcl-speedbin%d-v0" % b)][-1]))
mk = K + "Makefile"
m = open(mk).read()
if "clover-cpufreq-bin0" not in m:
    m = m.replace("dtb-$(CONFIG_ARCH_QCOM)\t+= sda660-xiaomi-clover.dtb\n",
                  "dtb-$(CONFIG_ARCH_QCOM)\t+= sda660-xiaomi-clover.dtb\n" +
                  "".join("dtb-$(CONFIG_ARCH_QCOM)\t+= sda660-xiaomi-clover-cpufreq-bin%d.dtb\n" % b for b in (0, 1, 3, 4)))
    open(mk, "w").write(m)
print("Makefile entries:", m.count("clover-cpufreq-bin"))
