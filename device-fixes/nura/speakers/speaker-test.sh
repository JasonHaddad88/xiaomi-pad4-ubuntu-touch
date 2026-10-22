#!/bin/sh
# Decide, on the device, whether clover's speakers are driven by the internal
# codec's SPK DAC. Run as root on Nura:  sh speaker-test.sh
#
# This deliberately bypasses UCM and PipeWire. UCM reapplies its own mixer
# settings when a stream starts, so setting controls first and then playing
# through the normal path can silently undo the very thing being tested.
#
# Nothing here is persistent: every control is restored on exit, and no file is
# written outside /tmp.
set -e
CARD=0
LOG=/tmp/speaker-test.log
exec > "$LOG" 2>&1
set -x

ctl() { amixer -c "$CARD" cset name="$1" "$2" >/dev/null 2>&1 || echo "MISSING CONTROL: $1"; }
get() { amixer -c "$CARD" cget name="$1" 2>/dev/null | sed -n 's/^  : values=/'"$1"' = /p'; }

echo "### the controls this test depends on, before touching anything"
for c in "SPK DAC Switch" "Digital RX3 MIX1 INP1" "Digital RX3 Mute Switch" \
         "Digital RX3 Digital Volume" "HPHL" "HPHR"; do get "$c"; done

echo "### confirm the analog codec really exposes a speaker"
amixer -c "$CARD" controls | grep -iE 'spk|ear|hph' || echo "no spk/ear/hph controls at all"

echo "### free the hardware"
# PipeWire/WirePlumber hold the PCM and own the UCM state.
systemctl --user -M user@ stop wireplumber pipewire pipewire-pulse 2>/dev/null || true
pkill -STOP wireplumber 2>/dev/null || true
sleep 2

echo "### a 440 Hz tone, 5 seconds, straight at the hardware"
# Generate the tone with no extra dependencies.
python3 -I - <<'PY'
import math, struct, wave
f, sr, secs, amp = 440.0, 48000, 5, 0.35
w = wave.open('/tmp/tone.wav', 'wb')
w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
w.writeframes(b''.join(struct.pack('<hh', *( (int(amp*32767*math.sin(2*math.pi*f*n/sr)),)*2 ))
                        for n in range(sr*secs)))
w.close()
PY

aplay -D "hw:${CARD},0" /tmp/tone.wav &
APLAY=$!
sleep 1

echo "### set the speaker path WHILE the stream is running"
ctl "Digital RX3 MIX1 INP1"     "RX1"
ctl "Digital RX3 Mute Switch"   "0"
ctl "Digital RX3 Digital Volume" "84"
ctl "SPK DAC Switch"            "1"

echo "### state during playback - this is the evidence that matters"
for c in "SPK DAC Switch" "Digital RX3 MIX1 INP1" "Digital RX3 Mute Switch" \
         "Digital RX3 Digital Volume"; do get "$c"; done

wait "$APLAY" || true

echo "### restore"
ctl "SPK DAC Switch"          "0"
ctl "Digital RX3 MIX1 INP1"   "ZERO"
pkill -CONT wireplumber 2>/dev/null || true
systemctl --user -M user@ start pipewire pipewire-pulse wireplumber 2>/dev/null || true
rm -f /tmp/tone.wav

echo "### DONE - the only question that matters: did the SPEAKERS make sound?"
