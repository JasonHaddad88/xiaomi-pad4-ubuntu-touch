#!/bin/sh
# Run this ON NURA, at the location whose AP crashes the Wi-Fi firmware.
#
#     sudo sh wifi-ap-crash-diagnostic.sh <SSID>
#
# It writes everything to /var/log/wifi-ap-crash.log on Nura's own rootfs, which
# persists. Read it afterwards from Ubuntu Touch:
#
#     sudo mount -o ro,noload /dev/mmcblk1p2 /mnt/nura
#     cat /mnt/nura/var/log/wifi-ap-crash.log
#
# WHY IT LOGS TO DISK: debugging Wi-Fi over Wi-Fi does not work. Every live
# attempt in this project knocked the tablet off the network and cost a power
# cycle, and two attempts died on `nmcli`, which hangs in a detached root
# context. Nothing here needs a live connection, and nothing here calls nmcli
# in the background.
set -x
SSID="${1:?usage: wifi-ap-crash-diagnostic.sh <SSID>}"
LOG=/var/log/wifi-ap-crash.log
exec > "$LOG" 2>&1

echo "=== BASELINE: state before touching anything ==="
date
uname -r
cat /sys/module/ath10k_core/parameters/debug_mask
dmesg | grep -iE "ath10k" | head -40

echo "=== THE AP: what does it advertise? ==="
# -B keeps this out of the interactive path; the scan itself is harmless.
iw dev wlan0 scan 2>/dev/null | awk -v s="$SSID" '
  /^BSS /{keep=0} $0 ~ "SSID: " s {keep=1}
  keep {print}' | head -60

echo "=== channel, rates, HT/VHT capabilities of that BSS ==="
iw dev wlan0 scan 2>/dev/null | awk -v s="$SSID" '
  /^BSS /{b=$2; keep=0} $0 ~ "SSID: " s {keep=1; print "BSSID " b}
  keep && /freq|DS Parameter|HT capabilities|HT operation|VHT|Supported rates|Extended supported|RSN|WEP|Privacy|ERP/ {print}' | head -40

echo "=== ATTEMPT: connect, and capture what the firmware does ==="
dmesg -C
timeout 90 nmcli connection up "$SSID"
echo "nmcli rc=$?"
sleep 8
nmcli -t -f DEVICE,STATE,CONNECTION device | grep wlan0
iw dev wlan0 link

echo "=== the firmware's side of it ==="
dmesg | grep -iE "ath10k|wlan0|crashed|recovered|txpower|-108" | head -60

echo "=== did it survive? ==="
ip -4 addr show wlan0 | grep inet || echo "no address"

echo "=== RESTORE: get back on something usable ==="
# Try the hotspot, then the previous connection, so the tablet is not stranded.
timeout 60 nmcli connection up "HONOR Magic7 Pro" || true
nmcli -t -f DEVICE,STATE,CONNECTION device | grep wlan0
echo "=== DONE ==="
