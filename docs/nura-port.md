# Nura (postmarketOS) on clover — what works, what was fixed, what is missing

**Nura** is postmarketOS, renamed on **27 September 2026**. It is Alpine-based and — unlike Ubuntu
Touch — uses **no Android container, no libhybris and no vendor HALs**. It runs a close-to-mainline
kernel (`linux-postmarketos-qcom-sdm660`, 7.0.14) talking to upstream Linux drivers.

`xiaomi-clover` is **already a supported device** (category `testing`), so this was never a port in the
sense the Ubuntu Touch work was. It is an install, plus fixing what is broken.

> Ubuntu Touch remains installed and untouched on internal storage. Nura runs **from the SD card**, so
> both are available: power on normally for Ubuntu Touch, `fastboot boot` for Nura.

## Status on this device

| | Nura | Ubuntu Touch |
|---|---|---|
| kernel | **mainline 7.0.14-sdm660** | Android 4.4.153 fork |
| Android container / libhybris | **none** | required |
| display, touch, 3D | works (but see the black-screen bug) | works |
| **Wi-Fi** | **works, WEP included — fixed here, see below** | works |
| **speakers** | **no — TAS2557 amps absent from the device tree; patch written, untested** | works, loud |
| headphones | works | works |
| camera | no | **works** |
| Bluetooth | reported working | masked (crash-looped) |
| rotation | works | works |

## Build and install

```sh
pmbootstrap config device xiaomi-clover
pmbootstrap config ui phosh
pmbootstrap config kernel clover        # NOT cloverlte / cloverplus - see below
pmbootstrap -y install --password 0000 --filesystem ext4
pmbootstrap export                      # boot.img + xiaomi-clover.img
```

**The kernel variant matters.** The device package offers three, and they ship *different device
trees*:

| variant | device | DTB |
|---|---|---|
| **`clover`** | Mi Pad 4, **Wi-Fi only** | `qcom/`**`sda660`**`-xiaomi-clover` |
| `cloverlte` | Mi Pad 4 LTE | `qcom/sdm660-xiaomi-clover` |
| `cloverplus` | Mi Pad 4 Plus | `qcom/sdm660-xiaomi-clover-plus` |

This unit is the Wi-Fi-only **SDA660**, so `clover` is correct. Choosing `cloverlte` would hand the
tablet a device tree for silicon it does not have.

The image is a complete disk (`pmOS_boot` ext2 + `pmOS_root` ext4) written straight to the SD card.
Booting is `fastboot boot boot.img` — RAM only, nothing on the tablet is written, so Ubuntu Touch is
never at risk.

## Fix 1 — `msm-firmware-loader` never ran (upstream bug)

**Symptom:** no vendor firmware anywhere; Wi-Fi had no calibration data and no MAC.

```
msm-firmware-loader.sh[405]: mount: /run/msm-firmware-loader: mount point does not exist.
```

The script mounts a tmpfs at `$BASEDIR` **without creating the directory first**:

```sh
BASEDIR="/run/msm-firmware-loader"
mount -o ... -t tmpfs none "$BASEDIR"   # <- fails, directory does not exist
mkdir -p "$BASEDIR/mnt"                 # <- creates the children, too late
```

It runs very early (`DefaultDependencies=no`, `Before=systemd-udevd.service`), before anything else
has created that path. The mount fails, the loader aborts, and **none of the device's firmware
partitions are ever exposed**.

**Fix** — one line, in `/usr/bin/msm-firmware-loader.sh`:

```sh
mkdir -p "$BASEDIR"
mount -o mode=755,nodev,noexec,nosuid -t tmpfs none "$BASEDIR"
```

Confirmed by `systemd[1]: Finished Load firmware that is located on dedicated partitions of qcom
devices.` where it previously failed. **This affects every device relying on `msm-firmware-loader`,
not just clover** — worth reporting upstream.

## Fix 2 — Wi-Fi: no board calibration data

**Symptom:** scanning worked, association always failed and dropped back to scanning.

```
ath10k_snoc: qmi chip_id 0x30214 chip_family 0x4001 board_id 0xff soc_id 0x40050000
ath10k_snoc: board_file api 2 bmi_id N/A crc32 00000000
ath10k_snoc: invalid MAC address; choosing random
ath10k_snoc: failed to set 2g txpower 40: -108
ath10k_snoc: firmware crashed! ... device successfully recovered
```

`board_id 0xff` means **unprogrammed** — the chip has no board ID burned in. ath10k looks up
calibration keyed on that value, finds only an empty placeholder in the stock `board-2.bin`, and gets
`crc32 00000000`. With no calibration, TX power cannot be set, and the firmware crashes the moment a
connection is attempted. Scanning survives because it needs no calibration.

### What did not work
Installing the vendor BDF as `board.bin` (the api-1 fallback). ath10k then logged **no `board_file`
line at all**. This matches the known upstream defect where WCN3990's fallback from `board-2.bin` to
`board.bin` cannot fire, because that platform's `hw_params` lacks the board-file fields.

### What worked
Build a real `board-2.bin` containing **this tablet's own BDF**, taken from its untouched vendor
partition, keyed to the board ID the chip reports:

```sh
# the device's own calibration data
adb pull /android/vendor/firmware_mnt/image/bdwlan.bin      # 19152 bytes

# Qualcomm's own encoder
curl -O https://raw.githubusercontent.com/qca/qca-swiss-army-knife/master/tools/scripts/ath10k/ath10k-bdencoder

cat > board.json <<'JSON'
[{ "names": ["bus=snoc,qmi-board-id=ff",
             "bus=snoc,qmi-board-id=ff,qmi-chip-id=30214",
             "bus=snoc,qmi-board-id=255"],
   "data": "bdwlan.bin" }]
JSON

python3 ath10k-bdencoder --create board.json
# -> board-2.bin, install to /lib/firmware/ath10k/WCN3990/hw1.0/
```

**Result: Wi-Fi associates and holds a connection.**

`invalid MAC address; choosing random` remains. It is cosmetic — ath10k generates a MAC when it finds
none — and does not stop connectivity. The real MAC (`20:a6:0c:5a:bf:6f`) is in
`persist/wlan_mac.clover` if it is ever worth wiring up.

## Fix 3 — Ubuntu Touch was corrupting the SD card on every boot

**This one is nasty and not obvious.** Ubuntu Touch's udisks2 **auto-mounts the Nura card read-write**
whenever it boots with the card inserted:

```
/dev/mmcblk1p2 on /media/phablet/pmOS_root type ext4 (rw,...,uhelper=udisks2)
```

The card's filesystem uses `metadata_csum`, `metadata_csum_seed`, `64bit` and `orphan_present` —
features the **4.4 kernel does not understand**. It refuses a read-write mount for them, but it still
**replays the ext4 journal**, writing metadata it cannot checksum correctly. After any unclean Nura
shutdown, this silently corrupts the card:

```
Group 18 block bitmap does not match checksum.
Orphan file (inode 12) block 65 is not clean.
pmOS_root: ********** WARNING: Filesystem still has errors **********
```

`e2fsck` could see **12 files** where there were 33,151. Nura then boots to a black screen.

**Fix** — stop udisks2 touching it, in `/etc/udev/rules.d/99-clover-no-sdcard-automount.rules` on
Ubuntu Touch:

```
SUBSYSTEM=="block", KERNEL=="mmcblk1*", ENV{UDISKS_IGNORE}="1"
```

**And never mount the card from Ubuntu Touch without `-o ro,noload`.** Plain `-o ro` is not enough —
ext4 replays the journal on a read-only mount. `noload` is what actually prevents it.

## Fix 4 — WEP: `wpa_supplicant` could not join the home network

With Fix 2 in place Wi-Fi worked on every network **except the one that matters** — the
owner's home network, `Blink7183AD`, which the router only offers as **WEP**. NetworkManager
refused it before the radio was ever touched:

```
Connection activation failed: no suitable device found for this connection
(wpa_supplicant does not support WEP encryption)
```

`wpa_supplicant` 2.10 moved WEP behind the build-time option `CONFIG_WEP` and **turned it
off**. It is not a runtime setting — the key-management code is simply not compiled in, and
NetworkManager reads that from the capabilities the daemon advertises on D-Bus. No profile
edit, `nmcli` flag or driver option can get around it.

**Fix:** rebuild the package with `CONFIG_WEP=y`. Full recipe, built packages and checksums:
[`device-fixes/nura/wpa_supplicant-wep/`](../device-fixes/nura/wpa_supplicant-wep/).

```sh
pmbootstrap --no-cross build wpa_supplicant     # --no-cross is global, before `build`
```

Two traps cost real time here:

- **`strings wpa_supplicant | grep wep_key0` matches even when WEP is compiled out**, because
  the config parser's key table survives. That output was twice mistaken for proof of
  support. It proves nothing; only an actual association does.
- The cross build fails with `'-fuse-linker-plugin', but liblto_plugin.so not found` —
  crossdirect plus LTO. `--no-crossdirect` is not a real flag.

**Result: the tablet associates with the WEP network and holds it,** with working DNS and
browsing. `pkgrel=99` keeps `apk` from replacing the package on upgrade.

WEP is broken encryption and this does not change that; the package exists because it is the
only network at the device's location.

## Not fixed — speakers: stereo TAS2557 missing from the device tree

Headphones work; **speakers produce nothing**, and the cause is now pinned down precisely.
Patch, UCM and workings: [`device-fixes/nura/speakers/`](../device-fixes/nura/speakers/).

**The speakers are two TI TAS2557 smart amplifiers on I2C, fed over `PRI_MI2S`.** The driver
is already built (`CONFIG_SND_SOC_TAS2557=m`) and `tulip`/`jasmine` already use it on this
SoC family, so **no kernel rebuild is needed** — only a new DTB and a UCM device.

| | |
|---|---|
| left amp | I2C `0x4C`, reset `tlmm 80`, IRQ `tlmm 28`, `ti,channel = <0>` |
| right amp | I2C `0x4E`, reset `tlmm 48`, IRQ `tlmm 55`, `ti,channel = <1>` |
| bus | `&blsp_i2c6` — present in clover's DTS but `status = "disabled"` |
| backend | `PRI_MI2S_RX Audio Mixer MultiMedia1` |

### How it was found

Ubuntu Touch's speakers work, so UT is the ground truth. Playing a tone there and capturing
**every DAPM widget that powered on** named the hardware outright:

```
codec:tas2557s.6-004c :: Stereo DAC / Stereo ClassD / Stereo OUT / Stereo ASI1 : On
platform:...msm-pcm-routing :: PRI_MI2S_RX Audio Mixer : On
WSA Spk Switch : 0
```

The addresses and GPIOs then came from the downstream device tree on the device itself,
`/proc/device-tree/soc/i2c@c1b6000/tas2557s@4c`.

Two habits did the work, and are worth keeping: **capture every widget that powers on**
instead of checking ones you guessed, and **measure on a configuration that works** —
everything here came from UT, not from Nura.

### Status

The DTS patch is written and verified to apply; the UCM device is written. **Neither is
tested** — next step is building the kernel package, repacking `boot.img` and
`fastboot boot`-ing it. Two points in the patch are unverified and flagged there: the 1.8 V
supply labels (tulip's cannot be copied — clover's `l6b` is 3.3 V) and the stereo pairing,
since tulip and jasmine each use only a single TAS2557.

### Why the volume OSD says "Headphones (3.5 mm jack)" with nothing plugged in

Not a jack bug — the kernel reports `Headset Jack` as `off` correctly. clover's UCM defines
only `Headphones` and `Headset Mic`, so headphones are the only playback device that exists
and are therefore always selected. Adding the `Speaker` device fixes this too.

### Three retracted conclusions

This section held three wrong answers before this one, and the pattern is the lesson:

1. **"Not implemented in mainline at all."** Five arguments, four false — `audio-routing`
   was said to list headphone paths and no speaker, when it lists *no* headphone paths yet
   headphones work; "no SDM660 device has speaker support" when `tulip` and `jasmine` both
   ship one; and "`SPK DAC Switch` changes nothing", measured with `Digital RX3 Mute Switch`
   set to `1` — a control named *Mute*, so the test silenced the path it was testing.
2. **"It is a configuration problem."** Driving the internal codec properly powered
   `SPK DAC → SPK PA → SPK_OUT` fully, confirmed in DAPM, and produced silence: that output
   is not wired to these speakers.
3. **"WSA881x amps on SoundWire."** Taken from `SND_DEVICE_OUT_SPEAKER_WSA` in the vendor
   config — a path for a *different variant* of the hardware.

Each wrong answer came from reading a plausible artefact instead of observing the working
system. The claim "there is no amplifier on I2C" was wrong for the same reason: `&blsp_i2c6`
is disabled in the device tree, so nothing could enumerate on it. And `tulip`/`jasmine`'s
UCM, labelled *"Built-in Speaker (TAS2557 smart amplifier)"*, was the right answer all along
— dismissed here on the grounds that "clover has no TAS2557".

## Access notes

- **SSH into Nura**: `user` / `0000`, over Wi-Fi once connected. pmOS enables sshd by default.
- **The home network does not isolate clients.** An earlier note here claimed AP isolation on
  `Blink7183AD` and drove a whole phone-hotspot workaround. It is wrong: with the PC on that
  network, the tablet answered on port 22 immediately. Put both on the home Wi-Fi and work
  directly. Find the tablet with a port-22 sweep rather than ping — it does not answer ICMP:

  ```sh
  for n in $(seq 1 254); do
    (timeout 2 bash -c "echo > /dev/tcp/192.168.1.$n/22" 2>/dev/null && echo "192.168.1.$n") &
  done; wait
  ```

- **Reading the stock Android audio/firmware config from Nura**: `msm-firmware-loader` mounts the
  vendor partition at `/run/msm-firmware-loader/mnt/vendor`. `etc/mixer_paths.xml` and
  `etc/audio_platform_info.xml` there are the authority on how the hardware is really driven —
  check them *before* theorising about an audio path.
- **DAPM widget power states** are in `/sys/kernel/debug/asoc/Xiaomi Mi Pad 4/<component>/dapm/`.
  `head -1 "<widget>"` gives `On`/`Off` plus the backing register. This turns "is this output
  actually active?" into a measurement, and a known-working output makes a positive control.
- **USB networking** uses **NCM**, not RNDIS. Windows binds the whole composite gadget as an Android
  ADB interface (`oem194.inf` matches `VID_18D1&PID_D001`), which hides the network function. Looking
  for an "RNDIS" child in Device Manager will not find one.
- **Nura has no RTC sync**, so journal timestamps reset to a build-time date every boot. Do not use
  them to tell boots apart — use `journalctl --list-boots` indexes.
- **Reading Nura's logs from Ubuntu Touch** works well: mount the card `-o ro,noload` and point
  `journalctl -D` at `var/log/journal`. An unclean shutdown loses only the last few seconds.

## Rollback

Nura lives entirely on the SD card. Remove it, or simply power on normally — Ubuntu Touch is on
internal storage and was never modified. `fastboot boot` writes nothing.
