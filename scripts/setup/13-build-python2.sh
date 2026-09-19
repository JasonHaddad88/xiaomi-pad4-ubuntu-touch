#!/usr/bin/env bash
# AOSP-9 build scripts require Python 2 (#!/usr/bin/env python2 and python==2); Ubuntu 26.04 ships none.
# Build python2.7.18 from source (~17 MB) -> /usr/local, symlink /usr/bin/python2, and make a build-local
# shim dir (/opt/halium-py2bin) with python+python2 so we can put python2 first on PATH ONLY for the Halium
# build (system `python` stays python3). Run as ROOT.
#   wsl -u root -e bash -c "tr -d '\r' < <this> | bash -s"
set -uo pipefail
V=2.7.18
PREFIX=/usr/local
CF="-fcommon -O2 -std=gnu17 -Wno-error -Wno-implicit-int -Wno-implicit-function-declaration -Wno-int-conversion"
if [ ! -x "$PREFIX/bin/python2.7" ]; then
  cd /tmp
  [ -f "/tmp/Python-$V.tgz" ] || curl -fL --retry 10 --retry-all-errors --retry-delay 3 -o "/tmp/Python-$V.tgz" \
    "https://www.python.org/ftp/python/$V/Python-$V.tgz"
  rm -rf "/tmp/Python-$V"; tar xf "/tmp/Python-$V.tgz"
  cd "/tmp/Python-$V"
  ./configure --prefix="$PREFIX" --enable-unicode=ucs4 --with-ensurepip=no CFLAGS="$CF" >/tmp/py2-configure.log 2>&1
  if ! make -j"$(nproc)" >/tmp/py2-make.log 2>&1; then
    echo "PYTHON2 BUILD FAILED — tail of /tmp/py2-make.log:"; tail -30 /tmp/py2-make.log; exit 1
  fi
  make altinstall >/tmp/py2-install.log 2>&1
fi
ln -sf "$PREFIX/bin/python2.7" /usr/bin/python2
SHIM=/opt/halium-py2bin
mkdir -p "$SHIM"
ln -sf "$PREFIX/bin/python2.7" "$SHIM/python"
ln -sf "$PREFIX/bin/python2.7" "$SHIM/python2"
echo "--- result ---"
/usr/bin/python2 --version
"$SHIM/python" --version
echo "build-local shim dir: $SHIM (prepend to PATH during the Halium build)"
