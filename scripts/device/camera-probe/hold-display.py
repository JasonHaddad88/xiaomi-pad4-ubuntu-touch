#!/usr/bin/env python3
"""Hold the clover display on for N seconds (default 180).

repowerd releases a keepDisplayOn request as soon as the calling D-Bus connection
closes, so "busctl call ... keepDisplayOn" lights the screen for milliseconds and
is useless for testing. This keeps the connection open for the duration.

Run on the device:  nohup python3 hold-display.py 200 &
Pair it with:       busctl --user call com.lomiri.LomiriGreeter /com/lomiri/LomiriGreeter \
                        com.lomiri.LomiriGreeter HideGreeter

Both are needed. Lomiri suspends unfocused apps, so with the screen off or the
greeter up a camera or graphics test measures nothing at all - several hours were
lost to headless reproductions that could never have shown the bug. Confirm the
app is really rendering with:

    busctl --user call com.lomiri.Shell.FocusInfo /com/lomiri/Shell/FocusInfo \
        com.lomiri.Shell.FocusInfo isPidFocused u <pid>
"""
import sys
import time

import dbus

seconds = int(sys.argv[1]) if len(sys.argv) > 1 else 180

bus = dbus.SystemBus()
screen = dbus.Interface(
    bus.get_object("com.canonical.Unity.Screen", "/com/canonical/Unity/Screen"),
    "com.canonical.Unity.Screen",
)

request = screen.keepDisplayOn()
screen.setUserBrightness(1640)          # this panel is 0..4095, not 0..255
print("HELD id=%s" % request, flush=True)

time.sleep(seconds)

try:
    screen.removeDisplayOnRequest(request)
except Exception:
    pass
print("RELEASED", flush=True)
