#!/usr/bin/env bash
# Read-only pull of a partition from the halium initrd shell to the PC, md5-verified.
# usage: pull.sh <partlabel> <outdir> <port>
set -u
p="$1"; out="$2"; port="$3"
dev="/dev/disk/by-partlabel/$p"
mkdir -p "$out"
# start a detached sender on the device: dd | nc -l
{ printf 'setsid sh -c "dd if=%s bs=1M 2>/dev/null | nc -l -p %s" </dev/null >/dev/null 2>&1 &\n' "$dev" "$port"; sleep 2; } \
  | timeout 5 nc 192.168.2.15 23 >/dev/null 2>&1
sleep 1
timeout 180 nc -d 192.168.2.15 "$port" > "$out/$p.img"
local_md5=$(md5sum "$out/$p.img" | cut -d' ' -f1)
size=$(stat -c%s "$out/$p.img")
dev_md5=$( { printf 'md5sum %s\n' "$dev"; sleep 6; } | timeout 10 nc 192.168.2.15 23 | tr -cd '\11\12\40-\176' | grep -oE '^[0-9a-f]{32}' | head -1 )
if [ -n "$dev_md5" ] && [ "$dev_md5" = "$local_md5" ]; then v=OK; else v="MISMATCH(dev=$dev_md5)"; fi
printf '%-9s %10s bytes  md5 %s  %s\n' "$p" "$size" "$local_md5" "$v"
