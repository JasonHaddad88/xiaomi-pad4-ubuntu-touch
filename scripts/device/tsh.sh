#!/usr/bin/env bash
# Send a file of shell commands to the halium initrd telnet shell (192.168.2.15:23) and print the output.
# usage: tsh.sh <cmdfile> [wait_seconds]
f="$1"; w="${2:-6}"
{ tr -d '\r' < "$f"; sleep "$w"; } | timeout $((w+6)) nc 192.168.2.15 23 | tr -cd '\11\12\40-\176'
