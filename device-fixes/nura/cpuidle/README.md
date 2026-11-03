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
