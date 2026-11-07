# Charge limit and bypass for clover (REVERTED 2026-11-07, kept as a record)

**Not installed.** Removed at the owner's request the same day: `nura-charge.service`, `/usr/local/bin/nura-charge` and `/etc/nura-charge.conf` deleted, and the kernel reinstalled as **r101** (boot.img `1389864848923ecbf36518767c20f795`, byte-identical to before; stock `qcom_smbx`, no `charge_behaviour`). `/boot/boot.img.r103` was kept on the tablet.

Why it was paused: the fuel gauge (`pmi8998_fg`, no battery profile loaded on mainline) overstates the charge while charging. The limit stopped at a displayed 80 %, but on unplug the gauge corrected from 78 % to 65 % within 40 s (3.90 V at rest is about 55-60 % for this 4.4 V cell). A real limit needs either a resting-voltage criterion (about 4.14 V for 80 %) or the battery profile from Android's `qcom,zql5018_battery_6000mah` (224-byte `qcom,fg-profile-data`) loaded into the gauge.

## Pieces

- **Kernel:** `0001-power-supply-qcom_smbx-add-charge_behaviour-auto-inh.patch` adds
  the standard `charge_behaviour` property (`auto`, `inhibit-charge`) to the
  PM660 charger driver. It drives `CHARGING_ENABLE_CMD` (0x42), the software
  charge-enable bit: with it cleared, USB keeps supplying the system through
  the power path and the battery is neither charged nor (unless the load
  exceeds the input limit) discharged.
  Shipped in kernel package **r103** = r101 + this patch
  (apk `0113a2854a37606b15ae312804ecea16`; config and DTB identical to r101;
  boot.img `de1f790770636cc12891939d0568ccbb`).
- **`nura-charge`** (`/usr/local/bin`): `status`, `limit [N [R]]`, `bypass`,
  `full`, `apply`. Config in `/etc/nura-charge.conf` (default
  `MODE=limit LIMIT=80 RESUME=75`). Bypass still charges below 20 % (until 25 %).
- **`nura-charge.service`**: runs `nura-charge apply` every 30 s; on stop it
  sets `auto` again.

## Measured (2026-11-07, laptop USB, 500 mA SDP)

| state | charger | USB in | battery current |
|---|---|---|---|
| auto | Charging | 469 mA @ 4.86 V | +455 mA |
| inhibit-charge | Not charging | (meter reads 0 while charging is off) | **+4 mA** |
| auto again | Charging | 469 mA | +460 mA |

The tablet kept running throughout, so it was supplied from USB.

## Lessons

- **Do not hot-reload `qcom_smbx`.** `rmmod` warns in
  `power_supply_unregister`, and the next `systemctl daemon-reload` then hung
  PID 1 for 3 minutes, making the whole UI crawl until a reboot.
- The charger driver loads from the **initramfs**
  (`00-device-xiaomi-clover.modules`), so an `updates/` copy on the rootfs is
  ignored. It has to ship in the kernel package.

## Undo

- `sudo systemctl disable --now nura-charge` (charging goes back to `auto`).
- Kernel rollback: `/boot/boot.img.r101` and
  `sda660-xiaomi-clover.dtb.r101` on the tablet, or
  `apk add --allow-untrusted linux-postmarketos-qcom-sdm660-7.0.14-r101.apk`
  (kept in `~/osm-diag/kept/`).

## Open: plugging in while asleep does not wake the tablet

The "usb-plugin" IRQ fired 9 times in one boot, but the charger's wakeup
source shows `wakeup_count 0`: plugging into a wall charger while suspended
does not wake the system, so the driver never configures the input for it.
Workaround: wake the tablet (Power) after plugging in.
