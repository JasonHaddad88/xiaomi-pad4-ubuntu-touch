#!/usr/bin/env bash
# Phase 2 build deps for halium-boot (kernel + boot image). Run as ROOT.
# Minimal set — Java (openjdk-8) and lib32/i386 are only needed for the full system.img build,
# added later if required.   wsl -u root -e bash -c "tr -d '\r' < <this> | bash -s"
set -uxo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
apt-get update
apt-get install -y --no-install-recommends \
  build-essential bc bison flex libssl-dev libncurses-dev zlib1g-dev \
  gawk zip unzip cpio kmod libelf-dev rsync ccache pkg-config python3 \
  imagemagick libxml2-utils
echo "----- versions -----"
gcc --version | head -1; flex --version; bison --version | head -1
echo "DONE: build-deps"
