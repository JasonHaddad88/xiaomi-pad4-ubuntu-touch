# Wi-Fi firmware crash on every disconnect (fixed 2026-11-12)

## Symptom

Every time the tablet left a Wi-Fi network, the WCN3990 firmware crashed:

```
qcom-q6v5-mss 4080000.remoteproc: fatal error received: err_qdi.c:459:EX:wlan_process:1:WLAN RT:2158:PC=b00c7410
ath10k_snoc 18800000.wifi: firmware crashed! (guid ...)
```

- It happened on switching networks, suspend, reboot and shutdown, on WEP and
  WPA networks alike.
- The firmware restarted by itself, but for up to three minutes afterwards the
  tablet could not join a network ("The device could not be readied for
  configuration").
- It is not a regression from the Nura kernels. The oldest boots in the
  journal (kernel `#3`, built 2026-10-21, before the DVFS work) crash the same
  way.

## Cause

A WMI trace (`ath10k_core.debug_mask=0x112`) around one disconnect:

```
wmi tlv peer delete                      <- mac80211 removes the AP station first
wmi tlv peer delete response
wmi tlv vdev down
wmi tlv vdev 0 set param 45 value 0x0    <- TXBF, on a vdev that is down with no BSS peer
qcom-q6v5-mss: fatal error received: ... EX:wlan_process ... PC=b00c7410
```

`ath10k_bss_disassoc()` sends vdev down and then calls
`ath10k_mac_vif_recalc_txbf()`. The firmware takes an exception on that
parameter. The commands logged after it (`pdev set param 3`, the TX power)
never reach the firmware: they wait three seconds for a WMI credit and fail
with `-108`, which is where the old "failed to set 2g txpower" lines came from.

Qualcomm's own ath10k tree has the same fix: "ath10k: Fix STA disconnect
issue" (CRs-Fixed 2000365) skips the TXBF recalculation on WCN3990.

## Fix

`0032-wifi-ath10k-do-not-set-the-TXBF-vdev-param-after-vde.patch`: skip
`ath10k_mac_vif_recalc_txbf()` in `ath10k_bss_disassoc()` when the chip is
WCN3990. The parameter is set again on the next association.

Applies on top of the 31 patches of `../kernel-r101/` (kernel branch
`r101wifi`).

## How it is installed

Only the `ath10k_core` module was replaced. The kernel is still r101.

| File on the tablet | md5 |
|---|---|
| `/usr/lib/modules/7.0.14-sdm660/updates/ath10k_core.ko.zst` (fixed, from test package r106) | `878c846265786fe1271734685b3cf45a` |
| `/usr/lib/modules/7.0.14-sdm660/kernel/drivers/net/wireless/ath/ath10k/ath10k_core.ko.zst` (stock r101, untouched) | `23b3bb0d163f2398e2907d4d2a8fb045` |

A module in `updates/` overrides the stock one after `depmod -a`. `ath10k` is
not in the initramfs, so the override is the copy that loads.

Both modules are kept locally in `backups/wifi-2026-11-12/` (not in git). The
test package is `~/osm-diag/kept/linux-postmarketos-qcom-sdm660-7.0.14-r106.apk`
(md5 `7547e3747d0ceb0fff9ae2a13f5e63ca`) in WSL.

**To undo:**

```sh
sudo rm /usr/lib/modules/7.0.14-sdm660/updates/ath10k_core.ko.zst
sudo depmod -a
sudo reboot
```

**When the next kernel package is built,** include patch 0032 and delete the
override, so the two cannot drift apart.

## Result (2026-11-12, home WEP network)

| Test | Before | After |
|---|---|---|
| Disconnect, then reconnect | firmware crash; reconnect after minutes | no crash; reconnect in about 1 s (3 of 3) |
| 33 s suspend and resume | firmware crash | no crash; Wi-Fi back by itself |
| `firmware crashed` lines in the boot | one per disconnect | 0 |

The trace after the fix shows the whole teardown completing: vdev down, vdev
stop, `WMI_VDEV_STOPPED_EVENTID`, vdev delete with its response, vdev create.
The WEP default-key parameter (`set param 33`) sent after the stop does not
crash the firmware.

During the test the module was installed with a safety net: a timer that
removed the override and rebooted if Wi-Fi was not connected five minutes after
boot. It was removed once the fix was verified.

## Not covered

- `Blink0D833C` (the WEP router at the other location) accepts authentication
  and then ignores the association request. That is a different failure and
  can only be tested there.
