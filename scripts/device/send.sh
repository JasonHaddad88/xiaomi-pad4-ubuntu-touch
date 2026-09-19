#!/usr/bin/env bash
# Stream a .gz file to the halium initrd: device runs  nc -l | gunzip | dd of=<target>
# Completion = dd's exit stats ("records out") appear in /tmp/<tag>.log; then the keep-alive sleep is killed.
# usage: send.sh <file.gz> <device-target-path> <port> <tag>
set -u
gz="$1"; target="$2"; port="$3"; tag="$4"
printf '%s\n' "rm -f /tmp/$tag.log; setsid sh -c \"sleep 100000 | nc -l -p $port | gunzip -c | dd of=$target bs=1M 2>/tmp/$tag.log\" </dev/null >/dev/null 2>&1 &" > "/tmp/$tag.start"
/tmp/tsh.sh "/tmp/$tag.start" 2 >/dev/null
sleep 1
t0=$(date +%s)
nc -N 192.168.2.15 "$port" < "$gz"
echo "  sent $(stat -c%s "$gz") bytes in $(( $(date +%s)-t0 ))s"
printf 'cat /tmp/%s.log 2>/dev/null\n' "$tag" > "/tmp/$tag.chk"
for i in $(seq 1 300); do
  out=$(/tmp/tsh.sh "/tmp/$tag.chk" 2)
  if printf '%s\n' "$out" | grep -q 'records out'; then
    printf '%s\n' "$out" | grep -E 'records|bytes|copied'
    printf 'killall sleep 2>/dev/null\n' > "/tmp/$tag.kill"; /tmp/tsh.sh "/tmp/$tag.kill" 1 >/dev/null
    echo "  device write done ($(( $(date +%s)-t0 ))s total)"; exit 0
  fi
  sleep 3
done
echo "TIMEOUT waiting for device write"; exit 1
