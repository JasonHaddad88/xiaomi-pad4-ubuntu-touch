# Charge limit and bypass for clover (installed 2026-11-07)

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
