# Power draw and suspend on clover (2026-11-03)

Report: unplugged at about 06:52 with a full battery, the tablet was empty by
evening without being used.

## What the logs showed

- **Charging was fine.** upower shows 31 % -> 99 % from 22:53 to 00:46.
- **Awake, screen off: about 0.94 W** (upower rate, 06:53-07:08).
- **Suspend (s2idle) from 07:08 to 22:33: about 1.4 W**, roughly 98 % of
  23 Wh in 15.4 h. Suspend saved nothing.
- Waking up produced 42 lines of `watchdog: CPU4: Watchdog detected hard
  LOCKUP on cpu 5`, with CPU 5 inside `cpuidle_enter_s2idle`.

## Cause: idle cores spinning on rejected PSCI requests (fixed)

The firmware refuses the core-retention and cluster idle states that the DT
offers, so idle cores loop on rejected PSCI calls: about 3 million every 30 s,
and s2idle always picks the deepest (rejected) one. Details, measurements and
undo are in [device-fixes/nura/cpuidle/README.md](../device-fixes/nura/cpuidle/README.md).

**Installed** as `nura-cpuidle-fix.service` and verified across a reboot:

- system draw fell from 1 574 to 1 133 mW (screen on, measured while charging)
- in a 91 s suspend every core spent 90+ s in core power collapse, waking
  about 30 times a second (`arch_mem_timer` and IPIs)
- no lockup warnings after either the `rtcwake` suspend or a real logind
  suspend

**Still to measure:** a full unplugged night. The RPM system-sleep counters
(`qcom_stats` `vlow`/`vmin`) stay at 0, so the SoC still never reaches XO
shutdown. The deeper fix is a hierarchical PSCI (OSI) device tree.

## Wi-Fi firmware crashes on every disconnect (FIXED 2026-11-12)

**Fixed** by a one-line ath10k change (the driver set the TXBF vdev parameter
after vdev down), installed as a module override. See
`device-fixes/nura/wifi-disconnect-crash/README.md`. The journal also showed
that the crash predates 2026-10-31: the oldest kernel in it (`#3`, built
2026-10-21) crashes the same way. The notes below are the record from before
the fix.

Since 2026-10-31, every disconnect crashes the WCN3990 firmware, which runs
on the modem DSP (`qcom-q6v5-mss: fatal error received:
err_qdi.c:459:EX:wlan_process`, always `PC=b00c7410`). That covers suspend,
reboot, shutdown and switching networks, on WEP (Blink7183AD) and on WPA-PSK
(Layers Caffee, the HONOR hotspot) alike. The crash is logged about 3 s
before wpa_supplicant's `CTRL-EVENT-DISCONNECTED`, so pairing the two events
naively hides it. The only earlier disconnect in the journal (Aroma Mio,
Oct 30) did not crash.

Recovery:

- **Real suspend (logind, as used overnight):** the firmware restarts while the
  system goes to sleep, and Wi-Fi was back on Blink **4 s after resume** with
  no help (tested 2026-11-03 23:19).
- **`rtcwake -m freeze`** bypasses NetworkManager. The disconnect then happens
  inside the kernel's suspend path, the restart fails with WMI timeouts, and
  Wi-Fi stays dead until reboot. Don't test suspend that way over Wi-Fi.

`board-2.bin` is intact: md5 `5b87ec6e67c8046b56665c1d1c5bfe0e`. It is shipped
by the official `firmware-xiaomi-clover-2-r1`, and `apk audit` reports no
modification.

## Smaller items

- `mdss_ahb_clk status stuck at 'on'` (WARNING in `clk_branch_toggle`) at
  suspend entry: the display AHB clock doesn't switch off. It may cost some
  suspend power. Kernel-level, not investigated yet.
- `msm-modem-uim-selection.service` waited 47 s at every boot for a modem SIM
  this Wi-Fi tablet doesn't have, then failed. **Masked** on 2026-11-03; undo
  with `sudo systemctl unmask msm-modem-uim-selection.service`.
- `gnome-software` keeps a background service decoding icons (20-40 % of a
  core). The owner chose to leave it.
- The `phosh-osk-stevia` start failures happen only during the low-battery
  shutdown. Harmless.
