# Device fixes applied to the tablet (clover, Ubuntu Touch)

Each fix is small, reversible, and was applied only after a verified backup
(`backups/ut-working-2026-09-20/`). Restore any of them with the originals listed below.

## 1. Rotation + screen turn-off — `sensor-bringup.conf`
Install to `/etc/init/sensor-bringup.conf` (rootfs is read-only: `sudo mount -o remount,rw /`,
install, then `sudo mount -o remount,ro /`).

### How stock Ubuntu Touch does sensors
```
sensors HAL  <--  sensorfw (the ONLY client)  <--D-Bus--  Lomiri (rotation), repowerd (light/proximity)
```
repowerd is built with `SensorfwLightSensor` / `SensorfwProximitySensor` and talks to sensorfw's
`com.nokia.SensorService`. Chasing this properly is what unstuck the whole problem — an earlier fix
here ran Android's `/system/bin/sensorservice` permanently, which no normal port does, and that
second HAL client caused every symptom that followed.

### The one twist on this device
The repowerd in this rootfs still binds android's binder `sensorservice` **at startup**. Without it
it sits in `Waiting for service 'sensorservice' on /dev/binder` forever, never registers
`com.canonical.Unity.Screen`, and the display can then be neither blanked nor woken — the power
button looks dead. But it only needs sensorservice long enough to **bind**: afterwards it keeps
serving `com.canonical.Unity.Screen` fine with sensorservice gone.

So the job: bring sensorservice up → **wait until repowerd has actually registered on D-Bus** → kill
it → restart sensorfw so it owns the HAL again. If screen control never comes up, it leaves
sensorservice running instead, because a working power button beats rotation.

It triggers on `start on started repowerd`, so it also re-arms if repowerd restarts later — otherwise
repowerd would block forever on a sensorservice that no longer exists.

> ### ⚠ Never let an upstart job flap on Ubuntu Touch
> The watchdog **reboots the device** when a job hits its respawn limit:
> ```
> watchdog: 'sensorservice' (instance '') hit respawn limit - rebooting
> ```
> An earlier `exec … ` + `respawn` version of this fix turned the tablet into a boot loop. This is a
> one-shot `task`; nothing here may ever flap.

**Verified after a clean reboot:** `com.canonical.Unity.Screen` registered by ~74s · HAL restarts
settle at 4 and then freeze · sensorservice gone · sensorfw serving the accelerometer plugin ·
panel blanks on the idle timeout and wakes on command · zero watchdog hits.

**Expected behaviour:** the screen blanks by itself after ~60-90s of no input. That is Ubuntu Touch's
normal inactivity timeout, not a fault; the power button wakes it.

**Revert:** delete `/etc/init/sensor-bringup.conf`.

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

## 3. Supporting changes that make the sensors exist
Without these, android reports **"No Sensors on the device"** — the Qualcomm sensor daemon gates on
`/persist/sensors/sensors_settings`:
```
libsensor1: check_sensors_enabled: Sensors enabled = false
Sensors : sns_main.c(447):Timeout waiting for SMGR service. Exit sensors daemon!
```
- **Symlink:** `/persist -> /mnt/vendor/persist` (stock is `/persist -> /android/persist`, which does
  not exist; the partition is `mmcblk0p48`).
- **System image:** an empty `/persist` mountpoint, so LXC's
  `lxc.mount.entry = /persist persist bind bind,optional` stops skipping it. The image was copied,
  modified while unmounted, `e2fsck -fn`'d clean and swapped in by rename. The untouched original is
  on the device as `/userdata/android-rootfs.img.pristine`.

Not a firmware problem: there is no SLPI image on this device and the SSC runs on the **ADSP**, so
`slpi_load_fw: SLPI image loading failed` in dmesg is a red herring.

Result: **30 h/w sensors** — BMI120 accelerometer + gyroscope, CM3232 light, ROHM hall effect.

**Revert:** `sudo mv /userdata/android-rootfs.img.pristine /userdata/android-rootfs.img`;
`sudo rm /persist && sudo ln -s /android/persist /persist` (rootfs remounted rw).
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
