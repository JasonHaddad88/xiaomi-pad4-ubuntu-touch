# USB gadget blocks suspend after unplugging from a PC

Installed 2026-11-04 as `/usr/lib/systemd/system-sleep/nura-usb-gadget-sleep`
(mode 0755, md5 `c9694500abab62a693471e3f40d12bee`). New file; the directory
was empty before.

## Symptom

Unplugged at 06:58 after charging from a PC. gsd-power requested suspend at
07:13 and again at 07:30, and both failed within seconds:

```
dwc3 a800000.usb: failed to enable ep0out
dwc3 a800000.usb: PM: dpm_run_callback(): platform_pm_suspend returns -11
dwc3 a800000.usb: PM: failed to suspend: error -11
PM: Some devices failed to suspend, or early wake event detected
```

gsd-power does not retry, so the tablet stayed awake with the screen off for
11 hours and lost 28 % (about 0.58 W).

## Cause

The configfs gadget `g1` (postmarketOS USB networking) stays bound to the
dwc3 controller after the cable is pulled. The controller reports
`not attached`, but the gadget is still bound, and dwc3's suspend fails trying
to soft-disconnect it.

## Fix

The hook runs before suspend. If `pm660-charger/online` is 0 it writes `""`
to each bound gadget's `UDC`, and after resume it writes the controller name
back. With a cable in, it does nothing.

Verified unplugged, both suspends with a real `systemctl suspend` and a 60 s
RTC wake:

| | result |
|---|---|
| without the hook | `success 1->1 fail 0->2`, `failed to suspend: error -11` |
| with the hook | `success 1->2 fail 2->2`, `unbound g1` ... `rebound g1`, Wi-Fi back |

After the rebind with no cable, dwc3 logs `failed to enable ep0out` once. It
does not block anything. Still to check: USB networking with a PC after the
next plug-in.

## Undo

`sudo rm /usr/lib/systemd/system-sleep/nura-usb-gadget-sleep`
