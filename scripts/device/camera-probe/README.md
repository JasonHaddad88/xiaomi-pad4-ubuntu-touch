# Looking at the tablet's screen without looking at the tablet

These exist because the camera viewfinder was black and there was no way to see it
from here. Mir 1.8 has no `wlr-screencopy`, `mirscreencast` is refused by the
compositor (`not accepted by server`), and `grim`/`wayland-info` are not installed
on a read-only rootfs. They are useful for any future graphics or sensor work, not
just the camera.

## The four things that made the camera debuggable

| problem | answer |
|---|---|
| the screen is off, so nothing renders | [`hold-display.py`](hold-display.py) - `keepDisplayOn` dies with the D-Bus connection, so `busctl call` is useless; hold it open |
| the greeter is up, so the app is not focused | `busctl --user call com.lomiri.LomiriGreeter /com/lomiri/LomiriGreeter com.lomiri.LomiriGreeter HideGreeter` |
| is the app *actually* rendering? | `com.lomiri.Shell.FocusInfo.isPidFocused` - returns a real boolean, unlike "the process exists" |
| what is on the screen? | [`viewfinder-grab.qml`](viewfinder-grab.qml) - QML grabs itself with `grabToImage()` |
| is that black frame dark, or dead? | [`measure-png.py`](measure-png.py) - uniform zero is no data; a dark room has noise |

## Running arbitrary test QML on the device

`lomiri-app-launch <appid>` launches installed clicks over SSH. For your own code,
register it as a **legacy** app - a `.desktop` file in
`~/.local/share/applications/` - which is how it gets a usable Qt platform:

```
[Desktop Entry]
Type=Application
Name=CamTest
Exec=qmlscene /home/phablet/viewfinder-grab.qml
Icon=camera
```

then `lomiri-app-launch camtest`. Add `Exec=env QT_LOGGING_RULES=*.debug=true ...`
for Qt internals. **Delete the .desktop file afterwards** or a stray entry shows up
in the app drawer.

## Traps

- **Kill leftovers before every measurement.** Two live camera clients collide:
  `camera_open failed. rc = -16` / `Camera 0 is already open`. One polluted capture
  produced a completely wrong conclusion ("the app never starts the preview").
- **Running the app binary directly over SSH proves nothing** - it dies at Qt
  platform init long before reaching the code under test.
- `pgrep -x` silently matches nothing for names longer than 15 characters
  (`lomiri-camera-app`); use `pgrep -f`.
- `strings` is not installed; use `grep -a`.
- Redirecting a `sudo lxc-attach ... logcat` into a file can leave it root-owned -
  pipe it through `cat`, or `chmod` it afterwards.

## Typical session

```sh
pkill -f qmlscene; pkill -f lomiri-camera-app
nohup python3 ~/hold-display.py 120 &
busctl --user call com.lomiri.LomiriGreeter /com/lomiri/LomiriGreeter \
    com.lomiri.LomiriGreeter HideGreeter
lomiri-app-launch camtest
# ... wait, then pull ~/vf.png and:
python3 measure-png.py vf.png
```
