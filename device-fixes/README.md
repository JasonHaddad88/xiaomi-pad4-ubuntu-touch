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

### The rotation trade-off
`sensorservice` and `sensorfw` **cannot both hold the sensors HAL**: with both running,
`vendor.sensors-hal-1-0` exits with status 255 every ~5s (71 times in one boot). Proof — the HAL was
stable from 461s to 806s of one boot, exactly the window when sensorservice was not running, and
died again the moment it was launched.

So it is one or the other:

| | screen turn-off | rotation |
|---|---|---|
| `sensorfw` disabled *(current)* | ✅ | ❌ |
| `sensorfw` enabled | ❌ power button dead | ✅ |

**To swap to rotation instead:** remove the trailing `manual` line from `/etc/init/sensorfw.override`
and reboot. Original: `backups/.../sensorfw.override.orig`.

Measured on the current setup: sensorservice stable for 5+ minutes (never restarted), repowerd and
`com.canonical.Unity.Screen` up throughout, **HAL started once**, no watchdog hits.

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
