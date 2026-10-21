# clover speakers on Nura — candidate fix, and a correction to the earlier analysis

**Status: not yet tested on the device.** Everything below about the kernel and the device
tree is verified from the compiled DTB and the shipped UCM tree. Whether the speakers
actually produce sound is an empirical question that [`speaker-test.sh`](speaker-test.sh)
answers and nothing here can.

## The earlier conclusion was wrong

`docs/nura-port.md` previously said the speakers could not work without a DTS change and a
kernel rebuild, because mainline had no speaker support for this SoC. Four of the five
arguments given for that do not survive checking the decompiled
`sda660-xiaomi-clover.dtb` and the installed `ucm2` tree:

| earlier claim | what is actually true |
|---|---|
| "The device tree's `audio-routing` contains only headphone, earpiece and mic paths. No speaker widget." | `audio-routing` contains **no headphone paths either** — yet headphones work. It declares `"PDM_RX3", "Digital PDM_RX3"`, and `PDM_RX3` is exactly the input the `SPK DAC` takes. The speaker feed **is** declared. |
| "Neither do `tulip`, `lavender` or `jasmine` — no SDM660 device has speaker support." | `tulip` and `jasmine` both ship a `SectionDevice."Speaker"`. |
| "`SPK DAC Switch` — enabling it changes nothing." | It was enabled in a test where `Digital RX3 Mute Switch` had been set to `1`. That control is named *Mute*: `1` means muted. The path was silenced by the test itself. |
| "This is not a configuration problem." | Every element the path needs is present in the kernel and the DTS. On the evidence available it is *exactly* a configuration problem. |
| "There is no amplifier on I2C — the only I2C device is the touchscreen." | Still true, and still relevant: it means the relevant output is the codec's own, not an external smart amp. |

The analog codec is instantiated as `qcom,pm8916-wcd-analog-codec` inside the PMIC, and its
interrupt list names `cdc_spk_cnp_int`, `cdc_spk_clip_int` and `cdc_spk_ocp_int` — speaker
click-and-pop, clipping and over-current. A driver with no speaker support does not request
speaker over-current interrupts.

## Why `tulip`'s and `jasmine`'s Speaker cannot simply be copied

Theirs is a **TAS2557 smart amplifier on `PRI_MI2S`**:

```
cset "name='PRI_MI2S_RX Audio Mixer MultiMedia1' 1"
```

clover has no TAS2557 — no such node in the DTB, and no I2C amplifier on the board. That is
a different topology, not a different setting, so their sequence is useless here.

## The right reference: apq8016-sbc

`Qualcomm/apq8016-sbc/HiFi.conf` drives the **same analog codec** through its internal
`SPK DAC`:

```
cset "name='SPK DAC Switch' 1"
cset "name='RX3 MIX1 INP1' RX1"
cset "name='RX3 Digital Volume' 128"
```

The full chain is

```
MultiMedia1 → INT0_MI2S_RX → Digital RX3 → Digital PDM_RX3 → PDM_RX3 → SPK DAC → SPK_OUT
                                                              ^^^^^^^ declared in clover's audio-routing
```

**Control names differ between the two boards, and this is the trap.** clover's DTS gives the
digital codec `sound-name-prefix = "Digital"`, so its controls are `Digital RX3 MIX1 INP1`,
`Digital RX3 Digital Volume`. The analog codec has no prefix, so `SPK DAC Switch` is
unprefixed. apq8016 prefixes neither. Copying its file verbatim silently does nothing,
because every `cset` names a control that does not exist.

## The candidate

[`clover-HiFi-Speaker.conf.add`](clover-HiFi-Speaker.conf.add) — append to
`/usr/share/alsa/ucm2/Xiaomi/clover/HiFi.conf`. Note `clover.conf` and
`conf.d/sdm660-internal/Xiaomi Mi Pad 4.conf` both point at that same `HiFi.conf`, so one
edit covers both entry points.

## Testing it

Run [`speaker-test.sh`](speaker-test.sh) as root on the device. It bypasses UCM and
PipeWire on purpose: **UCM reapplies its own mixer settings when a stream starts**, so
setting the controls first and then playing through the normal path can undo the thing being
tested. The script starts the tone, then sets the path while it is running, and logs the
control values *during* playback.

It restores every control on exit and writes nothing outside `/tmp`.

The only result that counts is whether the speakers made sound. Do not accept a control
read-back as proof — see the sibling `wpa_supplicant-wep/README.md` for how that kind of
proxy evidence has already misled this project twice.

### If it stays silent

Then the remaining possibility is the one the original conclusion assumed: `SPK_OUT` is not
physically connected to this tablet's speakers, and Xiaomi drove them from something the
mainline device tree does not describe. That would be worth confirming against the
downstream Android `mixer_paths*.xml` and the stock DTS before touching the kernel. Note
that the headphone outputs of this same analog codec *are* connected and do work, so the
codec's analog outputs reaching the board is established — just not that SPK_OUT in
particular reaches the speakers.
