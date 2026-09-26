#!/bin/sh
# clover - create the missing 32-bit VNDK-SP directory in the Halium system image.
#
# WHY: the camera viewfinder is black because the 32-bit CameraService aborts with
# "gralloc-mapper is missing". The mapper impl is loaded into the *sphal* linker
# namespace, which resolves android.hardware.graphics.mapper@2.0.so through the
# *vndk* namespace, whose only system search path is /system/${LIB}/vndk-sp-28.
# Our Halium build shipped /system/lib64/vndk-sp-28 but never created the 32-bit
# /system/lib/vndk-sp-28, so 64-bit resolves and 32-bit cannot. The library is not
# missing from the device - it sits in /system/lib, which that namespace may not
# search.
#
# The /android loop device is mounted WRITE-PROTECTED, so "mount -o remount,rw"
# fails and the image must be modified as a copy and swapped in. Run on the device
# with sudo. Nothing live is touched until the final rename, and the previous image
# is kept.
set -e

IMG=/userdata/android-rootfs.img
NEW=$IMG.new
MNT=/mnt/newsys

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

echo "1. copy the live image"
rm -f "$NEW"
cp "$IMG" "$NEW"

echo "2. mount the copy read-write"
LOOP=$(losetup -f --show "$NEW")
mkdir -p "$MNT"
mount -t ext4 "$LOOP" "$MNT"

echo "3. mirror the 64-bit VNDK-SP set in 32-bit"
mkdir -p "$MNT/system/lib/vndk-sp-28"
n=0
for f in $(ls "$MNT/system/lib64/vndk-sp-28/"); do
    # 6 of the 31 have no 32-bit build (libRS*, libbcinfo, libblas,
    # libcompiler_rt) - all RenderScript, irrelevant to gralloc.
    if [ -f "$MNT/system/lib/$f" ]; then
        cp -a "$MNT/system/lib/$f" "$MNT/system/lib/vndk-sp-28/$f"
        n=$((n + 1))
    fi
done
chmod 755 "$MNT/system/lib/vndk-sp-28"
echo "   copied $n libraries"

echo "4. unmount and check"
sync
umount "$MNT"
losetup -d "$LOOP"
e2fsck -fn "$NEW" || { echo "FILESYSTEM CHECK FAILED - not swapping"; exit 1; }

echo "5. swap in (the previous image is kept as .old)"
mv "$IMG" "$IMG.old"
mv "$NEW" "$IMG"

echo "done - reboot to apply."
echo "revert:  mv $IMG $IMG.vndk && mv $IMG.old $IMG && reboot"
