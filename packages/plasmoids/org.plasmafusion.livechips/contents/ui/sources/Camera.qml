// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.pipewire.monitor as Monitor

import "../../code/chips.js" as Chips

// A camera in use, as Plasma's own camera indicator sees it (kpipewire's camera monitor: camera
// nodes that run), and which apps read it: kpipewire knows the cameras only, so whenever their
// state changes one `pw-dump` gives the video streams linked from them (Chips.cameraApps). Without
// pw-dump (pipewire-utils) the rows name the camera instead. main.qml loads this file with a
// Loader, so a system without kpipewire's QML module has no camera chip.
Item {
    id: camera

    readonly property bool inUse: monitor.detectionAvailable && monitor.runningCount > 0
    // The names of the running cameras ("Integrated Camera").
    property var cameras: []
    // The apps reading them, when pw-dump could tell.
    property var apps: []

    function refresh(): void {
        const names = [];
        for (let i = 0; i < rows.count; ++i) {
            const row = rows.objectAt(i);
            if (row && row.running && row.name !== "" && names.indexOf(row.name) < 0) {
                names.push(row.name);
            }
        }
        cameras = names;
        if (inUse) {
            // The app's stream links to the camera a moment after the camera starts: a second look.
            lookUp();
            again.restart();
        } else {
            again.stop();
            apps = [];
        }
    }
    function lookUp(): void {
        exec.run("pw-dump 2>/dev/null", (code, out) => {
            if (!camera.inUse) {
                return;
            }
            let objects = null;
            try {
                objects = JSON.parse(out);
            } catch (e) {
                objects = null;
            }
            camera.apps = Chips.cameraApps(objects);
            console.info("livechips: camera apps " + JSON.stringify(camera.apps) + " (" + (code === 0 ? "pw-dump" : "no pw-dump") + ")");
        });
    }
    onInUseChanged: Qt.callLater(refresh)

    Timer {
        id: again
        interval: 1500
        onTriggered: camera.lookUp()
    }

    Exec {
        id: exec
    }

    Monitor.MediaMonitor {
        id: monitor
        role: Monitor.MediaRole.Camera
    }
    Instantiator {
        id: rows
        model: monitor
        delegate: QtObject {
            required property var model
            required property string display
            readonly property string name: String(display || "")
            readonly property bool running: model.state === Monitor.NodeState.Running
            onRunningChanged: Qt.callLater(camera.refresh)
            onNameChanged: Qt.callLater(camera.refresh)
        }
        onObjectAdded: Qt.callLater(camera.refresh)
        onObjectRemoved: Qt.callLater(camera.refresh)
    }
}
