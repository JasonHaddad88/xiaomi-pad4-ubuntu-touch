#!/bin/sh
# clover: make the persist partition visible inside the Android container.
#
# The Qualcomm sensor daemon refuses to start without
# /persist/sensors/sensors_settings:
#   libsensor1: check_sensors_enabled: open error: settings file
#               "/persist/sensors/sensors_settings", errno 2
#   libsensor1: check_sensors_enabled: Sensors enabled = false
# and then the sensors HAL enumerates nothing, so sensorfw reports
#   "HYBRIS CTL invalid sensor type: 1" / no such sensor "accelerometeradaptor"
# and rotation never works.
#
# The partition IS mounted at /mnt/vendor/persist, but Ubuntu Touch 24.04's LXC
# container config has no persist bind entry (16.04 had
# "lxc.mount.entry = /persist persist bind bind,optional"), so the container's
# /persist stays empty. We bind it ourselves.
#
# Added 2026-09-20 for the 24.04 port. Remove the unit to revert.
set -e

# wait for the android container
i=0
while [ $i -lt 60 ]; do
    lxc-info -n android 2>/dev/null | grep -q RUNNING && break
    sleep 1
    i=$((i+1))
done

# nothing to do if it is already there
if lxc-attach --clear-env -n android -- /system/bin/ls /persist/sensors >/dev/null 2>&1; then
    echo "clover-persist-bind: /persist already populated in the container"
    exit 0
fi

lxc-attach --clear-env -n android -- /system/bin/toybox mount -o bind /mnt/vendor/persist /persist
echo "clover-persist-bind: bound /mnt/vendor/persist -> container /persist"

# the sensor daemon and HAL cached the failure; restart them so they re-read it
lxc-attach --clear-env -n android -- /system/bin/setprop ctl.restart vendor.sensors || true
sleep 6
lxc-attach --clear-env -n android -- /system/bin/setprop ctl.restart vendor.sensors-hal-1-0 || true
sleep 8

# sensorfw started before the sensors existed and cached "no such sensor"
systemctl restart sensorfwd || true
echo "clover-persist-bind: sensor stack restarted"
