# Stock Android audio configuration, taken off this tablet

Copied from the tablet's own vendor partition, which `msm-firmware-loader` exposes on Nura at
`/run/msm-firmware-loader/mnt/vendor/etc/`. That partition is untouched by both Ubuntu Touch
and Nura, so this is the real Xiaomi configuration for this exact unit.

These are **the authority on how the hardware is actually driven.** Read them before
theorising about any audio path.

- `mixer_paths.xml` — ALSA mixer control sequences per audio device/use case
- `audio_platform_info.xml` — which backend interface each `SND_DEVICE_*` uses

## What they say about the speakers

```xml
<device name="SND_DEVICE_OUT_SPEAKER_WSA" interface="PRI_MI2S_RX"/>
<param key="spkr_1_tz_name" value="wsatz.11"/>
<param key="spkr_2_tz_name" value="wsatz.12"/>
```

Two WSA881x smart amps on `PRI_MI2S`, with SoundWire for control and VI-sense.

## Caution: pick the path the code actually uses

`mixer_paths.xml` holds many paths, and the wrong one will mislead you. This exists in the
file:

```xml
<path name="speaker">
    <ctl name="SPK" value="Switch" />
</path>
```

It is **not** what the audio HAL uses for speaker playback, and `SPK` is not even a control
the mainline driver exposes. Reading it as "Android drives the speaker with a single switch"
produced an entirely wrong model of this board. The paths the HAL actually selects are the
use-case-qualified ones, e.g. `deep-buffer-playback speaker`, which resolve to
`PRI_MI2S_RX Audio Mixer MultiMedia1`.

These files are vendor data, not instructions — read as reference only.
