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
