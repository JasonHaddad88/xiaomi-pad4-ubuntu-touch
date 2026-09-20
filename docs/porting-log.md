# Porting log

Newest entries at the top. Record decisions, what we tried, errors, and fixes — so we can backtrack.

---

## 2026-09-20 (cont.) — UPGRADED to Ubuntu Touch 24.04 (noble) — it boots

The 16.04 rootfs was replaced with `24.04-1.x/arm64/android9plus/stable`, keeping our Halium 9
`halium-boot` and `system.img` and the vendor partition. **The device boots 24.04 and, on first
inspection, everything works except rotation.**

### How it was done
1. Rootfs verified first: size matched the index exactly, `xz -t` clean, and the detached `.asc`
   gave a **good signature from UBports' image-signing key**. (The pool filename is *not* the file's
   sha256 — an assumption that produced a false "mismatch" scare.)
2. Target image created **on the device** (`fallocate 4G` + the device's own `mkfs.ext4`), because
   kernel 4.4 cannot mount an image made by a modern mkfs.
3. The tablet has **no `xz`**, so streaming `tar -xJf` failed instantly. The link turned out to run at
   **15 MB/s**, so the fix was to decompress on the PC and stream the raw 2.4 GB tar — about 3 minutes.
4. Post-install: `systemctl enable ssh.service usb-tethering.service`, symlinks verified by hand.
5. Device fixes re-applied into the new rootfs: `/persist -> /mnt/vendor/persist`, `clover.yaml`
   (the 24.04 variant, **without** the `SensorfwConfig` line), and `config-clover.xml` (4095 backlight).
6. `e2fsck -fn` clean, then swap: old rootfs kept as **`/userdata/rootfs.img.xenial`**.

### Two traps caught before they bit
- **`PasswordAuthentication=no`** in 24.04's `/etc/ssh/sshd_config.d/50-lxc-android-config.conf`.
  Booting that with only password auth would have locked us out. Set to `yes`, *and* an SSH public key
  was installed into the **persistent** home (`/userdata/user-data/phablet/.ssh`, shared by both
  rootfs versions) and **verified working against the live 16.04 system before the swap**.
- The `phablet` user is not in `/etc/passwd` at all — Ubuntu Touch keeps it in **extrausers**, which is
  bind-mounted from userdata, so the account and its password survive a rootfs swap untouched.

### First boot
The very first boot ended in Qualcomm **crashdump mode** (`05C6:900E`, "QUSB_BULK") — no OS. A forced
power-off and retry booted 24.04 fine, so it was a one-off. Worth remembering: that state looks
alarming but nothing was lost, because the swap only touches one file inside userdata.

### Access changed
24.04 presents a different USB gadget: 16.04 used `0FCE:7169` (RNDIS, 10.15.19.82); 24.04 came up as
`VID_1209&PID_0004` RNDIS (Windows: **Code 28, no driver**) and, once Developer Mode was enabled,
as **MTP + ADB**. So the old `ssh phablet@10.15.19.82` route is gone; adb is the new channel.

### Still to verify
Rotation — the whole point of the upgrade. The claim to test: 24.04's repowerd does not link
platform-api at all, so it cannot block on binder `sensorservice`, which leaves sensorfw as the only
client of the single-poller sensors HAL.

---

## 2026-09-20 (cont.) - WHY working devices rotate: they run a newer Ubuntu Touch

Prompted by <https://devices.ubuntu-touch.io/device/amar-row-wifi/> (Lenovo Tab M10 HD 2nd Gen) which
has rotation *and* automatic brightness working. It runs **Ubuntu Touch 24.04 (noble)**; we run
**16.04 (xenial)**. That single difference explains the wall we hit.

**The proof is in repowerd's source.** Our build is from the `xenial_-_android9` branch, where
`DefaultDaemonConfig::the_proximity_sensor()` is:

```cpp
try { proximity_sensor = std::make_shared<UbuntuProximitySensor>(...); return ...; }   // FIRST
catch (...) { log("Failed to create UbuntuProximitySensor"); log("Trying SensorfwProximitySensor"); }
```

The **Ubuntu/UAL backend is tried first** - and on a device with no proximity sensor it does not
throw, it blocks forever in `Waiting for service 'sensorservice' on /dev/binder`. So repowerd never
reaches the sensorfw path, never registers `com.canonical.Unity.Screen`, and the power button dies.
That is why forcing `proximitysensor=True` in sensorfw changed nothing: the code never gets there.

Current upstream (GitLab `ubports/development/core/repowerd`, `main` - what 24.04 ships) has the
order **reversed**:

```cpp
try { proximity_sensor = std::make_shared<SensorfwProximitySensor>(...); return ...; }  // FIRST now
catch (...) { logWarning("Failed to create SensorfwProximitySensor: %s", ...); }
```

With sensorfw first, repowerd never touches android's sensorservice, sensorfw is the only client of
the vendor sensors HAL (which allows exactly one poller), and rotation and screen control coexist -
exactly what the Lenovo tablet demonstrates.

**Upgrade path exists for this hardware.** UBports publishes `android9plus` channels - Halium 9 *and
newer* - including `20.04/arm64/android9plus/stable`, `24.04-1.x/arm64/android9plus/stable` (32
devices, `amar_row_wifi` among them) and `26.04-1.x/arm64/android9plus/daily`. The 24.04 image
splits into:

| file | size | device-specific? |
|---|---|---|
| `rootfs-*.tar.xz` | 500 MB | **no** - this is the Ubuntu 24.04 userspace we would take |
| `device-*.tar.xz` | 126 MB | yes - we build our own (`system.img`) |
| `boot-*.tar.xz` | 71 MB | yes - we build our own (`halium-boot.img`) |

So the route to rotation is not more config archaeology on xenial: it is replacing `/userdata/rootfs.img`
with the 24.04 android9plus rootfs, keeping our Halium 9 boot and system images. That is Phase 5 of
the roadmap, arriving earlier than planned.

Caveats to plan for: 24.04 uses **systemd**, so the upstart jobs in `device-fixes/` become obsolete
(most also become unnecessary - the new repowerd needs no `sensorservice`); the vendor-partition
audio fix is unaffected; `/persist` symlink, the deviceinfo entry and the backlight config must be
re-applied in the new rootfs. Rollback is a rename, since the old `rootfs.img` stays on the device.

---

## 2026-09-20 (cont.) - ROTATION: blocked by repowerd, not by the sensors

The sensors are fine. The blocker is a hard conflict, now measured rather than guessed:

**The vendor sensors HAL allows exactly ONE poller.** With android's `sensorservice` running,
sensorfw's poll returns result 2 (`PERMISSION_DENIED` in HIDL sensors 1.0) - 23k failures in one
boot. Stop sensorservice and restart sensorfw and the failures drop to **0**, the accelerometer
plugin loads, and rotation data flows. There is no sensors@2.0/2.1 interface on this device
(`Could not find service hosting interface android.hardware.sensors@2.1::ISensors/default`), so the
multi-client FMQ path is not available.

**But repowerd cannot run without sensorservice.** It uses libubuntu_application_api for
`ua_sensors_light_*` / `ua_sensors_proximity_*` only - its display control is pure D-Bus
(`com.canonical.Unity.Screen`) - and this tablet has **no proximity sensor**, so repowerd's sensorfw
backend fails and it falls through to the UAL one, which does not fail: it blocks forever in
`Waiting for service 'sensorservice' on /dev/binder`, never registering Unity.Screen. Dead power
button, unwakeable screen.

So it is strictly one or the other, and screen control wins.

### What was tried
- **`proximitysensor=True`** in a sensorfw `[available]` override: sensorfw then *offers* proximity
  (`loadPlugin` returns true), but repowerd still went to the UAL backend. Removed again.
- **`/etc/deviceinfo/devices/clover.yaml`**: the device had no deviceinfo entry at all, so repowerd
  logged `No device yaml config found!` and the generic `halium` profile applied - which sets
  `PrimaryOrientation: Portrait` and **no `SupportedOrientations`**, so Lomiri is never told rotation
  is allowed. The file silences that message and declares all four orientations. **Kept** - it is
  correct regardless, and needed whenever rotation does work.
- **`UBUNTU_PLATFORM_API_BACKEND=test`** to keep repowerd's UAL calls off binder. Note for next time:
  upstart on this device ignores both `/etc/init/repowerd.override` and edits to `repowerd.conf`
  until a **reboot** - `initctl reload-configuration` does not help, and the env var silently never
  reaches the process, which invalidated two earlier attempts. After a reboot the variable *was*
  delivered, but repowerd still failed to register Unity.Screen, so the test backend is not a way
  out. Reverted.

### Also fixed along the way
The stored `com.ubuntu.touch.system brightness` had gone back to **0**, which is why the screen kept
coming back black even with a correct backlight range: the panel powers on at brightness zero. Set to
1739 and confirmed it survives a reboot. Worth checking first whenever "the screen will not come on".

### Where rotation stands
Needs repowerd to stop depending on android sensors. Options, in order of sanity: a repowerd build
with a working sensorfw backend (upstream has `xenial_-_sensorfw`); patching out the UAL proximity
path; or a minimal stub that registers `sensorservice` on binder without touching the HAL. None of
these belong on a device someone is using without being asked first.

---

## 2026-09-20 (cont.) - THE ACTUAL ROOT CAUSES: a 4095 backlight and a missing proximity sensor

**Reported:** "I can use the tablet for a couple of seconds, then the screen turns off, and I am not
able to turn the screen back on with the power button... rotation and brightness do not work."

Two independent root causes, both finally identified properly:

### 1. The backlight range
`/sys/class/leds/lcd-backlight` has **`max_brightness = 4095`**. repowerd ships device configs for
mako/flo/grouper/hammerhead but none for clover, so it logged `No device yaml config found!` and used
its 8-bit defaults - dim 10, min 10, max 255, default 102 - every one of which is under 2.5% on this
panel. The stored user brightness was **0**. So the panel powered on with the backlight at zero: the
screen looked off, the power button looked dead, and the slider did nothing. Fixed with
`/usr/share/repowerd/device-configs/config-clover.xml` (min 40, max 4095, default 1640, dim 100).

**This one was findable much earlier.** `panel_power_on` told me the panel state but I never once read
the backlight value next to it, so "screen is off" and "screen is on at brightness 0" looked
identical for hours.

### 2. Why sensorservice must never be killed
`strings /usr/sbin/repowerd` shows the proximity backend order:
`SensorfwProximitySensor -> UbuntuProximitySensor -> NullProximitySensor`. This tablet has **no
proximity sensor** (`dumpsys sensorservice | grep -c proximity` = 0), so the sensorfw backend fails
and repowerd falls through to the Ubuntu/UAL one - which does not fail, it blocks forever waiting for
binder `sensorservice`. Blocked, repowerd never registers `com.canonical.Unity.Screen`.

Worse: kill sensorservice after repowerd bound to it and repowerd *exits*, upstart respawns it, and
it blocks again. The previous design killed sensorservice deliberately to free the HAL for sensorfw -
producing precisely the reported symptom: a few usable seconds, screen off, random returns.

**Fix:** start sensorservice once and keep it (supervised by a shell loop upstart can never see exit,
because the watchdog reboots the device on a respawn-limit hit). sensorfw runs alongside as a second
HAL client; the HAL restarts a few times while both attach, then settles.

**Verified after a clean reboot:** backlight 1640/4095 with the panel on, dims to 100, blanks on the
idle timeout, wake restores 1640; repowerd on a single pid for the whole watch, never restarted;
sensorservice up; sensorfw serving the accelerometer; HAL settled at 7 starts; zero watchdog hits.

### Rules this cost us
- **Measure the whole signal chain, not one link.** Panel power and backlight level are different
  things; reading only the first made an invisible screen look like a display-power bug for hours.
- A port needs its **device config** (brightness range) as much as its drivers - check for
  `No device yaml config found!` early.
- When a daemon "needs" something odd, read its backend-selection strings instead of theorising.

---

## 2026-09-20 (cont.) — SOLVED: rotation and screen turn-off together, the stock way

**The question that unstuck this:** "how do normal UBTouch devices work? there are a zillion working
UBTouch devices."

They do it with **one** HAL client:

```
sensors HAL  <--  sensorfw  <--D-Bus--  Lomiri (rotation), repowerd (light/proximity)
```

`strings /usr/sbin/repowerd` shows `SensorfwLightSensor`, `SensorfwProximitySensor`, `Sensorfw` and
`com.nokia.SensorService` — sensorfw's D-Bus name. There is **no android sensorservice backend** in
repowerd. Android's `/system/bin/sensorservice` is not part of a normal port at all.

So the original "fix #1" was a misdiagnosis: what made screen turn-off work back then was the
`initctl restart repowerd` sitting in that job's `post-start`, not the sensorservice next to it. I
then built an elaborate HAL-conflict problem on top of a daemon that should never have been running -
that second HAL client is what caused the crash-loops, the boot loops and the dead power button.

**The one real twist on this device:** the repowerd in this rootfs still binds binder `sensorservice`
at startup. Without it, it sits in `Waiting for service 'sensorservice' on /dev/binder` forever
(confirmed: the waiting pid in logcat maps to `/usr/sbin/repowerd` on the host), never registers
`com.canonical.Unity.Screen`, and the display can be neither blanked nor woken. But it only needs it
long enough to **bind** — afterwards it serves the screen fine with sensorservice gone.

**Final design** (`sensor-bringup.conf`, one-shot task on `started repowerd`): ensure `/persist`
reaches the container → wait for the HAL → start sensorservice → **wait until
`com.canonical.Unity.Screen` is actually registered** → kill sensorservice → restart sensorfw so it
owns the HAL again. If screen control never appears it leaves sensorservice running instead, because
a working power button beats rotation.

**Verified after a clean reboot, no manual steps:** Unity.Screen registered by ~74s · HAL restarts
settle at 4 then freeze · sensorservice gone · sensorfw serving the accelerometer · panel blanks on
the idle timeout and wakes on command · zero watchdog hits across a 5-minute watch.

### Rules this cost us
- **Ask how the working majority does it before engineering a workaround.** Every UT device rotates
  and blanks its screen; that fact alone said my architecture was wrong, and one `strings` on the
  binary proved it in seconds.
- **Verify the user-visible capability, not a proxy.** "repowerd answers a D-Bus introspect" is not
  "the screen can be powered on". The final job polls for the real service before proceeding.
- **Never let an upstart job flap on Ubuntu Touch** - the watchdog reboots the device.
- When a baseline worked and a feature has caused rounds of regressions, revert to the baseline
  first, then re-approach - do not ship another variation onto a device someone is using.

---

## 2026-09-20 (cont.) — REVERTED the rotation work; back to a seamless device

**Reported:** "the screen is reaching Ubuntu and going black, and the power button is not turning the
screen on... for a while it was almost seamless (before the rotation thing)."

That last clause was the answer. Every variation I tried after enabling the sensors was worse than
the state before them, so the entire rotation change set was reverted:

- `/persist` symlink back to the stock (dangling) `/android/persist`
- pristine `android-rootfs.img` restored; the patched one kept as `android-rootfs.img.persistfix`
- `sensorfw.override` restored to stock (md5 `85f53f6f32a513f96139c5ef7bfb814d`)

**Kept**, because they are unrelated to rotation and each fixes a real fault:
- the audio mixer patch (md5 `84c1545219312a21f8a5b0e26f149c16`)
- `lxc-android-config.override` — stops plugged-in reboots leaving `/userdata` read-only
- `audiosystem-passthrough` disabled — stopped the session watchdog rebooting the device
- `sensorservice.conf`, now as a shell loop upstart can never see exit (watchdog-safe)

**Verified over a 5-minute watch after reboot:** sensorservice registered throughout · repowerd
pid stable, `com.canonical.Unity.Screen` up · zero new watchdog hits · panel blanks on the normal
idle timeout and wakes on command · audio patch intact.

**The lesson, bluntly:** the user told me twice that things had been working before this feature. I
kept iterating on the feature instead of restoring the known-good state and re-approaching from
there. When a working baseline exists and a change has produced several rounds of regressions, revert
to the baseline first, then investigate - rather than shipping another variation onto a device
someone depends on.

**If rotation is attempted again**, the HAL conflict has to be solved first, not worked around. The
open question worth investigating: whether `sensorfw` can be pointed at android's `sensorservice`
instead of opening the sensors HAL itself, so there is only ever one HAL client.

---

## 2026-09-20 (cont.) — RESOLUTION: stability over cleverness (screen-off kept, rotation parked)

**Reported:** "boots to UI, it rotates, yet after around 16 seconds the screen turns off... another
time the screen went off on the UBUNTU logo, then the tablet rebooted itself. Both times the power
button was not working."

Three independent faults were stacked on top of each other:

1. **The ~16s screen-off was self-inflicted.** My bring-up task started sensorservice, let repowerd
   bind, then *killed* sensorservice 15s later to free the HAL for rotation. Killing it blanked the
   display and left repowerd unable to drive it — power button dead.
2. **A second, unrelated reboot source:** `session-watchdog: 'audiosystem-passthrough' hit respawn
   limit - asking logind to reboot`. It bridges cellular call audio and this is a WiFi-only tablet,
   so it crash-loops forever. Disabled via a session override. (My earlier claim that the reboots
   were fixed was wrong because I only checked for *sensorservice* watchdog hits, not all of them —
   `grep "hit respawn limit"` with no job filter would have shown this immediately.)
3. **The HAL conflict is not workable-around.** `sensorservice` and `sensorfw` cannot both hold the
   sensors HAL; every scheme that tried to give both (kill-after-bind, retrigger-on-repowerd) traded
   one broken feature for another.

**Decision:** take the trade-off explicitly instead of engineering around it. `sensorfw` is disabled
(`manual` in `/etc/init/sensorfw.override`), sensorservice runs permanently under a shell loop that
upstart can never see exit, and rotation is parked. This matches the priority originally set for this
port — screen turn-off first. Swapping back to rotation is one line, documented in
`device-fixes/README.md`.

**Measured after the change (5+ minute watch):** sensorservice pid stable, never restarted · repowerd
and `com.canonical.Unity.Screen` up throughout · **HAL started once** (was 71+ and climbing) · zero
new watchdog hits · display wakes on command.

### Rules this cost us
- **Never let an upstart job flap on Ubuntu Touch.** The watchdog reboots the device. If a process
  must be supervised, wrap it in a `while true` shell loop so upstart's main process never exits.
- **When checking whether reboots stopped, grep for *all* respawn-limit hits, not the job you were
  working on.** A second culprit hid behind the first for hours.
- **Verify the actual user-visible capability, not a proxy for it.** "repowerd answers a D-Bus
  introspect" is not "repowerd can power the panel on". Check `panel_power_on` transitions.
- Prefer an explicit, documented trade-off over a clever mechanism that makes both features flaky.

---

## 2026-09-20 (cont.) — INCIDENT: my sensorservice job was rebooting the tablet

**Symptom (reported):** "on boot the screen does not pass the Ubuntu logo always, and when it does,
it flickers then goes off."

**Cause — the single most important lesson of this port:**

```
watchdog: 'sensorservice' (instance '') hit respawn limit - rebooting
```

**Ubuntu Touch's watchdog reboots the whole device when an upstart job hits its respawn limit.** My
`sensorservice.conf` used `exec lxc-attach ... /system/bin/sensorservice` + `respawn`. sensorservice
crash-loops whenever the sensors HAL goes away (`Abort due to ISensors hidl service failure, detail:
Status(EX_TRANSACTION_FAILED): 'DEAD_OBJECT'`), so the job flapped, hit the limit, and the watchdog
rebooted the tablet — over and over. The "flicker then off" was the display dying as it rebooted.

A second bug made it worse: `post-start` restarted repowerd on **every** respawn, so repowerd was
restarted **60 times in two hours**, tearing the display stack down each time.

**Why sensorservice crash-loops:** `sensorservice` and `sensorfw` cannot both hold the sensors HAL.
With both running, `vendor.sensors-hal-1-0` exits with status 255 every ~5s (71 times in one boot).
Proof: the HAL was stable from 461s to 806s — exactly the window when sensorservice was not running —
and started dying again the moment sensorservice was launched. Stopping sensorfw and running
sensorservice alone produced no abort and one HAL restart instead of ~12/minute.

**Fix:** repowerd only needs sensorservice to exist *when it starts*; it keeps working and keeps
answering on `com.canonical.Unity.Screen` after sensorservice disappears. So `sensor-bringup.conf` is
a one-shot **task** that starts sensorservice, kicks repowerd so it binds, then kills sensorservice
and hands the HAL back to sensorfw. Screen-off and rotation now coexist.

**Measured before → after (per boot):** repowerd restarts 60 → 1 · HAL restarts ~71 and climbing → 4,
then frozen · watchdog reboots → none across a 5-minute watch.

### Rules this cost us
- **Never supervise an Android container service with an upstart `respawn` job on Ubuntu Touch.** A
  flapping job does not just fail, it *reboots the device*. Use a one-shot `task`, or android init.
- **Never restart repowerd from a per-start hook.** Once per boot, or the display churns.
- `initctl list` is the first thing to check when a job "did not work" — `stop/waiting` means it never
  started or upstart gave up, which is a completely different bug from the job doing the wrong thing.
- A wrong turn: I first blamed a duplicate repowerd restart for tripping the respawn limit. It had
  not — `initctl restart` does not count toward it. Check the evidence before blaming your own diff.

---

## 2026-09-20 (cont.) — FIX: rotation (sensors), and the charger-mode boot trap

**Symptom:** no rotation. `dumpsys sensorservice` → **"No Sensors on the device"**;
`vendor.sensors` / `sensors.qcom` exited with status 0 every ~10s.

**Diagnosis:** not firmware. logcat gave the exact gate:

```
libsensor1: check_sensors_enabled: open error: settings file "/persist/sensors/sensors_settings", errno 2
libsensor1: check_sensors_enabled: Sensors enabled = false
libsensor1: wait_for_service: sensors setting disabled sensors
Sensors : sns_main.c(447):Timeout waiting for SMGR service. Exit sensors daemon!
```

The daemon refuses to contact SMGR unless it can read `/persist/sensors/sensors_settings`.
`/persist` never reached the container because (1) the rootfs ships `/persist -> /android/persist`,
which does not exist — the partition (`mmcblk0p48`) is mounted at `/mnt/vendor/persist`; and (2) our
`system.img` has no `persist` directory, so LXC's own
`lxc.mount.entry = /persist persist bind bind,optional` silently skipped it.

**Red herring:** `sensors-ssc: slpi_load_fw: SLPI image loading failed` and an empty
`/vendor/firmware_mnt`. There is no SLPI image on this device at all — the SSC runs on the **ADSP**
(`sysmon-qmi: Connection established between QMI handle and adsp's SSCTL service`). Chasing missing
firmware would have been wasted effort; the logcat gate was the real signal.

**Fix:** repoint the symlink, add an empty `/persist` mountpoint to the Android system image, and add
`/etc/init/android-persist.conf` (see `device-fixes/README.md` #3). The system image was modified as
an **unmounted copy** (`losetup` + `mount`, `e2fsck -fn` clean) and swapped in by rename, so the
pristine original remains as `/userdata/android-rootfs.img.orig` — reverting is one `mv`.
Result: **30 h/w sensors** (BMI120 accel + gyro, CM3232 light, ROHM hall effect) and rotation works.

**Ordering matters:** `sensorfw` connects to Android's `sensorservice` at startup — long before the
sensors exist — and then just logs `Poll failed status 2` forever. It must be restarted *after*
sensorservice, which is what the new job does.

### The charger-mode trap (this cost the most time)

After the first reboot rotation worked but **the power button no longer blanked the screen**. The
cause was not the sensor work at all. The tablet was plugged in, so the bootloader set
`androidboot.mode=charger` — and a plain reboot while plugged in is indistinguishable from a cold
charger insertion (`Power-on reason: Triggered from USB (USB charger insertion)` in both cases).
UT's stock `/etc/init/lxc-android-config.override` then does:

```sh
if [ "$(getprop ro.bootmode)" = "charger" ]; then
    echo u > /proc/sysrq-trigger      # emergency remount R/O — hits ALL filesystems
    initctl emit -n charger           # 'android' is never emitted
```

Consequences on every plugged-in reboot: `/userdata` (home, settings, logs) goes **read-only** —
which also made `scp` fail with a bare `dest open: Failure` — and every job that starts `on android`
(`repowerd`, `sensorfw`, both of our jobs) never runs, while the UI still comes up. `initctl list`
showing `repowerd stop/waiting` was the tell. Replaced the branch with a plain `initctl emit android`
(no off-charging UI on this port anyway); original kept as `.orig` on device and in `backups/`.

**Wrong turn worth recording:** I first blamed the duplicate `initctl restart repowerd` in my own new
job for tripping upstart's respawn limit. It hadn't — `initctl restart` doesn't count toward the
respawn limit, and repowerd was `stop/waiting` simply because the `android` event never fired.
**Rule: before blaming your own change, check `initctl list` / whether the job's start event fired.**

**Verified after a clean reboot with no manual commands:** 30 sensors, `repowerd`/`sensorfw`/
`sensorservice` running, `/userdata` read-write, no emergency remount. Note repowerd is restarted
several times in the first ~30-60s of boot while the sensor stack settles.

---

## 2026-09-20 (cont.) — FIX: loud audio (speakers were never switched on)

**Symptom:** sound worked but was very quiet. PulseAudio was innocent: sink at 100%, unmuted,
`Active Port: output-speaker`.

**Diagnosis:** the codec gains were already maxed (`RX1/RX2/RX3 Digital Volume = 84`), but the speaker
switches were off: `SPK: ZERO`, `WSA Spk Switch: ZERO`, `Ext Spk Switch: Off`. The vendor
`mixer_paths.xml` has exactly one `<path name="speaker">` and it is **empty** (line 1704), while
`speaker-protected` / `speaker-vbat` merely include that empty path - so selecting the speaker enables
nothing and playback leaks out of a weak fallback route.

**Fix:** `<ctl name="SPK" value="Switch" />` inside the `speaker` path of
`/android/vendor/etc/mixer_paths.xml` (see `device-fixes/README.md`). Confirmed loud, and it survives
reboot because the HAL re-applies the path on every route selection. Runtime equivalent for testing:
`lxc-attach --clear-env -n android -- /system/bin/tinymix SPK Switch`.

**Incident during the fix (lesson):** a WSL restart wiped `/tmp`, the `scp` of the patched file failed
silently, and the next command `cat`-ed a missing file over the config - leaving `mixer_paths.xml`
**empty** (md5 d41d8cd9...). Caught via checksum, restored from the on-device `.bak` (md5 back to
e3571247...). **Rule: verify the uploaded file on the device before overwriting anything, and do
upload+install in a single shell invocation.**

**Also confirmed working today:** brightness slider (fixed as a side effect of fix #1), and charging
while powered off (it charges on the Mi logo; only the Android charger UI is missing - deprioritised).

## 2026-09-20 — FIX: screen can be turned off (repowerd was stuck on Android `sensorservice`)

**Symptom:** pressing Power never blanked the display; `com.canonical.powerd` and `com.canonical.Unity.Screen`
had **no owner** on the system bus, so the UI had nothing to ask. `repowerd` ran but its log stopped right
after `SysfsBacklight: Using backlight /sys/class/leds/lcd-backlight`.

**Diagnosis:** `strace` on the stuck process showed the loop plainly:
`Waiting for service 'sensorservice' on '/dev/binder'` -> `Service sensorservice didn't start. Returning NULL`.
repowerd (2017.03) needs Android's framework-level **`sensorservice`** for proximity; Halium has no Android
framework to launch it, so repowerd never finished init. The binary *does* exist in our build
(`/android/system/bin/sensorservice`).

**Fix:** start it from Ubuntu's upstart - `device-fixes/sensorservice.conf` -> `/etc/init/sensorservice.conf`
(rootfs is ro: `mount -o remount,rw /`, install, `remount,ro`). Gotchas hit on the way:
- `lxc-attach` must use **`--clear-env`**, else the container inherits Ubuntu's `LD_LIBRARY_PATH` and the
  64-bit binary loads 32-bit libs (`libbinder.so is 32-bit instead of 64-bit`).
- The trigger is **`start on android`** (an *event* emitted by `lxc-android-config`), **not**
  `start on started android` - there is no upstart job named `android`.
- `post-start` restarts repowerd, since repowerd starts (and stalls) before sensorservice is up.

**Verified after reboot:** sensorservice running, repowerd owns both bus names, Power button blanks the screen.
Rotation still broken (deprioritised by user). Backups taken first: `backups/ut-working-2026-09-20/`
(ut-data.tgz + boot + vendor, all md5-verified).

## 2026-09-19 (cont.) — 🎉 DISPLAY + TOUCH WORK — Ubuntu Touch UI up on clover

Built `vendor.img` (`mka vendorimage`, 45 s — blobs were already staged; 800 MB sparse → `simg2img`), copied to
`/home/phablet` over scp, then as root: `lxc-stop -n android -k`, `umount /android/vendor`, `dd` → `mmcblk0p14`,
md5-verified (`2f318425…`), reboot. Result: Android HALs up (`composer@2.1`, `allocator@1.0/2.0`,
hwservicemanager), unity-system-compositor + Mir 1.8.1 render via **Adreno 512 / GLES 3.2** at **1200×1920**,
lightdm autologins `phablet`, **Lomiri UI appears and touch responds**. (PE13 dynamic layout now overwritten —
returning to PixelExperience = full ROM reflash.) Boot to network is slower now (~2–4 min) as the HALs load.

## 2026-09-19 (cont.) — 🎉 FIRST BOOT: Ubuntu Touch 16.04 runs on clover (SSH works; display not yet)

**No TWRP needed.** Both official TWRPs (3.7.0, 3.6.2) hang on this tablet even with `/data` wiped; our own
`halium-boot.img` (same 4.4 kernel family) boots fine — so the TWRP failure is TWRP-specific, not "old kernel".

**Method (all reproducible, tools in `scripts/device/`):**
1. Phone (Bugjaeger) → bootloader fastboot → `fastboot boot halium-boot.img` (temporary, writes nothing).
2. halium initrd (no rootfs yet) → debug mode: USB `18D1:D001`, serial `HALIUM_INITRD_DEBUG_TELNET_ON_PORT_23…`,
   telnet **192.168.2.15:23**, udhcpd. Windows: in Device Manager switch the device from the Android driver to
   **"USB Composite Device"** (usb.inf), then the child **RNDIS** → Network adapters → Microsoft → **Remote NDIS
   Compatible Device**. PC gets 192.168.2.x. (`tsh.sh` = send commands via `nc`.)
3. **Backups** (read-only, md5-verified) of PE13 `boot`, `persist`, `modemst1/2`, `fsg` → `backups/pe13-partitions/`
   (`pull.sh`).
4. Initrd kernel has **ext4 only (no f2fs)** and **no mkfs** → wrote a 256 MiB ext4 **seed** (built on PC with
   `-O ^metadata_csum,^64bit,^orphan_file,^metadata_csum_seed`) to `userdata`, then on-device `e2fsck -fy` +
   `resize2fs` → full 50.7 GB. (Device e2fsprogs = 1.43.4 — strip `orphan_file` from any PC-made ext4!)
5. Images built with **`halium-install -p ut16.04 -u 0000 -s -m img -tm`** (test mode = build only, no adb push;
   rootfs is **Ubuntu 16.04 xenial**). Streamed gz over `nc` (`send.sh`) → `/data/rootfs.img` +
   `/data/android-rootfs.img`, md5-verified.
6. `dd` `halium-boot.img` → `boot` (md5-verified), `reboot -f`.

**Result:** UT boots. USB tethering `0FCE:7169` (needs the same RNDIS driver pick) → tablet **10.15.19.82**, PC
10.15.19.100 → **`ssh phablet@10.15.19.82` (password `0000`)**. Kernel `4.4.153-HandsomeKernel+`, Android container
RUNNING (`getprop` → clover / 9), rootfs loop0 ro, system loop1, userdata ext4.

**Display blocker (next):** `/android/vendor` (= physical `mmcblk0p14`) is an **empty ext4** — PE13 keeps its vendor
inside the retrofit-dynamic super, so no HAL blobs → `unity-system-compositor` aborts (signal 6) → lightdm exits;
screen stays on the bootloader's Mi logo. Fix: `mka vendorimage` → **`vendor.img`** (Android 9 blobs, 800 MB, sparse)
built 2026-09-19; next step is writing it to `vendor` (p14). NOTE: that further breaks PE13's dynamic layout —
returning to PixelExperience then needs a full ROM reflash, not just restoring `boot`.

## 2026-09-19 — Recovery-loop incident + rescue via phone (Bugjaeger) ✅ — READ BEFORE FLASHING AGAIN

**What happened:** flashed official **TWRP 3.7.0** to `recovery` via fastbootd (OK), then `fastboot reboot recovery`.
TWRP **hangs on its splash screen** on this PE13 / encrypted-`/data` state, then powers off. Because
`reboot recovery` writes a "boot-recovery" flag to **`misc`** that recovery clears only once it starts, the
flag never cleared → **every boot went to the hanging TWRP** (plain Power press too). Tablet looked bricked:
Mi logo / TWRP splash / auto-off, sometimes falling into **EDL `05C6:900E`** (SoC fallback, healthy).

**What didn't work from this Windows PC:** bootloader fastboot (`18D1:D00D`) — native Windows crashes it;
usbipd→WSL connects but every write fails `Write to device failed (Timer expired)` (tried `getvar` + `reboot`).
fastbootd was unreachable (needs a booted Android). EDL is Xiaomi-auth-locked on SDM660 — not used.

**Fix:** an **Android phone as fastboot host** — **Bugjaeger** app over USB-C OTG, tablet in Vol-Down+Power
fastboot → `erase misc` → `reboot` → **PixelExperience booted**. Nothing was ever written to boot/system/vendor.

**Rules going forward:**
- **Never `fastboot reboot recovery` / boot TWRP 3.7.0 on this device** — it hangs and re-traps. `recovery`
  still holds that TWRP; replace it (try 3.6.2 or an unofficial newer build) before relying on recovery.
- **The phone+Bugjaeger is the working bootloader-fastboot host** (the PC is not). If trapped again: fastboot
  → `erase misc` → `reboot`.
- Android-side fastboot (fastbootd via `adb reboot fastboot` + Google driver, PID 4EE0) still works from the PC.

## 2026-06-17 (cont.) — FASTBOOT SOLVED via fastbootd; unlock + sizes confirmed ✅ (long saga)

The clover **bootloader (aboot) fastboot — USB `18D1:D00D` — is unusable on this Windows PC.** No signed
driver exists for D00D; Zadig's generic WinUSB *crashed the bootloader* on the first fastboot command
(tablet → "press any key to shutdown"); removing WinUSB stopped the crash but left no driver. usbipd→WSL
(native Linux fastboot) *enumerated* the device but every write failed `Write to device failed (Timer expired)`
over USB/IP (tried both `nat` and `mirrored` WSL networking). Dead end for the bootloader fastboot.

**SOLUTION — userspace fastboot (fastbootd).** `adb reboot fastboot` (adb is rock-solid) boots **fastbootd**,
which enumerates as a **different PID `18D1:4EE0`** that Google's **official** USB driver supports. Installed
`tools/google-usb-driver/usb_driver/android_winusb.inf` (`pnputil /add-driver … /install`, admin) → bound
cleanly as **"Android Bootloader Interface"** → **native Windows fastboot works, NO crash** (`getvar all` completed).

**Confirmed (Task #1 done):** `unlocked: yes` ✅, `secure: yes`, **non‑A/B** (slot-count 0), max-download 256 MB.
Layout: **`boot` physical 64 MB** (halium-boot 52 MB fits), **`system`/`vendor` LOGICAL** (retrofit-dynamic super),
`userdata` ~50 GB. Saved: `dumps/fastboot-getvar-all-2026-06-17.txt`.

**Install implication:** because system/vendor are logical, use **`halium-install -m img`** (system + ubuntu
rootfs as images on `/data` — sidesteps the dynamic-partition layout), and flash only **halium-boot → boot**
via fastbootd; TWRP handles the `/data` format + push. **Task #7 resolved** (fastbootd + Google driver — NOT
Zadig/D00D). Key lesson: for clover, **always use `adb reboot fastboot` (fastbootd), never `adb reboot bootloader`.**

## 2026-06-17 (cont.) — Pre-staged the flash kit (images + rootfs + halium-install; TWRP manual)

Per "disregard bandwidth", staged everything for a turnkey flash once Task #7 + tablet are ready:
- **Images → Windows `flash/`** (`halium-boot.img`, `system.img`) for Windows fastboot (git-ignored).
- **Rootfs** `ubuntu-touch-android9-arm64.tar.gz` (556 MB) downloading to `~/halium/install/` (`70-fetch-rootfs.sh`, resumable).
- **`halium-install`** cloned → `~/halium/tools/` (gitlab.com/JBBgameich/halium-install; the GitHub mirror stalled).
- **TWRP 3.7.0** auto-fetch FAILED — twrp.me + SourceForge serve JS/referer-gated HTML (not the binary) to curl;
  must **download manually** from twrp.me/clover at flash time. `71-fetch-twrp.sh` documents the attempt + fallback.
- Flash-kit guide `flash/README.md`; full runbook `flashing.md`.

Confirmed: **first boot uses the proven `ubuntu-touch-android9-arm64` (Focal-era) rootfs**; Noble is the later
stabilization step (per roadmap).

## 2026-06-17 (cont.) — Install prep: runbook + rootfs source confirmed (flashing gated on Task #7 + tablet)

Build complete (both images). Prepared the on-device install — see [flashing.md](flashing.md):
- **Rootfs confirmed:** `ubuntu-touch-android9-arm64.tar.gz`, **556 MB**, HTTP 200 at the UBports CI job
  `xenial-hybris-android9-rootfs-arm64` (lastSuccessfulBuild artifact). The proven Halium-9 (Focal-era) rootfs
  for first boot; **Noble** is the later stabilization target. Deferred the 556 MB pull to flash time (bandwidth).
- Install tool: `halium-install` (`-p ut -s system.img <rootfs>`) → `~/halium/tools/` (clone slow; re-fetch at install).
- **Two install blockers from the device dump:** (1) `/data` is **encrypted** → must Format Data (wipes the
  tablet) to meet halium-install's unencrypted-ext4 requirement; (2) recovery is **PE's, not TWRP** → flash a
  clover TWRP first. Both in the runbook.

**Everything past here needs the tablet + the one-time fastboot driver (Task #7).** Handoff: run Zadig (Task #7),
connect the tablet, decide backup/wipe → then flash TWRP → format data → halium-install → flash halium-boot →
first boot (Phase 4).

## 2026-06-17 — Phase 3 build: `system.img` built ✅ (full Halium image set ready)

`mka systemimage` → **build completed successfully** → `out/target/product/clover/system.img`
(**227,684,644 B ≈ 217 MB**; fits the 3 GB system partition). Two more host fixes beyond the halium-boot shims:
- **Python 2.7.18 from source** (`13-build-python2.sh`, built with `-std=gnu17` to dodge gcc-15's C23
  `true/false/bool` keywords) + a build-local `python→python2` PATH shim (`/opt/halium-py2bin`, prepended in
  `60-build-system.sh`) — AOSP-9 build scripts (`check_radio_versions.py`, releasetools) require python2.
- **Disabled the ClearKey @1.1 DRM HIDL service** (`46-disable-clearkey-drm.sh`) — broken in this LineageOS-16
  `frameworks/av` (`DrmPlugin.h` references a `DeviceFiles` type that doesn't exist in the tree). Non-essential
  for first boot; dropped from clover `PRODUCT_PACKAGES` (kept drm@1.0-impl/service).

**Full image set now built on the host (Ubuntu 26.04 / Python 3.14 / gcc 15, NO Docker):**
`halium-boot.img` (52 MB) + `system.img` (217 MB). **Five reproducible host shims total** (`scripts/setup/`):
imagemagick, initrd-download retries, libtinfo5 symlink, python2, clearkey-disable. **Task #5 build done.**

**Next:** download the UBports **Noble** rootfs, assemble with `halium-install` (push rootfs to /data), then flash
`halium-boot.img`→boot (p12) and `system.img`→system (p13) from Windows fastboot — needs **Task #7** (fastboot
WinUSB driver / Zadig) + the tablet. Then **Phase 4** first boot (telnet/adb → Mir + touch).

## 2026-06-17 — Phase 2: `halium-boot.img` built ✅ (Halium-9 builds on Ubuntu 26.04)

`mka halium-boot` → **build completed successfully** → `out/target/product/clover/halium-boot.img`
(**54,730,752 B ≈ 52 MB**, fits the 64 MB boot partition). Kernel `clover_halium_defconfig` compiled with the
AOSP-9 prebuilt **clang 6.0.2**. Three host-side fixes were needed on this new host (all reproducible scripts
in `scripts/setup/`):
- **ImageMagick** (added to `11-build-deps.sh`) — vendor/lineage bootanimation needs `convert`.
- **initramfs download hardened** (`45-fix-initrd-download.sh`) — `halium/halium-boot/get-initrd.sh` did one
  no-retry `curl --silent`; added `--retry/--fail/--connect-timeout`. (One connectivity blip had failed the build.)
- **libtinfo.so.5 shim** (`12-libtinfo5-shim.sh`) — the AOSP-9 prebuilt clang links `libtinfo.so.5`/
  `libncurses.so.5`; symlinked to `.so.6` (26.04 ships .6). THE host-too-new blocker; clang now loads.

**Conclusion: no Docker container needed** — Halium-9 builds on Ubuntu 26.04 / Python 3.14 / gcc 15 with those
3 shims. **Task #4 build done.** Reaching the initrd telnet/adb shell needs flashing → still gated on the
fastboot WinUSB driver (**Task #7**) + the tablet.

**Next:** `mka hybris-hal systemimage` → Halium **system.img** (Task #5). Bigger build; may surface more
host-too-new issues — iterate as before. Then download the UBports **Noble** rootfs, then flash (after #7).

## 2026-06-14 — Phase 1 complete: tree synced, hybris patches applied, `breakfast clover` resolves ✅

repo sync finished clean (**rc=0, 36 GB**). Verified the tree (`scripts/setup/verify-tree.sh`): clover
device/kernel/vendor all present (kernel has **`clover_halium_defconfig`**), plus build/, halium/,
hybris-patches/, vendor/lineage; **no `sdm660-common` dependency** (the 2021 clover tree is self-contained).
`vendor/halium` is absent but not needed — Halium glue comes via `halium/` + hybris-patches + vendor/lineage.

- Applied **107 hybris-patches** via `apply-patches.sh --mb` (`scripts/setup/40-apply-hybris-patches.sh`) —
  these add `build/target/product/halium.mk` + the hybris/Mer init hooks. The placeholder git identity from
  `20-repo-init.sh` was needed for `git am`.
- **`breakfast clover` → rc=0** (`scripts/setup/breakfast-test.sh`): TARGET_PRODUCT=lineage_clover, arm64,
  CPU **kryo**, PLATFORM_VERSION 9, soong namespaces for qcom audio/display/media **msm8998** (SDM660 family).
  This is the **Phase 1 milestone** → **Task #3 done**.

**Notable:** the AOSP-9 build system runs on this brand-new host (Ubuntu 26.04 / **Python 3.14**) for config —
breakfast/lunch/dumpvars all work. So the Halium Docker container may not be necessary; the real test is the
compile. **Next (Phase 2 / Task #4):** install kernel/boot-image build deps (deferred earlier), then
`mka halium-boot`. If the compile hits old-toolchain breakage, fall back to the Halium Docker container.

## 2026-06-09 — WSL build env up; repo init + Halium 9.0 sync started (background)

User installed the WSL distro → it's **Ubuntu 26.04 LTS (resolute)**, ext4 (~955 GB free), 24 cores,
15 GiB RAM (cap), user `projkt88`, link ~350 KB/s. Did the WSL side of Phase 0→1 via reproducible scripts
in `scripts/setup/`:
- `10-sync-deps.sh` — minimal sync deps (git 2.53, git-lfs 3.7, curl, **python 3.14**, rsync).
- `20-repo-init.sh` — installed `repo` to `~/.bin`, placeholder git identity, `repo init -u
  https://github.com/Halium/android -b halium-9.0 --depth=1`, copied the clover local_manifest.
- `30-repo-sync.sh` — launched the shallow sync in the **background** (`repo sync -c --no-tags
  --optimized-fetch --prune --force-sync --retry-fetches=3 -j6`), logging to `halium-9.0/sync.log`.

**Fixed a real bug:** `manifests/clover.xml` had a `------` separator inside an XML comment; `--` is illegal
in XML comments, so expat rejected the whole local_manifest (repo silently ignored it). Replaced with `=`.
Resolved manifest is now **397 projects** incl. the 3 clover repos (device/kernel/vendor, `groups=local::clover`).

**Notes / risks:**
- Host is brand-new (Ubuntu 26.04, **Python 3.14**). `repo` runs fine, but the old Android-9/Halium-9 build
  *tools* probably won't — plan to **build in the Halium Docker container** (host distro then irrelevant),
  decided at Phase 2. Sync on the host is fine.
- Shallow (`--depth=1`) saves bandwidth but can break `git describe`/history-dependent steps; unshallow
  specific repos later if needed.
- Sync is **resumable** — re-run `30-repo-sync.sh` if the link drops. At ~350 KB/s expect **many hours**.

**Next:** sync completes → `breakfast clover` resolves (Task #3 milestone) → apply hybris patches → Phase 2
(halium-boot). Fastboot driver (Task #7) still pending for flash time, independent of all this.

## 2026-06-04 (cont.) — Fastboot blocked by Windows driver; sizes need root/fastboot; Zadig staged

Tried to capture `fastboot getvar all` (unlock state + physical partition sizes). Reboot to bootloader
worked, but **Windows can't talk to fastboot**: the tablet enumerates as `USB\VID_18D1&PID_D00D`
("Android Bootloader Interface") with **`CM_PROB_FAILED_INSTALL`** — no driver bound. Neither the Google
USB Driver r13 (downloaded to `tools/google-usb-driver/`) nor the Motorola `android_winusb.inf` already in
the driver store (`oem14.inf`) lists `D00D`, and this shell is **non-admin**, so I can't bind one.
→ Staged **`tools/zadig-2.9.exe`** + wrote [fastboot-driver-windows.md](fastboot-driver-windows.md); the
one-time elevated WinUSB bind is **Task #7** (blocks Task #1). Only affects fastboot mode — adb is fine.

**Physical sizes (system p13 / vendor p14): unreachable without root or fastboot.** On running PE13,
`/proc/partitions` and `/sys/block/*/size` are both SELinux-**denied** to shell uid 2000; device isn't
rooted. `adb reboot recovery` brought up adb **unauthorized** (encrypted /data, no RSA prompt) → no shell,
and **suggests PE replaced TWRP** with its own recovery (the "TWRP installed" note is likely stale). Saved
the attempt + node mapping to `dumps/partition-sizes-2026-06-04.txt`. **Not a blocker:** retrofit-dynamic
preserves the factory GPT, so physical system/vendor ≈ the build limits (3 GB / ~0.8 GB); confirm exact
numbers via `fastboot getvar all` at flash time.

**Bottom line:** none of this blocks the build. Fastboot/flashing is Phase 3; the critical path is now
**Task #2 — install the WSL Ubuntu distro + build deps** (gated on slow connection), then repo sync + build
(Phases 1–2), which need neither the tablet nor fastboot. (Left the tablet in recovery — couldn't
`adb reboot`, unauthorized — user long-presses Power to return to Android.)

## 2026-06-04 — Live device dump (tablet plugged in) + WSL state check

Tablet connected over USB. First `adb` saw it **unauthorized**; user accepted the RSA prompt →
`XXXXXXXX  device  product:clover model:MI_PAD_4`. Pulled a full live dump while booted in PE13.
Raw artifacts saved to [`dumps/`](dumps/) (`getprop`, partition by-name, `df`, `cpuinfo`, mapper);
confirmed facts consolidated into [device-clover.md](device-clover.md) "Live dump — 2026-06-04".

**Newly confirmed / changed:**
- This unit = **Mi Pad 4 (non-Plus), 4 GB / 64 GB, WiFi-only**. Silicon is **SDA660** (modem-less SDM660)
  — `ro.boot.baseband=sda`, cpuinfo "SDA660". Reconfirms telephony is a hardware non-issue.
- **GPS/GNSS is PRESENT** (`gnss@2.1` service running) — resolves the previously-uncertain item.
- **Retrofit dynamic + non-A/B confirmed live** (`dynamic_partitions`+`_retrofit=true`,
  `super_partition=system`; logical system/vendor as `dm-0`/`dm-1`). Captured the real by-name→`mmcblk0pN`
  GPT map (system=p13, vendor=p14, boot=p12, recovery=p51, userdata=p64, …).
- Kernel **4.19.294** (clang 14, 2023-09-26); PE13 OFFICIAL `20230926`, SDK 33.
- Hardware parts for bring-up: touch **`fts_ts`** (FocalTech, 10-pt, 1200×1920); accel/gyro **BMI120**;
  ALS **CM3232**; audio `sdm660-snd-card`; Adreno 512 / GLES 3.2 / Vulkan 1.1.

**⚠ Two things flagged:**
1. **Bootloader props report LOCKED** (`flash.locked=1`, `vbmeta=locked`, `verifiedbootstate=green`,
   `oem_unlock_allowed=0`). Almost certainly **PixelExperience Play-Integrity spoofing** (you can't run an
   unofficial PE13 on a truly locked bootloader), so the BL is very likely still unlocked as noted — but
   this MUST be confirmed with `fastboot getvar unlocked` before we trust any flash. → **Task #1.**
2. **Physical `system`/`vendor` partition sizes still unknown** — `/proc/partitions` is root-only here.
   Also from `fastboot getvar all`. → **Task #1.**

**Couldn't read without root:** `/proc/cmdline`, `/proc/partitions`, battery `charge_full_design`.
(Get cmdline from the boot image / fastboot later; sizes from fastboot; battery design-capacity is
non-essential.)

**WSL:** engine present & modern — **WSL 2.7.3.0, kernel 6.6.114.1, default version 2**, virtualization on.
**No distro installed yet** (`wsl -l -v` → none), matching the user's note (deferred, slow internet).
`Ubuntu-24.04` is available via `wsl --install -d Ubuntu-24.04`. → **Task #2** (the gating download).

**Task list (re)created** in the harness: #1 fastboot/unlock+sizes, #2 WSL distro+deps, #3 repo sync,
#4 halium-boot, #5 system.img+Noble, #6 bring-up. adb/fastboot install + adb-side device-facts capture
are **done**.



User asked whether device facts could come from the Internet rather than a live dump — yes, for the
model-level facts. Pulled authoritative config from `halium_device_xiaomi_clover@halium-9.0`
(`BoardConfig.mk` + `fstab.qcom`) and community sources.

**Captured** (see [device-clover.md](device-clover.md)): non-A/B, system-as-root, **no** dynamic
partitions in our base; partition sizes (boot/recovery 64 MB, system 3 GB, vendor 800 MB, cache 256 MB,
persist 32 MB, userdata ~45 GB); kernel `kernel/xiaomi/clover` defconfig `clover_halium_defconfig`,
`Image.gz-dtb` pagesize 4096; cmdline `console=ttyMSM0,115200,n8 earlycon=msm_serial_dm,0xc170000`;
full by-name fstab (flash targets: `boot`/`system`/`vendor`).

**Important:** current ROM is **PixelExperience 13 (Android 13)** with **retrofit dynamic partitions**
(`super`) + 4.19 kernel. Retrofit keeps the physical GPT intact, so flashing legacy-layout Halium is
fine, but we must restore an Android-9-consistent vendor/firmware base — planned for Phase 3
(try Halium vendor first; LOS16 firmware fallback).

**Tasks:** #2 (adb/fastboot installed & working; live device check deferred to flashing) and #3
(facts captured from Internet) → done. WSL2 setup is the next active step.

**Variant confirmed: WiFi-only** → telephony (ofono/RIL/SMS/data/VoLTE) entirely out of scope; meaningfully simpler port. GPS presence TBD.

## 2026-06-03 — Project kickoff & planning

**Decisions**
- Goal: **modern port from scratch** (not reviving the 2021 port, not just installing).
- Base: **Halium 9.0 / Android 9 (`sdm660-common`)** for hardware + **Ubuntu Touch Noble (24.04)** rootfs.
  Rationale: Noble is a rootfs choice independent of Halium version; the same-SoC `lavender` port runs
  Noble on Halium 9, which is the most proven base for SDM660.
- Build host: **WSL2 (Ubuntu)** on this Windows 11 machine.

**Findings**
- A clover UT port exists (`ubuntu-touch-clover`) but is **abandoned since Oct 2021** (Halium 9 / Focal).
  Useful as reference, not as a live base.
- SDM660 is well-supported: `ubports-xiaomi-sdm660` org has shared `sdm660-common` device/kernel/vendor
  trees; `lavender` (Redmi Note 7) is an actively-maintained SDM660 port with Focal **and** Noble channels.
- clover LineageOS trees are actively maintained (kyasu et al.), up to LOS 23 (Android 16) — good
  device-tree material.

**Machine check**
- 24-core Intel Core Ultra 9 275HX, 31 GB RAM, ~870 GB free C: / ~950 GB free D:.
- Virtualization ON (`HypervisorPresent: True`) → WSL2 OK, no BIOS change. WSL not yet installed.
- git ✓, winget ✓; adb/fastboot not installed yet.

**Done**
- Initialized git repo; scaffolded README + docs (roadmap, device facts, build env, sources, this log).
- Created task list (#1–#11).

**Next**
- Install Windows adb/fastboot; verify device & capture `fastboot getvar all` + partition layout.
- Install WSL2 + Ubuntu; set up Halium build env.
