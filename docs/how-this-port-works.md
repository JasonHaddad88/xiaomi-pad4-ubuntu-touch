# How this port works — the whole thing, explained

A single document that explains **what was built, what every piece is, how they fit together, what went
wrong, and why**. It assumes no prior Android-porting knowledge and defines terms as it goes.

The other documents are references for doing things. This one is for *understanding* them:

| if you want | read |
|---|---|
| to understand the system | **this file** |
| what happened, when, in what order | [porting-log.md](porting-log.md) — chronological, newest first |
| what is installed on the device right now | [../device-fixes/INSTALLED-STATE-2404.md](../device-fixes/INSTALLED-STATE-2404.md) |
| every fix and its revert command | [../device-fixes/README.md](../device-fixes/README.md) |
| desktop apps in a container | [libertine-guide.md](libertine-guide.md) |
| how to see the device's screen / debug graphics | [../scripts/device/camera-probe/](../scripts/device/camera-probe/) |

---

## 1. The thirty-second version

The Xiaomi Mi Pad 4 is an Android tablet. We wanted it to run **Ubuntu Touch**, a Linux phone OS.

The hardware only has **Android drivers** — Qualcomm never released Linux ones. So instead of replacing
Android entirely, we keep a stripped-down Android 9 system in a **container**, purely so its drivers
keep running, and run real Ubuntu on top. A translation layer lets Ubuntu programs call Android
drivers. That arrangement is called **Halium**.

Everything hard about this project comes from that one compromise: two operating systems sharing one
kernel, one GPU, one set of device nodes, each with different assumptions about who owns what.

---

## 2. Key terms

Read this once; everything later depends on it.

**Android HAL (Hardware Abstraction Layer)** — the vendor's closed-source driver libraries
(`camera.sdm660.so`, `gralloc.sdm660.so`, …). They are compiled for Android, expect Android's C library
(*Bionic*) and Android's service system. They are the reason we can't just run plain Linux.

**libhybris** — the translation layer. It loads Android `.so` libraries into a normal Linux (*glibc*)
process and fakes enough of Bionic for them to work. It is what lets Ubuntu's compositor talk to an
Adreno GPU driver written for Android.

**Halium** — the project that standardises the above: a minimal Android build, a container to run it
in, and the glue. **Halium 9** means the Android 9 generation. Our base is LineageOS 16 (= Android 9)
for the SDM660 chip family.

**The Android container** — a real Android userspace running under **LXC** as `/android`, started by
`lxc-android-config`. It runs `init`, `hwservicemanager`, `cameraserver`, the sensor daemon and the
HAL services — but **no apps, no Java framework, no launcher**. Think of it as a driver appliance.

**binder / hwbinder / vndbinder** — Android's inter-process communication. Three separate channels:
`binder` for framework, `hwbinder` for HALs (HIDL), `vndbinder` for vendor-internal traffic. They are
character devices: `/dev/binder`, `/dev/hwbinder`, `/dev/vndbinder`. **Their permissions matter** — see
§7.4, where wrong permissions on one of them crashed the camera.

**HIDL** — the interface language Android 8+ uses between frameworks and HALs. A HIDL service can run
**binderized** (its own process, reached over hwbinder) or **passthrough** (dlopen'd directly into the
caller). Which one applies is declared in a *VINTF manifest* (`/vendor/etc/vintf/manifest.xml`).

**gralloc** — the graphics memory allocator. Every camera frame, video frame and window buffer is a
gralloc buffer. Two halves: the **allocator** (creates buffers) and the **mapper** (maps them into a
process). If the mapper can't load, anything touching graphics buffers dies. It did, twice (§7.4).

**VNDK / VNDK-SP / linker namespaces** — Android 8+ stops vendor code from loading system libraries
freely. The dynamic linker is split into **namespaces** with separate search paths, configured in
`/system/etc/ld.config.28.txt`:

- `sphal` — where vendor HAL libraries get loaded. Searches `/vendor/lib*` only.
- `vndk` — the small set of system libraries vendor code *is* allowed to use, from
  `/system/${LIB}/vndk-sp-28`.

A library being present on disk means nothing if it isn't in a directory the loading namespace may
search. That distinction is the entire cause of the black camera (§7.5).

**Mir / Lomiri / XMir** — **Mir** is the display server, **Lomiri** the Ubuntu Touch shell (the UI you
touch), **XMir** an X server used to show old X11 apps inside it. On 24.04 Mir speaks **Wayland**.

**repowerd** — the power daemon: screen on/off, dimming, brightness, idle timeouts, the power button.
When it misbehaves the device looks bricked (§7.2).

**sensorfw** — Ubuntu Touch's sensor daemon. It reads the Android sensor HAL through libhybris and
feeds the UI. It's what makes screen rotation work.

**deviceinfo** — per-device configuration Ubuntu Touch reads from `/etc/deviceinfo/devices/<codename>.yaml`
(screen orientations, quirks).

**click / Libertine** — two ways to install software. **Click** packages are Ubuntu Touch's sandboxed
mobile apps (confined by *AppArmor*). **Libertine** is a container holding an ordinary Ubuntu
filesystem so normal desktop programs (VLC, Remmina, Standard Notes) can run.

**system-image channel** — how Ubuntu Touch ships OS images, e.g. `24.04-1.x/arm64/android9plus/stable`.
`android9plus` means "built to sit on a Halium 9 or newer base" — which is why our Android-9 base can
run a 2024-era Ubuntu.

### Flashing vocabulary

**fastboot** — the bootloader's flashing protocol. On this tablet the bootloader's own fastboot
(USB ID `18D1:D00D`) is **unusable from this Windows PC** (no signed driver; a generic one crashed the
bootloader).

**fastbootd** — a *newer, userspace* fastboot that runs from Android itself (`adb reboot fastboot`,
USB ID `18D1:4EE0`). Google's official driver supports it, so **this is the one that works from the PC**.

**EDL (Emergency Download, `05C6:900E`)** — Qualcomm's last-resort SoC recovery mode. On Xiaomi SDM660
it requires authorised firehose files, so for us it is a dead end, not a safety net.

**A/B vs non-A/B** — some devices keep two copies of the OS to update safely. This one is **non-A/B**:
a single slot. Get it wrong and there's no second copy to fall back to.

**Dynamic partitions / `super` / retrofit** — Android 10+ puts `system`/`vendor` inside one `super`
container. "Retrofit" means `super` was layered over the *existing* physical partitions, so the real
`system` (p13) and `vendor` (p14) still exist underneath — which is exactly what let us flash a
legacy-layout Halium build onto a device shipping the modern layout.

**system-as-root** — the system partition *is* `/` rather than being mounted at `/system`.

---

## 3. The device

| | |
|---|---|
| Codename | `clover` (Mi Pad 4 and Mi Pad 4 Plus) |
| This unit | Mi Pad 4, **Wi-Fi only**, 4 GB RAM / 64 GB |
| SoC | **SDA660** — the *modem-less* variant of Snapdragon 660 |
| GPU | Adreno 512, GLES 3.2, Vulkan 1.1 |
| Display | 8″ IPS, **1200×1920** portrait-native, ~283 ppi |
| Touch | FocalTech `fts_ts`, 10-point |
| Sensors | Bosch BMI120 accel+gyro, Capella CM3232 light, hall/folio switch |
| Battery | 6000 mAh |
| Was running | PixelExperience 13 (Android 13, kernel 4.19) |
| Now running | Ubuntu Touch 24.04 on Halium 9, kernel **4.4.153** |

Two device facts shaped the whole project:

1. **No modem.** The SoC is modem-less, so there is no telephony stack at all. In Halium ports the
   modem/RIL is usually the single biggest source of pain — here it simply doesn't exist. This port is
   much easier than a phone port for that one reason.
2. **No proximity sensor.** Sounds trivial. It cost weeks (§7.2) because `repowerd` blocked forever
   waiting for a sensor that isn't there.

### Partitions

Physical GPT, unchanged by the retrofit layout:

| name | device | what we put there |
|---|---|---|
| `boot` | `mmcblk0p12` | **our `halium-boot.img`** (kernel + Halium initrd) |
| `system` | `p13` | unused by us — we ship system as a *file* instead |
| `vendor` | `p14` | **our `vendor.img`** — the Android 9 driver blobs |
| `persist` | `p48` | sensor calibration (read-only, factory data) |
| `userdata` | `p64`, 51 GB | everything: both OS images, your files |
| `misc` | `p50` | boot-mode flags — **the partition that trapped the device**, §6.2 |

On `/userdata`:

| file | what it is |
|---|---|
| `rootfs.img` | **Ubuntu** — the OS you actually use |
| `android-rootfs.img` | **Android 9 system** — mounted at `/android`, the container's root |
| `android-rootfs.img.pristine` | untouched original, rollback |
| `android-rootfs.img.old` / `.prevndk` | pre-camera-fix copies |
| `rootfs.img.xenial` | the old 16.04 Ubuntu (moved to PC to reclaim 3 GB) |

Keeping both OSes as **files on `/userdata`** rather than real partitions is the single best decision
in this project: every risky change becomes *copy the file, modify the copy, rename*. A bad change is
undone with `mv`.

---

## 4. The layer cake

```
┌─────────────────────────────────────────────────────────────┐
│  Lomiri (the UI)   ·   apps: click / Libertine              │
├─────────────────────────────────────────────────────────────┤
│  Ubuntu Touch 24.04 userspace                               │
│  systemd · repowerd · sensorfw · Mir/Wayland · PulseAudio   │
├─────────────────────────────────────────────────────────────┤
│  libhybris  ── translates glibc → Bionic ───────────────────│
├─────────────────────────────────────────────────────────────┤
│  Android 9 container (LXC, "/android")                      │
│  init · hwservicemanager · cameraserver · sensor daemon     │
│  vendor HALs: gralloc · camera · audio · GPU (Adreno)       │
├─────────────────────────────────────────────────────────────┤
│  Linux kernel 4.4.153  (Android's kernel — shared by both)  │
└─────────────────────────────────────────────────────────────┘
```

Reading it top to bottom explains almost every bug in §7:

- Only **one kernel**, shared. Both sides see the same `/dev`.
- The Android side exists **only** to host drivers.
- Ubuntu processes call into Android libraries through libhybris, so a failure in an Android library
  surfaces as a crash in an *Ubuntu* process — which is why the camera app died with an Android abort
  message (§7.4).
- **Nobody arbitrates.** If both sides want the same hardware, they conflict. That's §7.3.

### What is ours vs upstream

| built by us | taken from upstream |
|---|---|
| `halium-boot.img` (kernel 4.4 + initrd) | Ubuntu Touch rootfs (UBports channel) |
| `android-rootfs.img` (Halium system) | Lomiri, Mir, repowerd, sensorfw |
| `vendor.img` (driver blobs) | libhybris |
| every file in `device-fixes/` | the Android 9 vendor blobs themselves |

We build the *bottom*, use upstream's *top*, and the fixes are almost all in the seam.

---

## 5. How it was built

Build host: **WSL2, Ubuntu 26.04, 24 cores**. Source tree (~36 GB) lives in WSL's ext4; this repo holds
only text.

### Phase 0–1 — get the source

`repo` (Google's multi-repository tool) pulls ~397 git repositories described by a manifest. Our
`local_manifest` adds the three clover-specific ones: device tree, kernel, vendor blobs.

Then **107 hybris patches** are applied — these modify AOSP to build the Halium variant instead of a
phone ROM. Milestone: `breakfast clover` resolves the configuration.

> **Trap found here:** `--` is illegal inside an XML comment. Our manifest had a `------` separator, so
> the XML parser rejected the whole file and `repo` **silently ignored it** — no error, just missing
> repositories. Silent failure from a cosmetic character.

### Phase 2–3 — compile

```
mka halium-boot     →  halium-boot.img   52 MB
mka systemimage     →  system.img       217 MB
mka vendorimage     →  vendor.img       800 MB
```

An Android 9 build system does not expect a 2026 host. It worked without Docker, but needed **five
shims** (all in `scripts/setup/`):

| shim | why |
|---|---|
| `libtinfo.so.5` symlink | AOSP-9's prebuilt clang links a library Ubuntu 26.04 no longer ships. *The* blocker. |
| Python 2.7.18 from source | AOSP-9 release tooling is Python 2. Built with `-std=gnu17` to dodge gcc-15 treating `bool`/`true` as C23 keywords. |
| ImageMagick | the boot animation needs `convert` |
| initrd download retries | one un-retried `curl` failed a whole build on a network blip |
| disable ClearKey DRM | broken in this LineageOS-16 tree; unnecessary for boot |

**The general lesson:** "host too new" failures are mechanical and fixable one at a time. Reach for a
container only after a real blocker, not in anticipation of one.

---

## 6. How it was installed

### 6.1 The plan that didn't survive

Standard recipe: flash TWRP (a recovery environment), format `/data`, push images, flash boot.

**TWRP 3.7.0 and 3.6.2 both hang on this tablet.** So none of that was available.

### 6.2 The recovery trap — worth understanding

`fastboot reboot recovery` writes a *boot-recovery* flag to the **`misc`** partition. Recovery is
supposed to clear that flag once it starts. TWRP hung before clearing it — so **every subsequent boot
went back to the hanging recovery**, including a plain power-button press. The tablet looked bricked.

Escape: an **Android phone as the fastboot host** (the *Bugjaeger* app over USB-C OTG), because the
Windows PC couldn't talk to the bootloader at all. Then:

```
fastboot erase misc
fastboot reboot
```

Nothing had been written to boot/system/vendor; the original ROM booted. **`misc` is a mode flag, not
data — erasing it is how you break a recovery loop.**

### 6.3 What actually worked

Installing with no recovery at all, using Halium's own initrd:

1. `fastboot boot halium-boot.img` from the phone — **boots without flashing anything**. Zero risk.
2. The Halium initrd, finding no rootfs, drops into a **debug shell**: it brings up USB networking and
   listens on **telnet 192.168.2.15:23**.
3. Back up the original partitions over that link (read-only, md5-verified).
4. Create the Ubuntu filesystem. The initrd's kernel has **ext4 only and no `mkfs`**, so: build a
   256 MiB ext4 *seed* on the PC, write it to `userdata`, then `resize2fs` it to the full 50.7 GB
   on-device.
   > The device's `e2fsprogs` is **1.43.4** (2017). A modern `mkfs.ext4` enables features
   > (`metadata_csum`, `64bit`, `orphan_file`) that old tools cannot mount. Any filesystem built on the
   > PC for this device must disable them.
5. Stream both OS images over the telnet link with `nc`, md5-verify.
6. `dd` `halium-boot.img` onto `boot`, reboot.

**Result:** Ubuntu Touch booted and SSH worked — but the screen stayed black.

### 6.4 The black screen: an empty `vendor`

`/android/vendor` was an empty ext4. PixelExperience kept its vendor inside the retrofit `super`
container, so the physical `vendor` partition held nothing. No driver blobs → the compositor aborted →
no display.

Fix: build `vendor.img` and `dd` it to `p14`. Display, touch and GPU came up immediately — Mir on
Adreno 512 at 1200×1920.

This is also the point of no return: overwriting `vendor` broke PixelExperience's dynamic layout, so
going back to Android now needs a full ROM reflash, not a restore.

---

## 7. Bring-up: every component, what broke, why

### 7.1 Audio — the speakers were never switched on

Sound worked but was inaudibly quiet. The vendor's mixer configuration
(`/vendor/etc/mixer_paths.xml`) describes audio routes; the speaker amplifier path simply wasn't being
enabled. Patching that file gave full volume.

*Lesson:* on Halium, "audio doesn't work" is usually routing, not drivers.

### 7.2 Screen, power button and brightness — two independent faults

The tablet would reach the UI, then the screen would die and the power button would do nothing.

**Fault 1 — repowerd waiting for a sensor that doesn't exist.** The 16.04 repowerd picks a proximity
backend in this order:

```
UbuntuProximitySensor   →   SensorfwProximitySensor   →   Null
```

The Ubuntu/Android backend doesn't *fail* on a device with no proximity sensor — it **blocks forever**
waiting for Android's `sensorservice` on binder. Blocked, repowerd never registers its screen
interface, so nothing can turn the display on or off.

**Fault 2 — the brightness scale.** This panel's `max_brightness` is **4095**. repowerd shipped no
config for `clover`, so it used 8-bit defaults (max 255, default 102, dim 10) — every one of them under
2.5% on this panel. Combined with a stored user brightness of **0**, the panel powered on with the
backlight off. Indistinguishable from a dead screen.

> **This one was findable much earlier.** The panel-power flag was being read, but never the backlight
> value next to it. "Screen is off" and "screen is on at brightness zero" looked identical for hours.
> Measure the whole chain, not one link in it.

Fixed with `config-clover.xml` (min 40, **max 4095**, default 1640, dim 100).

### 7.3 Rotation — the one-client rule, and why we upgraded the whole OS

Rotation needs `sensorfw` to read the accelerometer. Two obstacles.

**The sensors never calibrated.** The HAL reads factory calibration from `/persist`, which was never
mounted into the container. Fixed by mounting it — but note the image had to be patched to *contain*
the mountpoint, done the safe way: copy, modify the copy, `e2fsck`, rename.

**The vendor sensors HAL allows exactly ONE client.** Android's `sensorservice` — which repowerd needed
kept alive (§7.2) — owned it. sensorfw got `PERMISSION_DENIED`. So:

- keep `sensorservice` → screen works, rotation impossible
- kill it → rotation works, screen becomes unwakeable

A genuine architectural conflict with no local fix.

**The question that broke the deadlock** was the owner's: *"there are a zillion working Ubuntu Touch
devices — how do they do it?"* Checking a working device (Redmi Note 7, same SoC) showed that current
repowerd **reverses the backend order** — sensorfw first, Android never needed:

| | our 16.04 repowerd | 24.04 repowerd |
|---|---|---|
| links Android/binder sensor API | yes | **not at all** |
| proximity order | Ubuntu/binder **first** | **sensorfw → Null** |

So the fix was not a clever workaround but **upgrading Ubuntu Touch to 24.04**, where the conflict
doesn't exist. sensorfw becomes the single HAL client; Android's `sensorservice` is never started.

> **The rule this bought:** before engineering around a "fundamental" conflict, check how the
> mainstream does it. If everyone else's device works, you are fighting your own configuration.

The upgrade itself was low-risk by design: build the new Ubuntu image as a *new file*, keep the old one
as `rootfs.img.xenial`, swap two names. Rollback is two renames.

One more piece: on 24.04 sensorfw gates each sensor behind an `[available]` list, so the accelerometer
must be declared enabled via a **conf.d drop-in** (not by replacing the config, which breaks other
things).

### 7.4 Camera, part 1 — two device nodes with the wrong permissions

The camera app aborted seconds after opening. The last message before the crash:

```
gralloc-mapper is missing
```

That string lives in Android's own `libui.so`. When `IMapper::getService()` fails, AOSP calls
`LOG_ALWAYS_FATAL` — an unconditional `abort()`. Everything it needed *was* present: the passthrough
mapper library, its VINTF declaration, all ten dependencies.

The actual cause:

```
crw-rw-rw-  /dev/binder       ← fine
crw-------  /dev/hwbinder     ← root only
crw-------  /dev/vndbinder    ← root only
```

Apps run as uid 32011. HIDL needs **hwbinder**. `/android/ueventd.rc` specifies `0666` for all three —
the modes just never got applied on this port. No AppArmor denial appeared because the profile already
allowed those nodes; it was a plain Unix permission failure.

Fixed with a udev rule **and** a boot service (these nodes appear very early, so a udev rule alone can't
be trusted). Verified honestly: permissions were broken back to `0600` by hand and the unit restored
them.

Result: no more crashes, and the HAL started a stream. But the picture was still black.

### 7.5 Camera, part 2 — a directory that was never built

Nothing could be seen from the PC, so the first job was **instruments**, not theories:

- **Hold the display on.** `keepDisplayOn` is released the moment the calling D-Bus connection closes,
  so `busctl call` lights the screen for milliseconds. A small script that calls it and then *sleeps*
  holds it properly.
- **Dismiss the greeter** (`HideGreeter`) and **prove the app is focused** (`isPidFocused`) — with the
  screen off or the greeter up, Lomiri suspends apps and a test measures nothing.
- **Have QML screenshot itself.** `grabToImage()` produced a PNG of the rendered viewfinder, which
  could be pulled to the PC and measured.

That last one turned opinion into fact. The video rectangle was correctly sized and letterboxed, and
**all 93,000 sampled pixels were exactly RGB(0,0,0), with zero variance**. A dark room still produces
sensor noise; mathematically uniform zero is *no data*.

Then `logcat` named the cause:

```
E/vndksupport: Could not load /vendor/lib/hw/android.hardware.graphics.mapper@2.0-impl.so
               from sphal namespace: dlopen failed:
               library "android.hardware.graphics.mapper@2.0.so" not found.
F/Gralloc2: gralloc-mapper is missing
F/DEBUG: #05 /vendor/lib/hw/camera.sdm660.so (qcamera::QCameraGrallocMemory::allocate+832)
```

The same fatal message as before — but in a **32-bit** process (`/system/lib`, not `lib64`). The
linker configuration explains it exactly:

```
namespace.sphal.link.vndk.shared_libs = … android.hardware.graphics.mapper@2.0.so …
namespace.vndk.search.paths         += /system/${LIB}/vndk-sp-28
```

| | |
|---|---|
| `/system/lib64/vndk-sp-28/` | exists, 31 libraries |
| `/system/lib/vndk-sp-28/` | **did not exist at all** |

So 64-bit resolved and 32-bit could not. The library was never missing from the device — it sits in
`/system/lib`, a directory that namespace is **not permitted to search**. Our Halium build simply never
populated the 32-bit VNDK-SP directory.

This also explains why the permissions fix repaired the *crash* but not the *picture*: it gave the
64-bit app its mapper; the 32-bit camera HAL never had one.

Fix: create `/system/lib/vndk-sp-28/` with the 25 libraries that have 32-bit builds (the 6 missing are
all RenderScript, irrelevant here). Same measurement afterwards:

| | min | max | mean | stddev | non-zero |
|---|---|---|---|---|---|
| before | 0 | 0 | 0.00 | 0.00 | 0.00% |
| after | 0 | 255 | 138.67 | 67.05 | 96.48% |

### 7.6 Browser, Bluetooth, desktop apps

- **Morph crashed on video.** Hardware-accelerated video decode through libhybris was unstable; forcing
  software decode via a systemd *user* drop-in on the app's unit fixed it.
- **Bluetooth** (`bluebinder`) crash-looped every ~61 s. Disabling wasn't enough — `bluetooth.service`
  pulls it back in, so it had to be **masked**. Bluetooth is therefore untested, by choice.
- **Libertine** gives real desktop apps (Remmina, VLC, Standard Notes). No GPU inside the container, so
  rendering is software.

---

## 8. The hurdles, by category

**Host too new.** An Android 9 build system on a 2026 Linux. Mechanical; five shims.

**Device-specific traps.** TWRP hangs; the `misc` recovery loop; the PC cannot drive the bootloader's
fastboot (a phone can); EDL is authentication-locked; ancient on-device `e2fsprogs`.

**Architectural conflicts.** One kernel and one HAL shared by two systems: the single-client sensors
HAL, and repowerd's backend ordering. The sensor one could not be solved at our level — the answer was
to move to a version where it doesn't exist.

**Missing pieces in our own build.** Both camera faults, and the empty `vendor`. These are the
interesting ones: nothing was *broken*, something was simply *absent* — a permission never applied, a
directory never created.

**Self-inflicted.** Recorded deliberately, because they cost the most time:

- A supervised job that could crash-loop → Ubuntu Touch's **watchdog reboots the whole device** when a
  job hits its respawn limit. Twice.
- Reading panel power but never backlight, so an invisible screen looked like a display bug for hours.
- Concluding "the app never starts the preview" from a measurement polluted by leftover test processes.
- Diagnosing a broken container when the tablet merely hadn't rejoined Wi-Fi.

---

## 9. Rules earned the hard way

1. **Never let a job crash-loop.** The watchdog reboots the device. Use one-shot units, never
   `Restart=`/`respawn`, for anything touching the Android container.
2. **Check what starts a service before disabling it.** `bluebinder` came straight back; masking was
   required.
3. **Verify the capability, not a proxy for it.** "repowerd answers D-Bus" is not "the screen lights
   up". Read the actual value at the end of the chain.
4. **Build the instrument before forming the theory.** Three plausible camera hypotheses died the
   moment there was a real screenshot and a pixel histogram.
5. **Check how the mainstream does it** before engineering around a "fundamental" conflict.
6. **Modify a copy, then rename.** Every image change is reversible because of this.
7. **Back up before changing, and verify the backup** — same md5 on both sides, before and after.
8. **A string in a binary is not a symbol.** `SLOT(onPreviewReady())` embeds that literal at the *call*
   site; `nm` showed the slot doesn't exist. Check the symbol table.
9. **Kill leftovers before measuring.** Two camera clients collide (`rc = -16`, "already open") and
   produce confident nonsense.
10. **"Unreachable" is not "broken."** One failed probe is not a diagnosis.

---

## 10. Working on it

**Access.** `ssh phablet@<ip>` over Wi-Fi is the reliable route. `adb` needs Developer Mode re-armed
after every boot. If Ubuntu won't boot, the Halium initrd's telnet shell over USB is the rescue path —
it is how the OS was installed in the first place.

**Seeing the screen.** You can't screenshot this device from a PC: Mir 1.8 has no `wlr-screencopy`,
`mirscreencast` is refused, and the rootfs is read-only so `grim` can't be installed. The workaround —
hold the display on, dismiss the greeter, confirm focus, have QML grab itself, measure the pixels — is
in [`../scripts/device/camera-probe/`](../scripts/device/camera-probe/).

**Changing the Android image.** The `/android` loop device is mounted **write-protected**;
`mount -o remount,rw` fails. Copy the image, mount the copy, modify, `e2fsck`, swap names, reboot.
[`../device-fixes/clover-vndk-sp-32.sh`](../device-fixes/clover-vndk-sp-32.sh) is a worked example.

**Rollback.** Every risky change has a two-rename escape: the Ubuntu rootfs, the Android image, and the
16.04 system all keep their predecessors.

---

## 11. State and what's left

**Working:** display, touch, GPU, Wi-Fi, audio, battery reading, charging while off, screen
dim/blank/wake with the correct backlight range, brightness slider, all 30 sensors, rotation, Morph
browser, Libertine desktop apps, **camera viewfinder**.

**Open:**

- **Camera stills** — unverified. The viewfinder works, but the plugin connects to a slot
  (`AalImageCaptureControl::onPreviewReady()`) that doesn't exist in this build, and upstream uses that
  signal to complete the JPEG save. The shutter may not work.
- **Bluetooth** — deliberately masked after crash-looping; never tested.
- **Suspend / battery life** — the largest untouched area. Needs the owner present and an agreed escape
  route, since a bad suspend can make a device unwakeable.
