# Device fixes applied to the tablet (clover, Ubuntu Touch)

Each fix is small, reversible, and was applied only after a verified backup
(`backups/ut-working-2026-09-20/`). Restore any of them with the originals listed below.

## 1. Screen can be turned off — `sensorservice.conf`
Install to `/etc/init/sensorservice.conf` (rootfs is read-only: `sudo mount -o remount,rw /`,
install, then `sudo mount -o remount,ro /`).

`repowerd` blocks forever on binder waiting for Android's `sensorservice`, which Halium never
starts, so `com.canonical.powerd` / `com.canonical.Unity.Screen` are never registered and nothing
can blank the display. This upstart job starts the `sensorservice` binary from our own build.

**Revert:** delete `/etc/init/sensorservice.conf`.

## 2. Loud audio — speaker switch in the audio routing config
The vendor `mixer_paths.xml` ships an **empty** `<path name="speaker">`, so the speaker outputs are
never switched on (`SPK: ZERO`) and playback falls back to a weak path. Patch adds one line:

```xml
<path name="speaker">
    <ctl name="SPK" value="Switch" />
</path>
```

Applied to `/android/vendor/etc/mixer_paths.xml` (vendor partition is read-only:
`sudo mount -o remount,rw /android/vendor`, install, `remount,ro`).

- original md5 `e3571247681a812a5b62875e7ff614ba` (kept as `backups/.../mixer_paths.xml.orig`
  and on-device as `mixer_paths.xml.bak`)
- patched  md5 `84c1545219312a21f8a5b0e26f149c16`

**Revert:** `sudo cp -a /android/vendor/etc/mixer_paths.xml.bak /android/vendor/etc/mixer_paths.xml`

## 3. Rotation / sensors — `/persist` reaching the Android container
Android reported **"No Sensors on the device"**: `/vendor/bin/hw/android.hardware.sensors@1.0-service`
and `sensors.qcom` exited with status 0 every ~10s. The reason is a gate in `libsensor1`:

```
check_sensors_enabled: open error: settings file "/persist/sensors/sensors_settings", errno 2
check_sensors_enabled: Sensors enabled = false
wait_for_service: sensors setting disabled sensors
sns_main.c(447):Timeout waiting for SMGR service. Exit sensors daemon!
```

Nothing to do with firmware — SLPI has no image on this device and the SSC actually runs on the
**ADSP** (`sysmon-qmi: Connection established between QMI handle and adsp's SSCTL service`), so the
`slpi_load_fw: SLPI image loading failed` line in dmesg is a red herring. Two things kept
`/persist` from reaching the container:

1. The rootfs ships `/persist -> /android/persist`, which **does not exist**. The partition
   (`mmcblk0p48`) is mounted at `/mnt/vendor/persist`.
2. Our Halium `system.img` has **no `persist` directory**, so the container's own
   `lxc.mount.entry = /persist persist bind bind,optional` silently skipped it.

**Applied:**
- `sudo mount -o remount,rw / && sudo rm /persist && sudo ln -s /mnt/vendor/persist /persist`
- added an empty `/persist` mountpoint to the Android system image. The image was **copied first**,
  modified while unmounted (`losetup` + `mount` on the copy), `e2fsck -fn`'d clean, then swapped in
  by rename — the pristine original is still on the device as `/userdata/android-rootfs.img.orig`.
- `android-persist.conf` → `/etc/init/android-persist.conf`: binds persist inside the container as a
  fallback, then restarts the sensor stack **in order** (sensors HAL → sensorservice → sensorfw).
  `sensorfw` connects to Android's sensorservice at startup, long before the sensors exist, and just
  logs `Poll failed status 2` forever unless it is restarted afterwards.

Result: **30 h/w sensors** — BMI120 accelerometer + gyroscope, CM3232 light sensor, ROHM hall effect.

**Revert:** `sudo rm /etc/init/android-persist.conf`;
`sudo mv /userdata/android-rootfs.img.orig /userdata/android-rootfs.img`;
`sudo rm /persist && sudo ln -s /android/persist /persist` (each with the rootfs remounted rw).
Backup of the persist partition itself: `backups/.../persist-p48.img.gz` (32 MB, md5 verified).

## 4. Reboot while plugged in — `lxc-android-config.override`
The bootloader sets `androidboot.mode=charger` whenever the USB cable is attached at power-on, and
a plain reboot while plugged in is indistinguishable from a cold charger insertion (the PMIC reports
`Power-on reason: Triggered from USB (USB charger insertion)` either way). UT's stock job then does:

```sh
if [ "$(getprop ro.bootmode)" = "charger" ]; then
    echo u > /proc/sysrq-trigger      # emergency remount R/O - hits ALL filesystems
    initctl emit -n charger           # 'android' is never emitted
```

So on any plugged-in reboot: `/userdata` (home, settings, logs) goes **read-only**, and every job
that starts `on android` — `repowerd` (power button / screen blanking), `sensorfw`, our two jobs —
never starts, while the UI still comes up. That is what "rotation works but the power button
doesn't" looked like. This port has no off-charging UI, so the branch is replaced with a plain
`initctl emit android`.

**Revert:** `sudo cp /etc/init/lxc-android-config.override.orig /etc/init/lxc-android-config.override`
(also in `backups/.../lxc-android-config.override.orig`, md5 `fe91950f9bbd3c816a7483411ad67f37`).

> Note: for ~30-60s after boot, `repowerd` is restarted several times as the sensor stack settles,
> so give it a moment before judging the power button.
