#!/usr/bin/env bash
# Minimal deps needed to `repo init` + `repo sync` the Halium tree.
# NOT the full build toolchain (that decision — host 26.04 vs Halium Docker — is deferred to build time).
# Run as root:  wsl -u root -e bash -c "tr -d '\r' < <this> | bash -s"
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

apt-get update
apt-get install -y --no-install-recommends \
  git git-lfs curl wget ca-certificates gnupg \
  python3 python-is-python3 xz-utils rsync less

git lfs install --system || true

echo "----- versions -----"
git --version
python3 --version
curl --version | head -1
echo "DONE: sync-deps"
