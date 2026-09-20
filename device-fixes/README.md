# Device fixes applied to the tablet (clover, Ubuntu Touch)

Each fix is small, reversible, and was applied only after a verified backup
(`backups/ut-working-2026-09-20/`). Restore any of them with the originals listed below.

## 1. Screen turn-off — `sensorservice.conf` (and why rotation is off)
Install to `/etc/init/sensorservice.conf` (rootfs is read-only: `sudo mount -o remount,rw /`,
install, then `sudo mount -o remount,ro /`).

repowerd blocks on binder waiting for Android's `sensorservice` ("Waiting for service
'sensorservice' on /dev/binder"), never registers `com.canonical.Unity.Screen`, and the display can
then never be blanked **or woken** — the power button does nothing. Halium has no Android framework
to start it, so this job does.

> ### ⚠ Two hard rules, both learned painfully
> **1. Upstart must never see this job exit.** Ubuntu Touch's watchdog **reboots the device** when a
> job hits its respawn limit:
> ```
> watchdog: 'sensorservice' (instance '') hit respawn limit - rebooting
> ```
> sensorservice crash-loops whenever the sensors HAL goes away (`Abort due to ISensors hidl service
> failure ... DEAD_OBJECT`), so an `exec …` + `respawn` version turned the tablet into a **boot
> loop**. The job's main process is now a shell that loops forever and never exits, so upstart never
> respawns anything and the watchdog is never triggered.
>
> **2. Never kill sensorservice once it is up.** An earlier version started it, let repowerd bind,
> then killed it ~16s later to free the HAL for rotation. That blanked the screen ~16 seconds into
> every session and left the power button dead.

### Rotation is REVERTED on the device (2026-09-20)
`sensorservice` and `sensorfw` **cannot both hold the sensors HAL**: with both running,
`vendor.sensors-hal-1-0` exits with status 255 every ~5s (71 times in one boot). Every scheme that
tried to give both — killing sensorservice after repowerd bound, retriggering on repowerd restart —
produced a worse experience than either alone: the screen blanking ~16s into a session, a dead power
button, and self-reboots. **The whole rotation change set was reverted** back to the last state the
device owner described as "almost seamless". See section 3.

**Expected behaviour:** the screen still blanks on its own after ~60-90s of no input — that is Ubuntu
Touch's normal inactivity timeout, not a fault. The power button wakes it.

**Revert:** delete `/etc/init/sensorservice.conf`.

## 1b. Random self-reboots — `audiosystem-passthrough`
```
session-watchdog: 'audiosystem-passthrough' hit respawn limit - asking logind to reboot
```
A second, unrelated reboot source. `audiosystem-passthrough` bridges **cellular call audio** into
PulseAudio; this is a WiFi-only tablet, so it has no job to do, and it crash-loops until the session
watchdog reboots the device. Disabled with a session override:

```
/home/phablet/.config/upstart/audiosystem-passthrough.override   ->   manual
```

**Revert:** delete that file. (A harmless `<defunct>` child of pulseaudio may still appear; the
crash-looping *job* is what the watchdog counted.)

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

## 3. Sensors / rotation — REVERTED (kept here for a future attempt)
These made all 30 sensors work (BMI120 accelerometer + gyroscope, CM3232 light, ROHM hall effect) and
rotation worked — but they also make the sensors HAL fight `sensorservice`, which costs screen
turn-off and stability. **Both are reverted on the device.**

What they were:
- **Symlink:** `/persist -> /mnt/vendor/persist` (stock is `/persist -> /android/persist`, which does
  not exist; the partition is `mmcblk0p48`). Without it the Qualcomm sensor daemon gates out:
  `check_sensors_enabled: Sensors enabled = false` -> `Timeout waiting for SMGR service` -> android
  reports "No Sensors on the device".
- **System image:** an empty `/persist` mountpoint, so LXC's
  `lxc.mount.entry = /persist persist bind bind,optional` stops skipping. The patched image is still
  on the device as **`/userdata/android-rootfs.img.persistfix`**; the pristine one is live.

Not a firmware problem: there is no SLPI image on this device and the SSC runs on the **ADSP**, so
`slpi_load_fw: SLPI image loading failed` in dmesg is a red herring.

**To try rotation again** (expect the screen-turn-off regression unless the HAL conflict is solved
first):
```sh
sudo mount -o remount,rw /
sudo rm /persist && sudo ln -s /mnt/vendor/persist /persist
sudo mv /userdata/android-rootfs.img /userdata/android-rootfs.img.pristine
sudo mv /userdata/android-rootfs.img.persistfix /userdata/android-rootfs.img
sudo mount -o remount,ro / && sudo reboot
```
Backup of the persist partition: `backups/.../persist-p48.img.gz` (32 MB, md5 verified).

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
