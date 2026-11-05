import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()

# 1. cluster states become genpd domain idle states
n = 0
def fix_cluster(m):
    global n; n += 1
    return m.group(0).replace('compatible = "arm,idle-state";', 'compatible = "domain-idle-state";')
s = re.sub(r'cluster-sleep-[01]-[0-2] \{[^}]*\}', fix_cluster, s)
assert n == 6, n

# 2. CPU nodes: core states only, PSCI domain first, CPRh domain by name
cpus = re.search(r'\n\tcpus \{.*?\n\t\};', s, re.S)
block = cpus.group(0)
clusters = {}
def fix_cpu(m):
    node, body = m.group(1), m.group(2)
    st = re.search(r'cpu-idle-states = <([^>]+)>;', body).group(1).split()
    assert len(st) == 5, (node, st)
    cl = 'PERF' if st[0] == '0x04' else 'PWR'
    clusters.setdefault(cl, (st[2], st[3], st[4]))
    lab = 'CPU_PD_%s' % node.replace('@', '_')
    body = body.replace('cpu-idle-states = <%s>;' % ' '.join(st), 'cpu-idle-states = <%s %s>;' % (st[0], st[1]))
    body, k = re.subn(r'power-domains = <(0x0b 0x0[01])>;\n(\s*)power-domain-names = "cpr";',
                      r'power-domains = <&%s>, <\1>;\n\2power-domain-names = "psci", "cpr";' % lab, body)
    assert k == 1, node
    fix_cpu.nodes.append((lab, cl))
    return '\n\t\t%s {%s' % (node, body)
fix_cpu.nodes = []
block2 = re.sub(r'\n\t\t(cpu@[0-9a-f]+) \{(.*?\n\t\t\};)', fix_cpu, block, flags=re.S)
assert len(fix_cpu.nodes) == 8, fix_cpu.nodes
s = s.replace(block, block2)

# 3. PSCI power-domain topology
pd = ''
for lab, cl in fix_cpu.nodes:
    pd += '\n\t\t%s: power-domain-%s {\n\t\t\t#power-domain-cells = <0x00>;\n\t\t\tpower-domains = <&CLUSTER_PD_%s>;\n\t\t};\n' % (lab, lab.lower().replace('_', '-'), cl)
for cl, st in sorted(clusters.items()):
    pd += '\n\t\tCLUSTER_PD_%s: power-domain-cluster-%s {\n\t\t\t#power-domain-cells = <0x00>;\n\t\t\tdomain-idle-states = <%s>;\n\t\t};\n' % (cl, cl.lower(), ' '.join(st))
old = '\tpsci {\n\t\tcompatible = "arm,psci-1.0";\n\t\tmethod = "smc";\n\t};'
assert old in s
s = s.replace(old, '\tpsci {\n\t\tcompatible = "arm,psci-1.0";\n\t\tmethod = "smc";\n%s\t};' % pd)
open(dst, 'w').write(s)
print("clusters:", clusters)
