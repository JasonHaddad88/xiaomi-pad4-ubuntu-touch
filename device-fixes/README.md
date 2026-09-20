# Device fixes applied to the tablet (clover, Ubuntu Touch)

Each fix is small, reversible, and was applied only after a verified backup
(`backups/ut-working-2026-09-20/`). Restore any of them with the originals listed below.

## 1 + 3. Screen turn-off AND rotation — `sensor-bringup.conf`
Install to `/etc/init/sensor-bringup.conf` (rootfs is read-only: `sudo mount -o remount,rw /`,
install, then `sudo mount -o remount,ro /`).

Three separate problems, one job:

**(a) repowerd needs Android's `sensorservice`.** It blocks forever on binder ("Waiting for service
'sensorservice' on /dev/binder"), so `com.canonical.Unity.Screen` is never registered and nothing can
blank the display. Halium has no Android framework to start it.

**(b) Sensors were entirely absent** — `dumpsys sensorservice` said "No Sensors on the device"
because the Qualcomm sensor daemon gates on `/persist/sensors/sensors_settings`:

```
libsensor1: check_sensors_enabled: Sensors enabled = false
libsensor1: wait_for_service: sensors setting disabled sensors
Sensors : sns_main.c(447):Timeout waiting for SMGR service. Exit sensors daemon!
```

`/persist` never reached the container: the rootfs ships `/persist -> /android/persist`, which does
not exist (the partition, `mmcblk0p48`, is mounted at `/mnt/vendor/persist`), and our `system.img`
had no `persist` directory, so LXC's `lxc.mount.entry = /persist persist bind bind,optional` silently
skipped it. Fixed by repointing the symlink and adding the mountpoint to the system image (below).

**(c) `sensorservice` and `sensorfw` cannot both hold the sensors HAL.** With both running,
`vendor.sensors-hal-1-0` exits with status 255 every ~5s and sensorservice dies with `Abort due to
ISensors hidl service failure ... DEAD_OBJECT`. With sensorservice gone, the HAL is stable for hours.
But repowerd only needs sensorservice to exist *when it starts* — it keeps working, and keeps
answering on `com.canonical.Unity.Screen`, after sensorservice goes away.

So the job starts sensorservice, kicks repowerd so it binds, then **kills sensorservice** and hands
the HAL back to sensorfw. Result: screen turn-off and rotation at the same time.

> ### ⚠ Never supervise an Android service with upstart on this OS
> Ubuntu Touch's watchdog **reboots the device** when an upstart job hits its respawn limit:
> ```
> watchdog: 'sensorservice' (instance '') hit respawn limit - rebooting
> ```
> Because sensorservice crash-loops whenever the HAL goes away, an earlier `respawn`-based version of
> this fix turned the tablet into a **boot loop** — never reaching the desktop, or flickering and
> switching off. An earlier version also restarted repowerd from `post-start` on *every* respawn,
> giving 60 repowerd restarts in two hours, which tore the display stack down over and over.
> That is why this job is a one-shot `task` that runs once and exits.

**Revert:** delete `/etc/init/sensor-bringup.conf`.

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

## 3. Supporting changes for the sensors (persistent, outside the job)
- **Symlink:** `sudo mount -o remount,rw / && sudo rm /persist && sudo ln -s /mnt/vendor/persist /persist`
- **System image:** added an empty `/persist` mountpoint. The image was **copied first**, modified
  while unmounted (`losetup` + `mount` on the copy), `e2fsck -fn`'d clean, then swapped in by rename —
  the pristine original is still on the device as `/userdata/android-rootfs.img.orig`.

Not a firmware problem: there is no SLPI image on this device at all and the SSC runs on the **ADSP**
(`sysmon-qmi: Connection established between QMI handle and adsp's SSCTL service`), so the
`slpi_load_fw: SLPI image loading failed` line in dmesg is a red herring.

Result: **30 h/w sensors** — BMI120 accelerometer + gyroscope, CM3232 light sensor, ROHM hall effect.

**Revert:** `sudo mv /userdata/android-rootfs.img.orig /userdata/android-rootfs.img`;
`sudo rm /persist && sudo ln -s /android/persist /persist` (rootfs remounted rw).
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
