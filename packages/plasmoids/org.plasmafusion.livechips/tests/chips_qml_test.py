#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offscreen tests of the live chips' QML (not installed), on the staged package:

- the camera source (sources/Camera.qml) with a stand-in kpipewire camera monitor and a stand-in
  Exec: the apps reading a camera are looked up again while it runs (an app that starts reading a
  running camera changes no node's state), and none are left once it stops;
- the chips (ChipRow.qml) from the keyboard: Tab reaches the Keep awake chip, the recording's stop
  button and the capsule, and Space or Return runs each.

  STAGE=$PWD/build/stage tools/build.sh livechips
  QT_QPA_PLATFORM=offscreen python3 packages/plasmoids/org.plasmafusion.livechips/tests/chips_qml_test.py build/stage
"""
import os
import shutil
import sys
import tempfile

from PySide6.QtCore import QEventLoop, QMetaObject, QObject, Qt, QTimer, QUrl, Q_ARG, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine, QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest

PACKAGE = ".local/share/plasma/plasmoids/org.plasmafusion.livechips"


def subst(text, args):
    for i, a in enumerate(args):
        text = text.replace("%" + str(i + 1), str(a))
    return text


class I18n(QObject):
    """The i18n functions of a plasmoid's QML (KLocalizedContext), untranslated."""

    @Slot(str, str, result=str)
    @Slot(str, str, "QVariant", result=str)
    @Slot(str, str, "QVariant", "QVariant", result=str)
    def i18nc(self, context, text, *args):
        return subst(text, args)

    @Slot(str, str, str, result=str)
    @Slot(str, str, str, "QVariant", result=str)
    def i18ndc(self, domain, context, text, *args):
        return subst(text, args)


STUB_FILES = {
    # kpipewire's camera monitor: a list of camera nodes (display, state) and its counts. Each
    # monitor and Exec registers itself in Probe, for the test.
    "org/kde/pipewire/monitor/qmldir": "module org.kde.pipewire.monitor\nMediaRole 1.0 MediaRole.qml\n"
                                       "NodeState 1.0 NodeState.qml\nsingleton Probe 1.0 Probe.qml\n"
                                       "MediaMonitor 1.0 MediaMonitor.qml\n",
    # kpipewire's enums (MediaRole::Camera 2, pw_node_state idle 2 and running 3).
    "org/kde/pipewire/monitor/MediaRole.qml": "import QtQuick\nQtObject { enum Role { Unknown = -1, Camera = 2 } }\n",
    "org/kde/pipewire/monitor/NodeState.qml": "import QtQuick\nQtObject { enum State { Idle = 2, Running = 3 } }\n",
    "org/kde/pipewire/monitor/Probe.qml": "pragma Singleton\nimport QtQuick\nQtObject { property var monitor: null; property var exec: null }\n",
    "org/kde/pipewire/monitor/MediaMonitor.qml": "import QtQuick\nListModel {\n    property int role: -1\n"
                                                "    property bool detectionAvailable: true\n    property int runningCount: 0\n"
                                                "    Component.onCompleted: Probe.monitor = this\n}\n",
}
# Exec in place of the executable engine: counts the runs and answers with `output` (pw-dump).
STUB_EXEC = """import QtQuick
import org.kde.pipewire.monitor as Monitor
Item {
    property int runs: 0
    property string output: "[]"
    function run(command, handler) {
        runs += 1;
        if (handler) handler(0, output);
    }
    Component.onCompleted: Monitor.Probe.exec = this
}
"""
CAMERA_HARNESS = """import QtQuick
import org.kde.pipewire.monitor as Monitor
import "contents/ui/sources"
Item {
    readonly property var probe: Monitor.Probe
    // Plain values for the test (PySide converts no QML types).
    readonly property bool inUse: cam.inUse
    readonly property string apps: JSON.stringify(cam.apps)
    readonly property int runs: probe.exec ? probe.exec.runs : -1
    Camera { id: cam; refreshInterval: 200 }
    // A pw-dump graph: the camera and a video stream from it for each app.
    function graph(apps) {
        const out = [{ id: 30, type: "PipeWire:Interface:Node", info: { props: { "media.class": "Video/Source", "media.role": "Camera" } } }];
        apps.forEach((name, i) => {
            out.push({ id: 50 + i, type: "PipeWire:Interface:Node", info: { props: { "media.class": "Stream/Input/Video", "application.name": name } } });
            out.push({ id: 70 + i, type: "PipeWire:Interface:Link", info: { "output-node-id": 30, "input-node-id": 50 + i } });
        });
        return JSON.stringify(out);
    }
    function start(apps) {
        probe.exec.output = graph(apps);
        probe.monitor.append({ display: "Integrated Camera", state: Monitor.NodeState.Running });
        probe.monitor.runningCount = 1;
    }
    function readers(apps) { probe.exec.output = graph(apps); }
    function stop() {
        probe.monitor.setProperty(0, "state", Monitor.NodeState.Idle);
        probe.monitor.runningCount = 0;
    }
}
"""
KEYS_HARNESS = """import QtQuick
import QtQuick.Window
Window {
    width: 640
    height: 60
    visible: true
    property int awake: 0
    property int stops: 0
    property int capsules: 0
    readonly property bool awakeFocus: chips.keepAwakeItem.activeFocus
    readonly property bool stopFocus: chips.stopItem.activeFocus
    readonly property bool capsuleFocus: chips.capsuleItem.activeFocus
    FusionMetrics { id: m }
    ChipRow {
        id: chips
        anchors.centerIn: parent
        metrics: m
        dark: true
        capsule: ({ kinds: ["camera", "microphone"], tintKind: "" })
        recording: ({ time: "0:42" })
        keepAwakeOn: true
        keepAwakeLeft: ({ hours: 0, minutes: 24, total: 24 })
        panelOpen: false
        onKeepAwakeClicked: awake += 1
        onStopRecording: stops += 1
        onCapsuleClicked: capsules += 1
    }
    function focusFirst() { chips.keepAwakeItem.forceActiveFocus(Qt.TabFocusReason); }
}
"""

failed = 0
checks = 0


def check(ok, what):
    global failed, checks
    checks += 1
    failed += not ok
    print(("PASS " if ok else "FAIL ") + what)


def wait(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


def call(obj, name, *args):
    QMetaObject.invokeMethod(obj, name, Qt.DirectConnection, *[Q_ARG("QVariant", a) for a in args])


def main():
    stage = os.path.abspath(sys.argv[1])
    package = os.path.join(stage, PACKAGE)
    if not os.path.isdir(package):
        raise SystemExit("no staged live chips package in %s (tools/build.sh livechips)" % stage)
    work = tempfile.mkdtemp(prefix="livechips-qml-")
    try:
        shutil.copytree(package, os.path.join(work, "pkg"))
        root = os.path.join(work, "pkg")
        with open(os.path.join(root, "contents/ui/sources/Exec.qml"), "w") as f:
            f.write(STUB_EXEC)
        stubs = os.path.join(work, "stubs")
        for name, text in STUB_FILES.items():
            os.makedirs(os.path.dirname(os.path.join(stubs, name)), exist_ok=True)
            with open(os.path.join(stubs, name), "w") as f:
                f.write(text)
        with open(os.path.join(root, "camera_harness.qml"), "w") as f:
            f.write(CAMERA_HARNESS)
        with open(os.path.join(root, "contents/ui/keys_harness.qml"), "w") as f:
            f.write(KEYS_HARNESS)

        app = QGuiApplication(sys.argv[:1])
        i18n = I18n()

        # ---- the camera's readers
        engine = QQmlEngine()
        engine.addImportPath(stubs)
        engine.rootContext().setContextObject(i18n)
        component = QQmlComponent(engine, QUrl.fromLocalFile(os.path.join(root, "camera_harness.qml")))
        harness = component.create()
        if harness is None:
            raise SystemExit("camera harness: " + "; ".join(e.toString() for e in component.errors()))
        import json

        def apps():
            return json.loads(harness.property("apps"))
        wait(50)
        check(not harness.property("inUse") and harness.property("runs") == 0, "no camera running: no pw-dump")
        call(harness, "start", ["Zoom"])
        wait(100)
        check(harness.property("inUse") and apps() == ["Zoom"], "a camera starts: its reader (%s)" % apps())
        # Firefox starts reading the camera that runs already: no node changes state.
        call(harness, "readers", ["Zoom", "Firefox"])
        wait(700)
        check(apps() == ["Zoom", "Firefox"], "an app that starts reading a running camera is seen (%s)" % apps())
        call(harness, "readers", ["Firefox"])
        wait(700)
        check(apps() == ["Firefox"], "an app that stops reading it goes (%s)" % apps())
        call(harness, "stop")
        wait(100)
        runs = harness.property("runs")
        wait(700)
        check(not harness.property("inUse") and apps() == [] and harness.property("runs") == runs,
              "the camera stops: no readers, no more pw-dump")

        # ---- the chips from the keyboard
        keys = QQmlApplicationEngine()
        keys.rootContext().setContextObject(i18n)
        keys.load(QUrl.fromLocalFile(os.path.join(root, "contents/ui/keys_harness.qml")))
        if not keys.rootObjects():
            raise SystemExit("keys harness failed to load")
        window = keys.rootObjects()[0]
        window.requestActivate()
        wait(200)
        call(window, "focusFirst")
        wait(50)
        check(window.property("awakeFocus"), "the Keep awake chip takes the keyboard focus")
        QTest.keyClick(window, Qt.Key_Space)
        wait(50)
        check(window.property("awake") == 1, "Space on the Keep awake chip opens Keep awake")
        QTest.keyClick(window, Qt.Key_Tab)
        wait(50)
        check(window.property("stopFocus"), "Tab moves to the recording's stop button")
        QTest.keyClick(window, Qt.Key_Return)
        wait(50)
        check(window.property("stops") == 1, "Return on the stop button finishes the recording")
        QTest.keyClick(window, Qt.Key_Tab)
        wait(50)
        check(window.property("capsuleFocus"), "Tab moves to the capsule")
        QTest.keyClick(window, Qt.Key_Space)
        wait(50)
        check(window.property("capsules") == 1, "Space on the capsule opens the panel")
        del app
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("chips_qml_test: %d checks, %d failed" % (checks, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
