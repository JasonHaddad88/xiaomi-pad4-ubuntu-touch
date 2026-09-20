# Known-good installed state — clover, 2026-09-20

**User-confirmed working:** display + touch, GPU, Wi-Fi, battery, **screen turn-off and wake with the
power button**, **brightness slider**, loud audio, charging while off.
**Not working:** rotation (next task), camera. **Untested:** Bluetooth, suspend/resume, battery drain.

This is the restore point. Every md5 below was verified against the device on 2026-09-20 with the
system in its confirmed-working state.

## Files installed on the device

| md5 | path on device | repo copy | what it does |
|---|---|---|---|
| `1e30a5ae1f3c23d3ff41718e18ff8397` | `/etc/init/sensorservice.conf` | `device-fixes/sensorservice.conf` | starts + keeps Android `sensorservice` (repowerd blocks without it), binds `/persist`, restarts sensorfw once |
| `b47a0d9fd526f0902b43904dd60a1223` | `/usr/share/repowerd/device-configs/config-clover.xml` | `device-fixes/config-clover.xml` | backlight range for this panel (min 40, max 4095, default 1640, dim 100) |
| `896b776155ccbd771b7f65d72c04f3b4` | `/etc/init/lxc-android-config.override` | `device-fixes/lxc-android-config.override` | always emit `android`; stops plugged-in reboots leaving `/userdata` read-only |
| `ce8c818f4b116148312e81cd2447f498` | `/home/phablet/.config/upstart/audiosystem-passthrough.override` | `device-fixes/audiosystem-passthrough.override` | disables the crash-looping call-audio bridge that triggered watchdog reboots |
| `84c1545219312a21f8a5b0e26f149c16` | `/android/vendor/etc/mixer_paths.xml` | patch documented in `README.md` §2 | speaker switch — loud audio |

## Originals kept for revert

| md5 | where |
|---|---|
| `fe91950f9bbd3c816a7483411ad67f37` | `/etc/init/lxc-android-config.override.orig` (device) + `device-fixes/lxc-android-config.override.orig` |
| `85f53f6f32a513f96139c5ef7bfb814d` | `/etc/init/sensorfw.override` — stock, unmodified; copy in `backups/…/sensorfw.override.stock` |
| `a91d54c9ea3481b788a378f7aec2c53c` | `/etc/deviceinfo/sensorfw/hybris.conf` — stock; copy in `backups/…/hybris.conf.orig` |
| `e3571247681a812a5b62875e7ff614ba` | `/android/vendor/etc/mixer_paths.xml.bak` (device) + `backups/…/mixer_paths.xml.orig` |

## Non-file state

- `/persist -> /mnt/vendor/persist` (stock is `/persist -> /android/persist`, which does not exist)
- `/userdata/android-rootfs.img` — patched: contains an empty `/persist` mountpoint
- `/userdata/android-rootfs.img.pristine` — the untouched original, still on the device
- gsettings `com.ubuntu.touch.system brightness` — must **not** be 0 (0 = black screen); currently ~1739
- gsettings `com.ubuntu.touch.system rotation-lock` = `false`
- `/etc/deviceinfo/devices/clover.yaml` (md5 `b4d74b2a47738f2814c4bf7ec0a5981a`, repo:
  `device-fixes/clover.yaml`) - declares all four `SupportedOrientations` and silences repowerd's
  `No device yaml config found!`. Without it the generic `halium` profile applies, which never tells
  Lomiri that rotation is allowed.

## Rebuilding the patched system image (if ever lost)

The only difference from pristine is one empty directory. Modify a **copy**, never the mounted image:

```sh
sudo cp /userdata/android-rootfs.img.pristine /userdata/new.img
LOOP=$(sudo losetup -f --show /userdata/new.img)
sudo mkdir -p /mnt/newsys && sudo mount -t ext4 $LOOP /mnt/newsys
sudo mkdir -p /mnt/newsys/persist && sudo chmod 771 /mnt/newsys/persist
sudo umount /mnt/newsys && sudo losetup -d $LOOP
sudo e2fsck -fn /userdata/new.img          # must come back clean
sudo mv /userdata/android-rootfs.img /userdata/android-rootfs.img.old
sudo mv /userdata/new.img /userdata/android-rootfs.img
```

## Full revert to stock

```sh
sudo mount -o remount,rw /
sudo rm -f /etc/init/sensorservice.conf
sudo rm -f /usr/share/repowerd/device-configs/config-clover.xml
sudo cp /etc/init/lxc-android-config.override.orig /etc/init/lxc-android-config.override
rm -f /home/phablet/.config/upstart/audiosystem-passthrough.override
sudo rm /persist && sudo ln -s /android/persist /persist
sudo mv /userdata/android-rootfs.img.pristine /userdata/android-rootfs.img
sudo cp -a /android/vendor/etc/mixer_paths.xml.bak /android/vendor/etc/mixer_paths.xml   # needs /android/vendor rw
sudo mount -o remount,ro / && sudo reboot
```

## Binary backups (in `backups/ut-working-2026-09-20/`, git-ignored — keep off-machine)

`boot.img` · `vendor.img` · `ut-data.tgz` · `persist-p48.img.gz` (32 MB, md5-verified against the
device) · `mixer_paths.xml.orig` · `hybris.conf.orig` · `sensorfw.override.stock` ·
`lxc-android-config.override.orig`

## Two rules that must not be broken

1. **Never supervise an Android service with an upstart `respawn` job.** Ubuntu Touch's watchdog
   reboots the whole device when a job hits its respawn limit. Use a `task`, or a shell loop that
   never exits.
2. **Never kill `sensorservice` once repowerd has bound to it** — repowerd exits, upstart respawns it
   blocked on binder, and the screen becomes unwakeable.
