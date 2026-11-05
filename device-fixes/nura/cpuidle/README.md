# Idle-state fix: stop clover's cores spinning on rejected PSCI requests

Installed 2026-11-03 as `/usr/local/sbin/nura-cpuidle-fix` plus
`/etc/systemd/system/nura-cpuidle-fix.service` (enabled). Both are new files;
nothing was replaced.

## Symptom

Overnight, the battery went from full to empty while the tablet was suspended:
about 98 % of 23 Wh in 15.4 h of s2idle, roughly **1.4 W**. Awake with the
screen off it drew about 0.94 W, so suspend saved nothing. Resuming flooded the
log with `watchdog: CPU4: Watchdog detected hard LOCKUP on cpu 5` (42 lines,
CPU 5 inside `cpuidle_enter_s2idle`).

## Cause

`sdm630.dtsi` gives each core five PSCI idle states: core retention
(`cpu-sleep-N-0`, param `0x40000002`), core power collapse (`cpu-sleep-N-1`,
`0x40000003`), and three cluster states (`0x400000f2/f3/f4`). The firmware
refuses the retention and cluster states. Boot shows
`psci: [Firmware Bug]: failed to set PC mode: -3`, and after 4 minutes of
uptime the per-state `rejected` counters read:

| state | usage | rejected |
|---|---|---|
| cpu-sleep-0-0 (retention) | 0 | 20 804 |
| cpu-sleep-0-1 (power collapse) | 6 667 | 791 |
| cluster-sleep (f2) | 0 | 705 |
| cluster-sleep (f4) | 0 | **5 161 921** |

A rejected entry returns at once and cpuidle picks the same state again, so
idle cores spin issuing PSCI calls. s2idle always asks for the deepest state,
which is why suspend drew more than awake idle. The RPM sleep counters
(`/sys/kernel/debug/qcom_stats/vlow`, `vmin`) stayed at 0: the SoC never
reached system sleep.

## Fix and measurement

Disable the refused states by name at boot. WFI and core power collapse stay
enabled. Measured live while charging (screen on, brightness 160, 30 s each):

| | charger in | into battery | system + losses | PSCI rejections |
|---|---|---|---|---|
| before | 6 887 mW | 5 312 mW | 1 574 mW | 3 157 114 |
| after | 6 869 mW | 5 736 mW | **1 133 mW** | 83 |

After a reboot the service is active and all refused states are disabled. In a
60 s `rtcwake -m freeze` test, suspend and resume were clean, with no lockup
warnings.

## Undo

```sh
sudo systemctl disable --now nura-cpuidle-fix.service   # ExecStop re-enables the states
sudo rm /usr/local/sbin/nura-cpuidle-fix /etc/systemd/system/nura-cpuidle-fix.service
```

## The proper fix (not done)

Make the deep states work instead of disabling them. The firmware advertises
OSI mode, so the likely route is the hierarchical PSCI description
(`power-domains` per CPU and cluster with `domain-idle-states`) instead of the
flattened composite parameters. That is device-tree work, to be tested by RAM
boot like docs/nura-gpu-speedbin.md. It would allow cluster sleep and possibly
the RPM's `vlow`/`vmin` system sleep.

## Correct PSCI parameters, found 2026-11-04 (RAM tests T21, T22)

Clover's Android tree (`qcom,lpm-levels`) gives the firmware's encoding:
CPU mode in bits 0-3, L2 mode in bits 4-7, system mode in bits 8-11,
affinity level in bits 24-25, and the power-down bit 30 **only** on reset
(power-collapse) levels. Mainline `sdm630.dtsi` gets two things wrong:

| state | mainline | Android-derived |
|---|---|---|
| core retention | `0x40000002` (power-down bit set) | `0x00000002` |
| L2 dynamic retention / retention / power collapse | `0x400000f2/f3/f4` | `0x41000023/33/43` |

**T21** (`TEST-psci-idle-r100.img`, flattened PC-style states, corrected
values): core retention ran 539 times with 0 rejections. L2 dynamic retention
was entered 272 times but rejected 1.76 million times, with power up to
970 mW. The firmware only accepts a cluster request from the *last* core of
the cluster: OS-initiated (OSI) semantics.

**T22** (`TEST-psci-osi-r100.img`, md5 `f847b151586ee455e2123883cd141c37`,
in `backups/psci-idle-2026-11-03/`): a hierarchical PSCI topology. There is
one `power-domain-cpu-*` per core, under `power-domain-cluster-perf` /
`-pwr` holding the three L2 states as `domain-idle-state`. CPUs keep only
their two core states, and `power-domains = <&CPU_PD>, <&apc_cprh N>` with
names `"psci", "cpr"`. The CPRh driver looks up `"cpr"` by name for exactly
this case (`qcom_cpr_cpu_pd_index()`). Result:

- `CPUidle PSCI: Initialized CPU PM domain topology using OSI mode`; DVFS and
  CPRh unaffected (1843 / 2208 MHz)
- after about 5 min, each cluster had spent 340-350 s in L2 retention, and core
  power-collapse rejections were rare
- settled screen-off draw while charging: 567-589 mW, against about 620 mW with
  the installed workaround (modest: the CPUs were no longer the main consumer)
- a real 60 s suspend: both clusters entered L2 power collapse (perf +3, pwr +4)
- RPM `vlow`/`vmin` still 0: the SoC still never reaches XO shutdown, so
  something outside the CPUs keeps it up (candidates: `mdss_ahb_clk` stuck
  on at suspend, remote-processor votes)

Not installed yet; it is waiting for an unplugged overnight run on T22.

## Installed 2026-11-05

T22 then ran for 25 h, including **21 h of continuous suspend** (23:24 ->
20:35) that cost about 32 % (99 -> 67 %), roughly **0.35 W**, against 1.4 W on
2026-11-02/03. That is about 65 h of standby on a full charge.

The OSI DTB is now installed: see [osi-dtb/](osi-dtb/). After a normal boot:
`Initialized CPU PM domain topology using OSI mode`, retention on with 0
rejections, both clusters in L2 retention, DVFS at 1843 / 2208 MHz, Wi-Fi up,
no failed units.

`nura-cpuidle-fix` v2 (md5 `16dae4085ebf79a0e05890d7f9f86f2c`) stays enabled as
a guard. It disables `cpu-sleep-N-0` only when the DT parameter has the
power-down bit, and any flattened `cluster-sleep-*`, so it does nothing under
the OSI DTB and protects the stock one. v1 is kept on the tablet as
`/usr/local/sbin/nura-cpuidle-fix.v1`.

**Still open:** RPM `vlow`/`vmin` stay at 0, so the SoC never reaches XO
shutdown. Something outside the CPUs keeps it up.
