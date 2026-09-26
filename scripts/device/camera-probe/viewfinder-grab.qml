// Minimal camera client that screenshots its own viewfinder.
//
// Two jobs. First, it takes the camera app out of the equation: if this shows a
// picture the fault is app-side, if it does not the fault is in the plugin, the
// HAL or graphics. Second, grabToImage() yields a PNG of what was actually
// rendered, which can be pulled to a PC and measured - the only way to tell
// "no data" (uniform zero) from "dark room" (low mean, non-zero variance).
// See measure-png.py.
//
// Run it as a LEGACY app so it gets a working Qt platform. There is no wayland
// QPA plugin on this device (only eglfs, linuxfb, minimal, minimalegl,
// offscreen, mir1server, ubuntumirclient, vnc, xcb) and running qmlscene
// straight from SSH dies at platform init. Drop a .desktop file in
// ~/.local/share/applications:
//
//   [Desktop Entry]
//   Type=Application
//   Name=CamTest
//   Exec=qmlscene /home/phablet/viewfinder-grab.qml
//   Icon=camera
//
// then:  lomiri-app-launch camtest
//
// Kill every other camera client first (pkill -f qmlscene; pkill -f
// lomiri-camera-app) or they collide and the second open fails with
// "camera_open failed. rc = -16" / "Camera 0 is already open".

import QtQuick 2.12
import QtMultimedia 5.9

Item {
    id: root
    width: 800
    height: 600

    Camera {
        id: cam
        captureMode: Camera.CaptureStillImage
        cameraState: Camera.ActiveState
    }

    VideoOutput {
        id: vo
        anchors.fill: parent
        source: cam
    }

    Timer {
        interval: 7000
        running: true
        repeat: false
        onTriggered: {
            // status 8 = ActiveStatus, state 2 = ActiveState.
            // A valid srcRect with a black picture means the camera is streaming
            // but the frames are empty - look at the Android side, not at Qt.
            console.log("GRAB srcRect=" + vo.sourceRect.width + "x" + vo.sourceRect.height
                        + " state=" + cam.cameraState + " status=" + cam.cameraStatus)
            vo.grabToImage(function (r) {
                console.log("GRAB videoOutput saved=" + r.saveToFile("/home/phablet/vf.png"))
            })
        }
    }
}
