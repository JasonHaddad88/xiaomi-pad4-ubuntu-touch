# clover speakers on Nura — the actual cause, measured

**Conclusion: the speakers are two WSA881x smart amplifiers fed over `PRI_MI2S`. The
mainline clover device tree does not describe them, and the WSA881x driver is not even
compiled into this kernel. They cannot work until that is fixed — no amount of mixer
configuration will do it.**

This replaces two earlier wrong conclusions. The history matters, because both were stated
confidently and both were wrong for instructive reasons.

## How this was established

### 1. The internal codec's speaker output works perfectly — and is silent

`qcom,pm8916-wcd-analog-codec` has a complete speaker chain, and the driver drives all of
it. Measured from DAPM debugfs with a 440 Hz tone playing, speaker path enabled and
headphones switched off:

| widget | idle | tone playing |
|---|---|---|
| `Digital RX3 MIX1` | Off | **On** |
| `Digital RX3 INT` | Off | **On** |
| `Digital PDM_RX3` | Off | **On** |
| `PDM_RX3` | Off | **On** |
| `SPK DAC` | Off | **On** |
| `SPK PA` | Off | **On** — register `0xf1b2` mask `0x40` |
| `SPK_OUT` | Off | **On** |
| `SPKR_CLK` | Off | **On** |

The headphone chain (`HPHL DAC`, `HPHL PA`, `HPH_L`) stayed `Off` throughout, then powered
`On` when `HPHL`/`HPHR` were switched — so the measurement demonstrably distinguishes a live
output from a dead one.

**Result: complete silence.** The kernel powers up a speaker output, including a real
hardware PA-enable bit, that is not physically connected to this tablet's speakers.

### 2. What stock Android actually does

From the tablet's own vendor partition, which `msm-firmware-loader` exposes at
`/run/msm-firmware-loader/mnt/vendor` (`etc/mixer_paths.xml`, `etc/audio_platform_info.xml`):

```xml
<device name="SND_DEVICE_OUT_SPEAKER_WSA" interface="PRI_MI2S_RX"/>
<param key="spkr_1_tz_name" value="wsatz.11"/>
<param key="spkr_2_tz_name" value="wsatz.12"/>

<path name="deep-buffer-playback speaker">
    <ctl name="PRI_MI2S_RX Audio Mixer MultiMedia1" value="1" />
</path>
```

plus WSA control registers:

```xml
<ctl name="SpkrLeft WSA PA Gain"  value="G_0_DB" />
<ctl name="SpkrRight WSA PA Mute" value="1" />
<ctl name="SpkrLeft SWR DAC_Port Switch" value="0" />
<ctl name="SpkrLeft BOOST Switch" value="0" />
<ctl name="SpkrLeft VISENSE Switch" value="0" />
<ctl name="AIF1_VI_SDW Mixer SPKR_VI_1" value="0" />
```

So: **audio goes over `PRI_MI2S` to two WSA881x Class-D smart amps**, whose control and
VI-sense (voltage/current feedback for excursion protection) ride SoundWire. `wsatz.11` and
`wsatz.12` are the two amps' thermal zones. The internal codec's `SPK_OUT` plays no part.

### The trap that caused the earlier wrong answer

`mixer_paths.xml` also contains this:

```xml
<path name="speaker">
    <ctl name="SPK" value="Switch" />
</path>
```

That path is **not** what the audio HAL uses for speaker playback, and the control `SPK` does
not even exist in the mainline driver's control list. Quoting it as "Android's own recipe is
a single switch" produced a model of the hardware in which the internal codec drove the
speakers. Everything built on that was wrong. **A config file contains many paths; the one
that matters is the one the code actually selects.**

## What is required

| piece | state |
|---|---|
| `soundwire-bus`, `soundwire-qcom` | **present**, built as modules |
| `PRI_MI2S_RX Audio Mixer MultiMedia1` routing control | **present** (`numid=146`) — q6routing creates backends generically |
| `CONFIG_SND_SOC_WSA881X` | **not set** — the amp driver is not compiled |
| SoundWire master node in the clover DTS | **absent** |
| two `wsa881x` nodes with their SoundWire addresses | **absent** |
| a `PRI_MI2S` dai-link in the `sound` node | **absent** — only `INT0_MI2S` playback and `INT3_MI2S` capture exist |
| speaker `audio-routing` entries | **absent** |
| UCM `Speaker` device | absent, and pointless until the above lands |

The driver itself exists in mainline (`sound/soc/codecs/wsa881x.c`), so the kernel side is a
config change rather than new code. The device-tree side is real work: the SDM660 LPASS
SoundWire master's address and the two amps' SoundWire device IDs have to be established —
most readily from the downstream Android DTS for clover, not guessed.

## Why the volume OSD says "Headphones (3.5 mm jack)" with nothing plugged in

Not a jack-detection bug. The kernel is correct — `Headset Jack` reads `off`. clover's UCM
defines only `Headphones` and `Headset Mic`, so headphones are the **only** playback device
in existence, and PipeWire labels the stream accordingly whatever the jack does. With no
working speaker and no earpiece on this model, that label is currently accurate.

## Files here

- [`speaker-test.sh`](speaker-test.sh) — the on-device test. Its value now is as a method:
  it bypasses UCM and PipeWire (UCM reapplies its own mixer settings when a stream starts,
  so configuring first and playing afterwards can undo the thing being tested) and sets the
  path *while* the tone runs.

## Lesson

The bottom line of the very first conclusion — "this needs a DTS change and a kernel
rebuild" — turned out to be right. But it was reached from five arguments, four of which
were false, and it was then retracted on the strength of those being false. Both the
original claim and the retraction skipped the one step that would have settled it in
minutes: **read how the stock firmware drives the hardware.** The vendor partition was
mounted and readable the whole time.
