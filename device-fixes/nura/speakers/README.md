# clover speakers on Nura — WORKING: stereo TAS2557 on PRI_MI2S

**The speakers work.** They are two TI TAS2557 smart amplifiers on I2C, fed over `PRI_MI2S`.
Confirmed audible on 22 October 2026.

Three things were missing, none of them kernel code:

1. the device-tree nodes (the amps' I2C bus was `status = "disabled"`),
2. the `PRIMARY_MI2S_RX` DAI declaration and a dai-link,
3. the amps' DSP firmware, which is on the tablet's own vendor partition.

`CONFIG_SND_SOC_TAS2557=m` is already set in the pmaports kernel config and
`snd-soc-tas2557.ko` already ships in the rootfs, so **no kernel rebuild is needed** — only a
new DTB, one firmware file and a UCM device.

| | |
|---|---|
| left amp | I2C `0x4C`, reset `tlmm 80`, IRQ `tlmm 28`, `ti,channel = <0>` |
| right amp | I2C `0x4E`, reset `tlmm 48`, IRQ `tlmm 55`, `ti,channel = <1>` |
| bus | `&blsp_i2c6` (`i2c@c1b6000`), enabled by the patch |
| backend | `PRI_MI2S_RX Audio Mixer MultiMedia1` |
| firmware | `tas2557s_uCDSP.bin` from the vendor partition |

## Steps

### 1. Device tree

[`0001-clover-add-tas2557-speakers.patch`](0001-clover-add-tas2557-speakers.patch) — against
`arch/arm64/boot/dts/qcom/sdm660-xiaomi-clover-common.dtsi` in
`github.com/sdm660-mainline/linux` at `v7.0.14-sdm660`. Verified to apply cleanly.

It enables `&blsp_i2c6`, adds both amps, declares `dai@16` (`PRIMARY_MI2S_RX`) in
`&q6afedai`, adds the `pri-mi2s-dai-link` with both codecs, the two `audio-routing` entries
and the `pri_mi2s_active` pin state.

### 2. Firmware — must be taken off this tablet

The blob is proprietary and is **not** committed here. It is already on the device, on the
vendor partition, which both Ubuntu Touch and Nura leave untouched:

```sh
# on Nura, where msm-firmware-loader exposes the vendor partition
sudo cp /run/msm-firmware-loader/mnt/vendor/firmware/tas2557s_uCDSP.bin /lib/firmware/
```

`tas2557s_uCDSP.bin` is 39615 bytes, md5 `21a800398c167168579395d9662cf4f3` on this unit.

**Note the `s`.** clover ships the *stereo* firmware, `tas2557s_uCDSP.bin`, while the driver
defaults to `tas2557_uCDSP.bin`. Rather than renaming the vendor file, the patch sets
`firmware-name = "tas2557s_uCDSP.bin"` on both nodes. The driver supports this firmware
properly — it validates the device type with
`unsupported device %u in firmware (expected 2=mono or 3=stereo)` — so the stereo blob is
the correct input, not a workaround.

On success both chips report:

```
tas2557 1-004c: PG2.1 left ready:  fw 'tas2557s_uCDSP.bin' ver=0x1010000 drv=0x400 (3 prog, 6 cfg)
tas2557 1-004e: PG2.1 right ready: fw 'tas2557s_uCDSP.bin' ver=0x1010000 drv=0x400 (3 prog, 6 cfg)
```

Without it, the amps probe and register controls but refuse to produce audio:
`firmware 'tas2557_uCDSP.bin' not found, the amplifier cannot work without it`.

### 3. UCM

[`clover-ucm-speaker.conf.add`](clover-ucm-speaker.conf.add) — adds the `Speaker` device,
the volume defaults, and `Speaker` to the `Headphones` conflicts.

## Verified on device

With a tone playing, every stage of both amps powers up:

| widget | left (`1-004c`) | right (`1-004e`) |
|---|---|---|
| `ASI1` / `ASI2` | On | On |
| `DAC` | On | On |
| `ClassD` | On | On |
| `OUT` | On | On |
| `bias_level` | On | On |

plus `PRI_MI2S_RX` and `PRI_MI2S_RX Audio Mixer` On. **And it is audible.**

The `iovdd`/`avdd`/`dvdd` supplies fall back to dummy regulators and the amps work regardless,
so the rails are board-fixed. tulip's labels must *not* be copied for these — clover's `l6b`
is 3.3 V (`vreg_l6b_3p3`) where tulip's is 1.8 V. `vbat-supply = <&vph_pwr>` resolves fine.

## Testing without a kernel build

The driver was already present, so only the DTB needed changing. Rather than build the kernel
package, the compiled DTB was patched directly and spliced into the boot image:

1. `dtc -I dtb -O dts` the shipped `sda660-xiaomi-clover.dtb`, add the nodes in resolved form
   (phandles by value — `tlmm` is `0x29`, `vph_pwr` `0x1e`, `q6afedai` `0x97`,
   `q6routing` `0x98`; new nodes took `0xb0`–`0xb2`, above the highest in use, `0xa2`),
   recompile.
2. In this boot image the DTB is **appended to the gzipped kernel** inside the kernel region
   (header v0). Replace that tail, fix `kernel_size` in the header, recompute the `id` SHA1,
   re-pad the ramdisk to a page boundary.
3. `fastboot boot` the result — RAM only, nothing written.

## Pitfalls hit along the way

- **`reboot bootloader` works on Ubuntu Touch but not on Nura.** UT's downstream kernel
  honours the reboot reason; Nura's mainline kernel does not, so systemd starts shutting
  down (taking Wi-Fi with it), the reboot call then fails, and the device is left
  half-stopped and unreachable. Use `fastboot` from a powered-off state instead.
- **`dtc | head` silently produces no output file.** SIGPIPE kills dtc before it writes.
  Redirect its warnings to a file instead of piping.
- **The patch initially missed `dai@16`.** `&q6afedai` declared only `dai@81` and `dai@88`;
  a dai-link cannot bind to an undeclared DAI.

## Three retracted conclusions

The answer took three wrong turns, and the pattern is the lesson:

1. **"Speakers are not implemented in mainline."** Five arguments, four false.
2. **"It is a configuration problem — the internal codec's `SPK DAC` needs enabling."**
   Driving it correctly powered `SPK DAC → SPK PA → SPK_OUT` fully and produced silence:
   that output is not wired to these speakers.
3. **"WSA881x amps on SoundWire."** Taken from `SND_DEVICE_OUT_SPEAKER_WSA` in the vendor
   config — a path for a *different variant* of the hardware.

Each came from reading a plausible artefact instead of observing the system that worked.
"There is no amplifier on I2C" was wrong for the same reason: `&blsp_i2c6` was disabled, so
nothing could enumerate on it.

**What finally worked:** Ubuntu Touch's speakers work, so a tone was played *there* and every
DAPM widget that powered on was captured. The active chain named its own hardware
(`codec:tas2557s.6-004c :: Stereo ClassD: On`) in one step. And `tulip`/`jasmine`'s UCM,
labelled *"Built-in Speaker (TAS2557 smart amplifier)"*, had been the right answer all along
— dismissed early on the grounds that "clover has no TAS2557".

## The interrupt-storm bug (and why the IRQs are not wired)

The first working version of this patch **hung the tablet**: UI frozen, display would not
blank, input dead, ssh answering and then starving out. The audio was fine; the machine was
not.

Cause: `gpio28`.

```
cdc-dmic-default-state {                 /* phandle 0x95 */
    dmic2-clk-pins {
        pins = "gpio28";
        function = "dmic2_clk";
    };
};

&sound { pinctrl-0 = <&cdc_pdm_default>, <&cdc_dmic_default>; };   /* claims 0x95 */
```

clover's own `sound` node claims that pin and muxes it to the DMIC2 clock. The patch had put
the left amplifier's interrupt on the same pin as `IRQ_TYPE_LEVEL_HIGH`. **A level-triggered
interrupt on a pin being driven as a clock never deasserts** — an interrupt storm, and the
machine drowns.

The downstream device tree really does say `ti,irq-gpio-left = <&tlmm 28>`, so either the amp
IRQ genuinely is gpio28 and clover's mainline DMIC pinctrl is mistaken, or the downstream
property means something else. **That is unresolved**, so neither interrupt is claimed now.
The amplifiers do not need them — they only report faults, and audio works without them.

### The checking mistake worth remembering

The GPIOs were validated against clover's **source** `.dtsi` files, where a grep for
`&tlmm 28` and `"gpio28"` found nothing. But the pin states that actually conflict are
inherited from the SoC-level include and only appear in the **fully resolved** tree. Checking
the compiled DTB — `dtc -I dtb -O dts` on the shipped `.dtb`, which is what the kernel is
really handed — shows them immediately:

```sh
dtc -I dtb -O dts sda660-xiaomi-clover.dtb | grep -oE 'pins = "gpio[0-9]+"' | sort -u
```

That lists gpio14, gpio28 and others the source files never mention. **Validate pin claims
against the resolved tree, not the board's own source file.**
