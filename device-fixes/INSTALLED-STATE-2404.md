# Installed state — clover on Ubuntu Touch 24.04 (noble)

Last verified **2026-09-26** against the running device. Every md5 below was read off the tablet.

| | |
|---|---|
| OS | Ubuntu **24.04.4 LTS** (noble), channel `24.04-1.x/arm64/android9plus/stable` |
| kernel | `4.4.153-HandsomeKernel+` (ours, unchanged) |
| init | **systemd** (the 16.04 upstart jobs are obsolete and gone) |
| boot / android | our Halium 9 `halium-boot` + `android-rootfs.img`, unchanged |
| vendor partition | unchanged — the `mixer_paths.xml` audio fix still applies |
| free space | **38 GB** on `/userdata`, **1.3 GB** on the read-only rootfs |

**Owner-confirmed working:** display, touch, GPU, Wi-Fi, audio (loud), brightness slider, screen
off/wake via power button, **rotation**, Morph browser, charging while off.
**Camera: working** — owner-confirmed, and verified here by grabbing the rendered viewfinder and
measuring it (`stddev 0.00 -> 67.05`). **Untested:** Bluetooth (deliberately masked), suspend/battery life.

## Access

| route | detail |
|---|---|
| **ssh over Wi-Fi** | `ssh phablet@192.168.1.64` — key **and** password both work. This is the reliable route |
| ssh key | `/root/.ssh/id_ed25519` in WSL; public key in the **persistent** home `/userdata/user-data/phablet/.ssh`, so it survives rootfs swaps |
| **adb** | works only after Developer Mode is (re)armed. **After a fresh boot the USB gadget comes up as RNDIS** (`VID_1209&PID_0004`, Windows shows Code 28) and adb is absent until then |
| old 16.04 route | `ssh phablet@10.15.19.82` is **dead** — `usb0` still holds that IP but is DOWN |

## Files installed (md5 verified on device 2026-09-26)

| md5 | path on device | repo copy | purpose |
|---|---|---|---|
| `5dcaec6f8c0bef6d5b5460ca4b7d05be` | `/etc/sensorfw/sensord.conf.d/25-clover.conf` | `device-fixes/25-clover-sensorfw.conf` | **rotation** — overrides sensorfw's availability gate |
| `5fe6fbffe31fcf3b09e325e6c2ae3e35` | `/etc/deviceinfo/devices/clover.yaml` | `device-fixes/clover-2404.yaml` | declares all four `SupportedOrientations` |
| `b47a0d9fd526f0902b43904dd60a1223` | `/usr/share/repowerd/device-configs/config-clover.xml` | `device-fixes/config-clover.xml` | backlight range for this panel (min 40, **max 4095**, default 1640, dim 100) |
| `e3b9913132136a7d5d6f667d12527278` | `/usr/local/bin/clover-persist-bind` | `device-fixes/clover-persist-bind.sh` | binds persist into the Android container so the sensors work |
| `b1ab384d03b42d804d0b362045c45c8b` | `/etc/systemd/system/clover-persist-bind.service` | `device-fixes/clover-persist-bind.service` | runs the above at boot (oneshot, no `Restart=`) |
| `ebebbbd9d189db96b6188c9b5b8090a7` | `~/.config/systemd/user/lomiri-app-launch--application-legacy--morph-browser--.service.d/50-clover-webengine.conf` | `device-fixes/50-webengine-clover.conf` | **the one that actually fixes Morph** — forces software video decode |
| `a8ae74075f21ab7aa2f85a487e1ca9cd` | `~/.config/environment.d/50-webengine-clover.conf` | same | session-wide fallback for the above |
| `0df57593e5e4318169220983cb0d8856` | `~/.local/bin/ct` | `device-fixes/ct` | run container tools (git, apt, …) from the terminal |
| `dab9b32a22b99731c339dab99cb7c1de` | `/etc/udev/rules.d/70-clover-binder.rules` | `device-fixes/70-clover-binder.rules` | **camera** — `/dev/hwbinder` and `/dev/vndbinder` to 0666 as `ueventd.rc` intends |
| `1d706856bb0a76f0610cdf2f913bed1d` | `/etc/systemd/system/clover-binder-perms.service` | `device-fixes/clover-binder-perms.service` | same, at boot — the nodes appear too early for udev alone to be trusted |

The camera also needs a change **inside the Android system image**, not a file on the rootfs:

| | |
|---|---|
| what | `/system/lib/vndk-sp-28/` created and filled with 25 libraries |
| why | the 32-bit `CameraService` aborted with `gralloc-mapper is missing`; the sphal namespace resolves the mapper's dependency only through `/system/${LIB}/vndk-sp-28`, and the 32-bit one was never built |
| how | [`device-fixes/clover-vndk-sp-32.sh`](clover-vndk-sp-32.sh) — the loop device is write-protected, so the image is modified as a copy and swapped in |
| live image md5 | `9354f91cba2f1eea4bdcc7a2f07ba467` |
| revert | `mv /userdata/android-rootfs.img{,.vndk} && mv /userdata/android-rootfs.img{.old,} && reboot` |

Also: `PasswordAuthentication=yes` in `/etc/ssh/sshd_config.d/50-lxc-android-config.conf`
(24.04 ships `no`), and `/persist -> /mnt/vendor/persist`.

## Service state

```
repowerd=active   sensorfwd=active   ssh=active
clover-persist-bind=active           bluebinder=masked
clover-binder-perms=active/enabled
```

`clover-binder-perms` was verified the honest way: the modes were reset to `0600` by hand, the unit was
started, and both nodes came back `crw-rw-rw-`.

`bluebinder` is **masked**, not merely disabled — plain `disable` was undone because
`bluetooth.service` pulls it in, and it crash-looped every ~61 s. Re-enable with
`sudo systemctl unmask --now bluebinder` if Bluetooth is ever wanted.

## Libertine container

- id `clover`, chroot type, **2.4 GB**
- **Remmina**, **VLC** and **Standard Notes** installed and working
- Standard Notes is the official arm64 `.deb` 3.202.7 (487 MB installed), sha256-verified,
  registered as `clover_standard-notes_0.0`. It needed a root install inside the chroot —
  `libertine-container-manager install-package` cannot handle a downloaded `.deb`; the recipe and
  the reasons are in the guide
- `~/.local/bin/ct` gives terminal access to it
- Full explanation and self-service guide: [`docs/libertine-guide.md`](../docs/libertine-guide.md)

## Non-file state that matters

- gsettings `com.ubuntu.touch.system brightness` — must **never** be 0. Zero means the panel powers on
  with the backlight off, which looks exactly like a dead screen/dead power button
- gsettings `com.ubuntu.touch.system rotation-lock` = `false`
- `/userdata/android-rootfs.img.pristine` — the untouched Halium system image (rollback for the
  `/persist` mountpoint patch)
- `/userdata/android-rootfs.img.old` and `…​.prevndk` — the pre-camera-fix image, both
  md5 `775635294f5a518f1d98b58560d3558b`. Keep at least one; `/userdata` has 38 GB free

## Rollback to 16.04

No longer on the device — the image was moved to the PC to reclaim 3 GB:
`backups/ut-working-2026-09-20/rootfs.img.xenial`, md5 **`bb98c95f85afd2b61ba764c64cb84915`**,
verified identical to the device copy before deletion. To return to 16.04: push it back to
`/userdata/rootfs.img.xenial`, then swap the two filenames and reboot. `halium-boot`, the Android
system image and the vendor partition were never modified, so that path remains intact.

## Rules that must not be broken

1. **Never supervise an Android-container service with an upstart `respawn` job** (16.04) — UT's
   watchdog reboots the whole device when a job hits its respawn limit. On 24.04, systemd units here
   are `Type=oneshot` with no `Restart=` for the same reason.
2. **Check what starts a service before disabling it.** `bluebinder` came straight back because
   `bluetooth.service` wants it; masking was required.
3. **Verify the capability, not a proxy for it.** "repowerd answers D-Bus" is not "the screen powers
   on"; read `panel_power_on` *and* `/sys/class/leds/lcd-backlight/brightness`.

## Instruments

There is no way to screenshot this device from a PC (Mir 1.8 has no `wlr-screencopy`,
`mirscreencast` is refused, `grim` is not installed). The workarounds — holding the display on,
dismissing the greeter, proving an app is focused, and having QML grab its own output — are kept in
[`scripts/device/camera-probe/`](../scripts/device/camera-probe/). Nothing from them is left
installed on the device.
