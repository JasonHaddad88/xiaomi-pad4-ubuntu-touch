#!/bin/bash
# Build linux-postmarketos-qcom-sdm660 7.0.14-r101 the same way as r100:
# temporarily patch the pristine aport, build, restore.
set -u
LOG=~/osm-diag/buildR101.out
exec > >(tee $LOG) 2>&1
echo "=== start $(date +%H:%M) ==="
L=~/cprh-port/linux
P=~/.local/var/pmbootstrap/cache_git/pmaports
A=$P/device/testing/linux-postmarketos-qcom-sdm660
PB=~/.local/bin/pmbootstrap
REPO="/mnt/c/Users/User/Desktop/Projects/Xiaomi Pad 4 Ubuntu Touch"

cd $P
[ -z "$(git status --short -- $A)" ] || { echo "aport not pristine, stopping"; git status --short -- $A; exit 1; }

# patches: everything on r101 since the v7.0.14-sdm660 base
BASE=$(cd $L && git log --format=%H --grep='^base: sdm660-mainline v7.0.14-sdm660' -1 r101)
[ -n "$BASE" ] || BASE=$(cd $L && git merge-base release r101)
echo "base: $(cd $L && git log --oneline -1 $BASE)"
OUTP=$(mktemp -d)
(cd $L && git format-patch -q -o $OUTP $BASE..r101)
N=$(ls $OUTP/*.patch | wc -l); echo "patches: $N"
cp $OUTP/*.patch $A/

# APKBUILD: pkgrel, patch list in source=
sed -i 's/^pkgrel=.*/pkgrel=101/' $A/APKBUILD
LIST=$(cd $OUTP && ls *.patch | sed 's/^/\t/')
python3 - "$A/APKBUILD" "$LIST" <<'PY'
import sys
p, lst = sys.argv[1], sys.argv[2]
s = open(p).read()
old = '\tconfig-$_flavor.aarch64\n"'
assert s.count(old) == 1
s = s.replace(old, '\tconfig-$_flavor.aarch64\n' + lst + '\n"')
open(p, 'w').write(s)
PY

# config
C=$A/config-postmarketos-qcom-sdm660.aarch64
sed -i 's/^# CONFIG_MODULE_ALLOW_BTF_MISMATCH is not set/CONFIG_MODULE_ALLOW_BTF_MISMATCH=y/' $C
sed -i 's/^# CONFIG_QCOM_MPM is not set/CONFIG_QCOM_MPM=y/' $C
# the three options r100's recipe also set (read back from r100's IKCONFIG)
sed -i 's/^CONFIG_ARM_QCOM_CPUFREQ_HW=m/CONFIG_ARM_QCOM_CPUFREQ_HW=y/' $C
sed -i 's/^CONFIG_QCOM_SPM=m/CONFIG_QCOM_SPM=y/' $C
grep -q '^CONFIG_QCOM_CPR3=' $C || echo 'CONFIG_QCOM_CPR3=y' >> $C
grep -E "^CONFIG_(MODULE_ALLOW_BTF_MISMATCH|QCOM_MPM|ARM_QCOM_CPUFREQ_HW|QCOM_SPM|QCOM_CPR3)=" $C
grep -E "^pkgrel" $A/APKBUILD
echo "patches in source=: $(grep -c '\.patch$' $A/APKBUILD)"

$PB checksum linux-postmarketos-qcom-sdm660 > /dev/null 2>&1 || { echo "checksum failed"; }
$PB build --force linux-postmarketos-qcom-sdm660 > ~/osm-diag/buildR101.log 2>&1
RC=$?
echo "build rc=$RC"
APK=$(find ~/.local/var/pmbootstrap/packages -name 'linux-postmarketos-qcom-sdm660-7.0.14-r101.apk' | head -1)
if [ $RC = 0 ] && [ -n "$APK" ]; then
	cp "$APK" ~/osm-diag/kept/linux-postmarketos-qcom-sdm660-7.0.14-r101.apk
	md5sum ~/osm-diag/kept/linux-postmarketos-qcom-sdm660-7.0.14-r101.apk
	mkdir -p "$REPO/device-fixes/nura/kernel-r101"
	cp $OUTP/*.patch "$REPO/device-fixes/nura/kernel-r101/"
	cp $C "$REPO/device-fixes/nura/kernel-r101/config-r101.aarch64"
	rm -f "$APK"
	echo "=== built r101 $(date +%H:%M) ==="
else
	tail -30 ~/osm-diag/buildR101.log
fi

# restore the aport
cd $P && git checkout -- $A && rm -f $A/*.patch
echo "aport restored, changes left: $(git status --short -- $A | wc -l)"
rm -rf $OUTP
