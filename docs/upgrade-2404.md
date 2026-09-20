# Upgrading clover from Ubuntu Touch 16.04 to 24.04 (android9plus)

> Status: **prepared, not yet executed.** The device stays on 16.04 until the owner says go.

## Why

Rotation cannot work on 16.04 on this device. repowerd there (`xenial_-_android9`) picks its
proximity backend in this order:

```cpp
try { std::make_shared<UbuntuProximitySensor>(...); return ...; }   // FIRST
catch (...) { log("Trying SensorfwProximitySensor"); }
```

This tablet has **no proximity sensor**, and the Ubuntu/UAL backend does not throw — it blocks
forever in `Waiting for service 'sensorservice' on /dev/binder`. So repowerd never reaches sensorfw,
never registers `com.canonical.Unity.Screen`, and the power button dies. Keeping Android's
`sensorservice` alive works around that, but it then owns the vendor sensors HAL, which permits
exactly **one poller** — sensorfw gets `PERMISSION_DENIED` and rotation never works.

Current upstream repowerd (what 24.04 ships) reverses the order and tries **sensorfw first**, so
Android's sensorservice is never needed and sensorfw is the single HAL client. That is why
`amar_row_wifi` (Lenovo Tab M10 HD 2nd Gen, 24.04) has both rotation and automatic brightness.

## What changes, what stays

| | |
|---|---|
| **Replaced** | `/userdata/rootfs.img` — the Ubuntu userspace (16.04 → 24.04) |
| **Kept** | `halium-boot.img` (our Halium 9 kernel + initrd) |
| **Kept** | `/userdata/android-rootfs.img` — our Halium 9 `system.img`, including the `/persist` mountpoint patch |
| **Kept** | the vendor partition, so the `mixer_paths.xml` audio fix is unaffected |

The channel is `24.04-1.x/arm64/android9plus/stable`; **android9plus covers Halium 9**, which is what
we built. Rootfs tarball: 500 MB,
`rootfs-cf2d4f00668360d35298ea34e1b47b4434b96fb93509dc738906950ef9e261ab.tar.xz`
(the filename is its sha256 — verify before use).

## Preconditions

- Device reachable over SSH (`phablet@10.15.19.82`, password `0000`) — this is our only channel.
- `backups/ut-working-2026-09-20/` present, and `device-fixes/INSTALLED-STATE.md` current.
- Battery healthy and the tablet plugged in for the duration.
- The old `rootfs.img` is **kept on the device**, so rollback is a rename.

## Procedure (all over SSH; the old rootfs is never overwritten)

1. **Make the target image on the device, not the PC.** The device runs e2fsprogs 1.43.4 on kernel
   4.4 and cannot mount an image made by a modern `mkfs.ext4` (`metadata_csum`/`orphan_file`/`64bit`).
   Creating it with the device's own tools sidesteps that entirely:
   ```sh
   sudo fallocate -l 3G /userdata/rootfs-2404.img
   sudo mkfs.ext4 -F /userdata/rootfs-2404.img
   sudo mkdir -p /mnt/new2404 && sudo mount -o loop /userdata/rootfs-2404.img /mnt/new2404
   ```
2. **Stream and extract the tarball** (500 MB compressed beats sending a 3 GB image):
   ```sh
   # from the PC
   ssh phablet@10.15.19.82 'sudo tar -xJf - -C /mnt/new2404' < rootfs-2404.tar.xz
   ```
3. **Post-install** — the same steps `halium-install` performs for `ut20.04`. Missing the first one
   loses our only access to the device:
   ```sh
   sudo chroot /mnt/new2404 systemctl enable ssh.service usb-tethering.service
   echo phablet:0000 | sudo chroot /mnt/new2404 chpasswd
   sudo mkdir -p /mnt/new2404/android/firmware /mnt/new2404/android/persist /mnt/new2404/userdata
   for l in cache data factory firmware persist system odm product metadata; do
       [ -L /mnt/new2404/$l ] || sudo ln -s /android/$l /mnt/new2404/$l
   done
   ```
   The chroot is native (arm64 on arm64), so no qemu is needed.
4. **Re-apply the device fixes** that live in the rootfs (`device-fixes/`):
   - `/persist` → `/mnt/vendor/persist` (the stock symlink points at a path that does not exist)
   - `/etc/deviceinfo/devices/clover.yaml` — declares all four `SupportedOrientations`
   - `/usr/share/repowerd/device-configs/config-clover.xml` — **the 4095 backlight range**; without
     it the screen comes up at ~2% and looks dead
   - The upstart jobs do **not** carry over: 24.04 is systemd, and the `sensorservice` job should be
     unnecessary once repowerd prefers sensorfw. Re-add only what proves necessary, as systemd units.
5. **Swap and reboot:**
   ```sh
   sudo mv /userdata/rootfs.img /userdata/rootfs.img.xenial
   sudo mv /userdata/rootfs-2404.img /userdata/rootfs.img
   sudo reboot
   ```

## Rollback

```sh
sudo mv /userdata/rootfs.img /userdata/rootfs.img.2404
sudo mv /userdata/rootfs.img.xenial /userdata/rootfs.img
sudo reboot
```

If 24.04 does not boot far enough for SSH, do the same renames from the **halium initrd telnet
shell** (`192.168.2.15:23`, `scripts/device/tsh.sh`) — the method used for the original install.
Nothing in this procedure touches `halium-boot`, the android system image, or the vendor partition,
so the fallback path itself cannot be damaged by it.

## Verification checklist after first 24.04 boot

- [ ] SSH reachable (if not: initrd telnet, roll back)
- [ ] `com.canonical.Unity.Screen` registered, panel blanks and wakes, backlight non-zero
- [ ] `/sys/class/leds/lcd-backlight/brightness` sane (not 0, not <100 on a 4095 scale)
- [ ] Android container up; `sensorfw` polling with **0** `Poll failed` entries
- [ ] Android `sensorservice` **not** running — if repowerd still needs it, the upgrade did not
      deliver its main benefit
- [ ] **Rotation** follows the tablet
- [ ] Audio still loud (vendor `mixer_paths.xml` untouched)
- [ ] Wi-Fi, touch, brightness slider
- [ ] No self-reboots over a 10-minute watch

## Known risks

- 24.04 is systemd; every upstart job we wrote is dead weight there. Expect to rewrite anything still
  needed as units.
- Our `halium-boot` initrd is Halium 9 era. It switch_roots into the rootfs and exec's `/sbin/init`,
  which systemd satisfies, but this is the least-tested assumption in the plan.
- The 24.04 container config (`lxc-android-config`) is newer than our Halium 9 system image. The
  `android9plus` channel name says Halium 9 is supported; if the container misbehaves, that is where
  to look first.
- User data in `/userdata/user-data` is not touched by this procedure, but `ut-data.tgz` exists.
