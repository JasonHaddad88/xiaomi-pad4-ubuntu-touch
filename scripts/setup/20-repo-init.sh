#!/usr/bin/env bash
# repo launcher + Halium 9.0 manifest init + clover local_manifest. Run as the NORMAL user (projkt88):
#   wsl -e bash -c "tr -d '\r' < <this> | bash -s"
# Does NOT sync (that's the long background job in 30-repo-sync.sh).
set -euxo pipefail

REPO_BIN="$HOME/.bin/repo"
WORK="$HOME/halium/halium-9.0"
LOCAL_MANIFEST_SRC="/mnt/c/Users/User/Desktop/Projects/Xiaomi Pad 4 Ubuntu Touch/manifests/clover.xml"

# 1. repo launcher on PATH
mkdir -p "$HOME/.bin"
if [ ! -x "$REPO_BIN" ]; then
  curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$REPO_BIN"
  chmod a+x "$REPO_BIN"
fi
grep -q '/.bin' "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/.bin:$PATH"

# 2. minimal git identity (PLACEHOLDER — replace with real name/email before forking/pushing in Phase 1)
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "clover porter"
git config --global user.email >/dev/null 2>&1 || git config --global user.email "clover@localhost"
git config --global color.ui false
git config --global --add safe.directory '*'

python3 --version

# 3. repo init Halium 9.0 (shallow to save bandwidth; NO project sync yet)
mkdir -p "$WORK"
cd "$WORK"
"$REPO_BIN" init -u https://github.com/Halium/android.git -b halium-9.0 --depth=1

# 4. drop in the clover local_manifest
mkdir -p .repo/local_manifests
cp "$LOCAL_MANIFEST_SRC" .repo/local_manifests/clover.xml
echo "----- .repo/local_manifests -----"
ls -la .repo/local_manifests/
echo "----- clover entries in resolved manifest -----"
"$REPO_BIN" manifest 2>/dev/null | grep -i clover || echo "(no clover lines — check manifest)"
echo "DONE: repo-init"
