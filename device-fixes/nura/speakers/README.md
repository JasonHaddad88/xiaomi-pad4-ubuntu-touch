# clover speakers on Nura — stereo TAS2557 on PRI_MI2S

**The speakers are two TI TAS2557 smart amplifiers on I2C, fed over `PRI_MI2S`.** The mainline
driver is already built (`CONFIG_SND_SOC_TAS2557=m`) and `tulip`/`jasmine` already use it on
this SoC family. clover is missing only the **device-tree nodes** and a **UCM device**.

No kernel rebuild is needed — only a new DTB.

| | |
|---|---|
| left amp | I2C `0x4C`, reset `tlmm 80`, IRQ `tlmm 28`, `ti,channel = <0>` |
| right amp | I2C `0x4E`, reset `tlmm 48`, IRQ `tlmm 55`, `ti,channel = <1>` |
| bus | `&blsp_i2c6` (`i2c@c1b6000`) — present in clover's DTS but `status = "disabled"` |
| backend | `PRI_MI2S_RX Audio Mixer MultiMedia1` |
| driver | `snd-soc-tas2557.ko`, already built; widgets `ASI1`/`ASI2`, control `Speaker Playback Volume` |

## Files

- [`0001-clover-add-tas2557-speakers.patch`](0001-clover-add-tas2557-speakers.patch) — against
  `arch/arm64/boot/dts/qcom/sdm660-xiaomi-clover-common.dtsi` in
  `github.com/sdm660-mainline/linux` at `v7.0.14-sdm660`. Verified to apply cleanly.
  It enables `&blsp_i2c6`, adds both amps, adds the `pri-mi2s-dai-link`, the two
  `audio-routing` entries and the `pri_mi2s_active` pin state.
- [`clover-ucm-speaker.conf.add`](clover-ucm-speaker.conf.add) — the UCM `Speaker` device.
- [`speaker-test.sh`](speaker-test.sh) — on-device test method (see *Method* below).
- [`stock-android-reference/`](stock-android-reference/) — the tablet's own
  `mixer_paths.xml` and `audio_platform_info.xml`.

## How this was established

Ubuntu Touch's speakers work, so UT is the ground truth. Playing a tone on UT and capturing
**every DAPM widget that powered on** named the hardware outright:

```
codec:tas2557s.6-004c :: Stereo DAC     : On
codec:tas2557s.6-004c :: Stereo ClassD  : On
codec:tas2557s.6-004c :: Stereo OUT     : On
codec:tas2557s.6-004c :: Stereo ASI1    : On
platform:...msm-pcm-routing :: PRI_MI2S_RX Audio Mixer : On
WSA Spk Switch                          : 0
```

`tas2557s.6-004c` = a TAS2557 on I2C bus 6, address 0x4c. The addresses and GPIOs then came
from the downstream device tree on the device itself, `/proc/device-tree/soc/i2c@c1b6000/tas2557s@4c`:

```
ti,left-channel  = 0x4c      ti,right-channel = 0x4e
ti,reset-gpio-left  = <&tlmm 80>     ti,irq-gpio-left  = <&tlmm 28>
ti,reset-gpio-right = <&tlmm 48>     ti,irq-gpio-right = <&tlmm 55>
```

### Method worth reusing

- **Capture every widget that powers on, rather than checking widgets you guessed.** The
  active chain names its own hardware. `/sys/kernel/debug/asoc/<card>/<component>/dapm/<widget>`,
  first line, during playback.
- **Measure on a configuration that works.** UT's speakers work; Nura's do not. Everything
  here came from the working one.

## Open points in the patch

Both are low-risk but unverified, and marked in the patch:

1. **Supplies.** `vbat-supply = <&vph_pwr>` is certain. tulip also wires `iovdd`/`avdd`/`dvdd`
   to `vreg_l6b_1p8`, but **clover's `l6b` is 3.3 V** (`vreg_l6b_3p3`), so tulip's label must
   not be copied. The downstream clover DT declares no supplies for this amp at all, implying
   the rails are board-fixed, and ASoC falls back to a dummy regulator for a missing supply.
   They are therefore omitted rather than guessed. If the amps fail to probe, the 1.8 V
   candidates on clover are `vreg_l8a_1p8`, `vreg_l9a_1p8`, `vreg_l10a_1p8`, `vreg_l13a_1p8`.
2. **Stereo is new ground.** tulip and jasmine each use a *single* TAS2557. clover is the
   first stereo pair in pmaports, so the `sound-name-prefix` approach ("Left Spk"/"Right Spk")
   and the two-codec `pri-mi2s-dai-link` are the parts most likely to need adjustment. The
   driver does support it in principle — it validates `ti,channel must be 0 or 1` and logs
   `TAS2557 probed (I2C addr 0x%02x, %s channel)`.

**None of this is tested yet.** The next step is building the kernel package with the patch,
repacking `boot.img`, and `fastboot boot`-ing it.

## Three retracted conclusions

This took three wrong answers before the right one, and the pattern is the lesson:

1. **"Speakers are not implemented in mainline."** Five arguments, four false.
2. **"It is a configuration problem — the internal codec's `SPK DAC` just needs enabling."**
   Measured wrong: `Digital RX3 Mute Switch` had been set to `1`, and that control is named
   *Mute*. Driving the internal codec correctly afterwards powered
   `SPK DAC → SPK PA → SPK_OUT` fully — and produced silence, because that output is not
   wired to these speakers.
3. **"The speakers are WSA881x amps on SoundWire."** Taken from
   `SND_DEVICE_OUT_SPEAKER_WSA` in the vendor config — a path for a *different variant* of
   the hardware. clover's actual device is the TAS2557.

Each wrong answer came from reading a *plausible* artefact instead of observing the working
system: a config file's wrong path, a control whose polarity was assumed, a bus that was
disabled in the device tree (which is also why "there is no amplifier on I2C" was wrong —
`&blsp_i2c6` is off, so nothing could enumerate).

Also worth noting: `tulip`/`jasmine`'s UCM, labelled *"Built-in Speaker (TAS2557 smart
amplifier)"*, was the right answer the whole time and was explicitly dismissed here on the
grounds that "clover has no TAS2557".
