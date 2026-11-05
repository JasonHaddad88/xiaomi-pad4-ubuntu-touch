#!/usr/bin/env python3
"""Compare two DTBs with phandle numbers resolved to node paths.

Usage:
    dtb-semantic-diff.py <a.dtb> <b.dtb>

Two DTBs built differently (a source build versus a hand-edited decompile)
number their phandles differently, so a plain `dtc -O dts | diff` is all
noise. This flattens each tree to `path:property = value` and rewrites
phandle-carrying properties as `&{/target/path} args...`, using the
target's `#<x>-cells` to know how many argument cells follow each phandle.
It then prints only the real differences.

`phandle`, `linux,phandle` and the `__symbols__` / `__fixups__` /
`__local_fixups__` nodes are ignored. Properties not listed below are
compared raw, so a phandle in an unlisted property shows up as a (false)
difference rather than being hidden.

Needs `dtc` on PATH.
"""
import re
import subprocess
import sys

# property -> name of the #cells property in the target; None = no args
SPEC = {
    'clocks': '#clock-cells', 'assigned-clocks': '#clock-cells',
    'assigned-clock-parents': '#clock-cells',
    'power-domains': '#power-domain-cells',
    'interrupts-extended': '#interrupt-cells',
    'resets': '#reset-cells', 'phys': '#phy-cells',
    'iommus': '#iommu-cells', 'mboxes': '#mbox-cells',
    'interconnects': '#interconnect-cells',
    'thermal-sensors': '#thermal-sensor-cells',
    'sound-dai': '#sound-dai-cells', 'dmas': '#dma-cells',
    'io-channels': '#io-channel-cells', 'hwlocks': '#hwlock-cells',
    'qcom,smem-states': '#qcom,smem-state-cells',
    'cooling-device': '#cooling-cells',
    'interrupt-parent': None, 'cpu-idle-states': None,
    'domain-idle-states': None, 'operating-points-v2': None,
    'required-opps': None, 'next-level-cache': None,
    'memory-region': None, 'remote-endpoint': None, 'trip': None,
    'nvmem-cells': None, 'qcom,rpm-msg-ram': None, 'wakeup-parent': None,
    'qcom,freq-domain': 1, 'gpio-ranges': 3, 'qcom,tcsr-reg': 1,
    'qcom,halt-regs': 3, 'backlight': None, 'monitored-battery': None,
    'power-supplies': None,
}
SKIP_NODES = ('/__symbols__', '/__fixups__', '/__local_fixups__')


def spec_for(key):
    if key in SPEC:
        return SPEC[key]
    if key.endswith('-supply') or re.match(r'pinctrl-\d+$', key):
        return None
    if key.endswith('-gpios') or key == 'gpios':
        return '#gpio-cells'
    return 'raw'


def flatten(path):
    dts = subprocess.run(['dtc', '-I', 'dtb', '-O', 'dts', path],
                         capture_output=True, text=True, check=True).stdout
    props, phandles, stack = {}, {}, []
    for raw in dts.splitlines():
        line = raw.strip()
        if not line or line.startswith(('/dts-v1/', '//')):
            continue
        m = re.match(r'^(?:[\w,.-]+:\s*)?([\w,.@+-]+|/)\s*\{$', line)
        if m:
            name = m.group(1)
            parent = stack[-1] if stack else ''
            stack.append('/' if name == '/' else parent.rstrip('/') + '/' + name)
            continue
        if line == '};':
            stack.pop()
            continue
        m = re.match(r'^([\w,.#+?@-]+)\s*(?:=\s*(.*))?;$', line)
        if not m or not stack:
            continue
        key, val = m.group(1), (m.group(2) or '')
        if key in ('phandle', 'linux,phandle'):
            phandles[int(val.strip('<>'), 16)] = stack[-1]
            continue
        props[(stack[-1], key)] = val
    return props, phandles


def cells(val):
    return [int(c, 16) for g in re.findall(r'<([^>]*)>', val) for c in g.split()]


def resolve(props, phandles):
    out = {}
    for (path, key), val in props.items():
        if path.startswith(SKIP_NODES):
            continue
        sp = spec_for(key)
        if sp == 'raw' or '<' not in val:
            out[(path, key)] = val
            continue
        cs, res, i = cells(val), [], 0
        try:
            while i < len(cs):
                if cs[i] == 0:
                    res.append('<null>')
                    i += 1
                    continue
                tgt = phandles[cs[i]]
                if sp is None:
                    n = 0
                elif isinstance(sp, int):
                    n = sp
                else:
                    n = cells(props.get((tgt, sp), '<0x0>'))[0]
                res.append('&{%s}%s' % (tgt, ''.join(' 0x%x' % c for c in cs[i + 1:i + 1 + n])))
                i += 1 + n
            out[(path, key)] = ', '.join(res)
        except (KeyError, IndexError):
            out[(path, key)] = 'UNRESOLVED ' + val
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    a = resolve(*flatten(sys.argv[1]))
    b = resolve(*flatten(sys.argv[2]))
    n = 0
    for k in sorted(set(a) | set(b)):
        if a.get(k) != b.get(k):
            n += 1
            print('%s : %s' % k)
            print('   a: %s' % a.get(k, '(absent)'))
            print('   b: %s' % b.get(k, '(absent)'))
    print('%d difference(s)' % n)


if __name__ == '__main__':
    main()
