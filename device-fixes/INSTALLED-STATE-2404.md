# Installed state — clover on Ubuntu Touch 24.04 (noble)

Captured 2026-09-20, straight after the upgrade from 16.04. **Owner's first inspection: everything
works except rotation.**

| | |
|---|---|
| OS | Ubuntu **24.04.4 LTS** (noble), `24.04-1.x/arm64/android9plus/stable` |
| kernel | `4.4.153-HandsomeKernel+` (ours, unchanged) |
| init | **systemd** (16.04 was upstart — all the old upstart jobs are obsolete) |
| boot / android | our Halium 9 `halium-boot` + `android-rootfs.img`, unchanged |
| vendor partition | unchanged, so the `mixer_paths.xml` audio fix still applies |

## Access (changed from 16.04 — the old `ssh phablet@10.15.19.82` is gone)

| route | detail |
|---|---|
| **adb** | `adb devices` → `891bc6d1`. Needs Developer Mode on; authorise the prompt on the tablet once |
| **ssh over Wi-Fi** | `ssh phablet@192.168.1.64` — **key and password both verified working** |
| ssh key | `/root/.ssh/id_ed25519` in WSL; public key lives in the **persistent** home `/userdata/user-data/phablet/.ssh`, so it survives rootfs swaps |
| USB RNDIS | 24.04 uses gadget `VID_1209&PID_0004`; Windows shows **Code 28** until the "Remote NDIS Compatible Device" driver is bound. Not needed while Wi-Fi works |

Careful: `usb0` still holds `10.15.19.82` but is **DOWN**; Wi-Fi `wlan0` is the live route.

## Our fixes installed in this rootfs (md5 verified on device)

| md5 | path | repo copy |
|---|---|---|
| `0eac56170fb5fe136895ea5b84a13dff` | `/etc/deviceinfo/devices/clover.yaml` | `device-fixes/clover-2404.yaml` |
| `b47a0d9fd526f0902b43904dd60a1223` | `/usr/share/repowerd/device-configs/config-clover.xml` | `device-fixes/config-clover.xml` |
| symlink | `/persist -> /mnt/vendor/persist` | — |
| `PasswordAuthentication=yes` | `/etc/ssh/sshd_config.d/50-lxc-android-config.conf` | 24.04 ships `no`; changed so password auth still works |

Also enabled: `ssh.service`, `usb-tethering.service` (both `active`).

## Confirmed on 24.04

- `repowerd` **active** — screen control works, which on 16.04 required keeping Android's
  `sensorservice` alive.
- Android `sensorservice`: **0 processes**. Exactly as intended — 24.04's repowerd does not link
  platform-api, so nothing needs it, and the single-poller sensors HAL is free.
- `sensorfwd.service` **enabled and running** (note the unit is `sensorfwd`, *not* `sensorfw` as on
  16.04 — querying the old name reports "could not be found" and looks like a fault when it isn't).
  Running as `/usr/sbin/sensorfwd --systemd --device-info --log-level=warning`.
- sensorfw config now comes from `/etc/sensorfw/sensord.conf.d/30-hidl.conf` (new `hidl*adaptor`
  plugins) — which is why `clover.yaml` here must **not** set `SensorfwConfig`.

## Rollback to 16.04 (two renames)

`/userdata/rootfs.img.xenial` (3072 MB) is untouched on the device:

```sh
sudo mv /userdata/rootfs.img /userdata/rootfs.img.2404
sudo mv /userdata/rootfs.img.xenial /userdata/rootfs.img
sudo reboot
```

The 16.04 state and its fixes are documented in `INSTALLED-STATE.md`.

## Still open

- **Rotation** — the reason for the upgrade. sensorfw is running and the HAL is uncontested, so the
  remaining question is whether sensorfw is actually reading the accelerometer and whether Lomiri is
  acting on it. Not yet diagnosed.
- First boot after the swap ended in Qualcomm crashdump mode (`05C6:900E`); a forced power-off and
  retry booted fine. Watch whether it recurs.
- Camera, Bluetooth, suspend/battery drain: untested on 24.04.

## Backups

`backups/ut-2404-2026-09-20/` — `clover.yaml`, `config-clover.xml`, `30-hidl.conf` pulled from the
running device. The 16.04 binary backups remain in `backups/ut-working-2026-09-20/`.
