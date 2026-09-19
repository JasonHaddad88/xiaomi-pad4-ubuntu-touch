#!/usr/bin/env bash
# AOSP-9 prebuilt clang (clang-4691093) is dynamically linked against libtinfo.so.5 / libncurses.so.5,
# which Ubuntu 26.04 doesn't ship (it has .so.6). Symlink the .5 sonames to .6 so the old clang loads.
# (The terminfo ABI clang uses is compatible across 5/6.)  Run as ROOT.
#   wsl -u root -e bash -c "tr -d '\r' < <this> | bash -s"
set -uo pipefail
DIR=/usr/lib/x86_64-linux-gnu
link5() {  # $1 = lib basename (libtinfo / libncurses / libncursesw)
  local six
  six=$(ldconfig -p | awk -v n="$1.so.6" 'index($0,n){print $NF; exit}')
  [ -z "$six" ] && six="$DIR/$1.so.6"
  if [ -e "$six" ]; then ln -sf "$six" "$DIR/$1.so.5"; echo "linked $DIR/$1.so.5 -> $six"
  else echo "skip $1 (.so.6 not found)"; fi
}
link5 libtinfo
link5 libncurses
link5 libncursesw
ldconfig
echo '--- result ---'
ls -l "$DIR"/libtinfo.so.5 "$DIR"/libncurses.so.5 2>/dev/null
