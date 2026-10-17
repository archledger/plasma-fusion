#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offscreen tests of the live chips' QML (not installed), on the staged package:

- the camera source (sources/Camera.qml) with a stand-in kpipewire camera monitor and a stand-in
  Exec: the apps reading a camera are looked up again while it runs (an app that starts reading a
  running camera changes no node's state), and none are left once it stops;
- the chips (ChipRow.qml) from the keyboard: Tab reaches the Keep awake chip, the recording's stop
  button and the capsule, and Space or Return runs each;
- names from other apps and from logins, and Spectacle's time, shown as plain text (not markup), in
  the panel (InUsePanel.qml) and the chips;
- the status items (sources/StatusItems.qml, with Plasma's D-Bus module) against a stand-in
  watcher and items on a private bus (fake_watcher.py): an item that unregisters while its
  properties are read is not shown when the reply comes after, one that stays is; a recording's
  time runs on with nothing logged, and the widget's debug output (for the session tests) has it;
  a recording with sound (Spectacle 6.8's title) is a recording too;
- the island (Island.qml, board Island.dc.html), its own window: shown while the bar is hidden and
  gone when it shows; 4 px from the top and centred on the screen, compact 32 px high and at least
  132 wide, not a pop-up of the bar's window (plasmashell keeps the bar shown while one of its
  pop-ups is visible); the bubble 6 px beside it with the island still centred; opened in place 400 px wide,
  where a click on Mute asks the app's microphone to mute and Esc closes it; in a full-screen
  window the 14 px row of dots.

  STAGE=$PWD/build/stage tools/build.sh livechips
  QT_QPA_PLATFORM=offscreen dbus-run-session --config-file=packages/kwin/tests/offscreen/session-bus.conf -- \
    python3 packages/plasmoids/org.plasmafusion.livechips/tests/chips_qml_test.py build/stage
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading

from PySide6.QtCore import (QEventLoop, QLoggingCategory, QMetaObject, QObject, QPoint, QSize, Qt, QTimer, QUrl, Q_ARG, Q_RETURN_ARG,
                            QtMsgType, Slot, qInstallMessageHandler)
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
# The island on a 1440 x 900 screen, its content set by the test; declared in a window, as the
# widget's is in the bar's.
ISLAND_HARNESS = """import QtQuick
import QtQuick.Window
Window {
    id: harness
    width: 200
    height: 60
    visible: true
    property bool barHidden: true
    property var content: ({ mode: "compact", items: ["privacy"], dots: ["camera", "microphone"] })
    property var actions: []
    property var rows: [{ app: "Firefox", kinds: ["camera", "microphone"], action: "mute", microphones: [0], session: "", login: "" }]
    readonly property var window: island
    FusionMetrics { id: m }
    Island {
        id: island
        metrics: m
        dark: true
        barHidden: harness.barHidden
        screenGeometry: Qt.rect(0, 0, 1440, 900)
        content: harness.content
        rows: harness.rows
        recording: null
        keepAwakeLeft: null
        media: null
        onRowAction: row => harness.actions = harness.actions.concat([row.action])
    }
    function find(item, test) {
        if (test(item)) return item;
        for (const child of item.children) {
            const found = find(child, test);
            if (found) return found;
        }
        return null;
    }
    // The black shape (the frame's first child) and the bubble (its second), in screen pixels.
    function state() {
        const frame = island.mainItem, body = frame.children[0], bubble = frame.children[1];
        return JSON.stringify({ visible: island.visible, mode: island.mode, x: island.x, y: island.y, frame: frame.width,
                                transient: island.transientParent !== null,
                                body: [island.x + body.x, island.y + body.y, body.width, body.height],
                                bubble: bubble.visible ? [island.x + bubble.x, bubble.width] : null,
                                px32: m.px(32), px132: m.px(132), px400: m.px(400), px14: m.px(14), px6: m.px(6) });
    }
    // The centre of the visible button with this text, in the island window's pixels.
    function button(text) {
        const label = find(island.mainItem, i => i.text === text && i.visible && i.width > 0);
        if (!label) return "";
        const c = label.mapToItem(island.mainItem, label.width / 2, label.height / 2);
        return JSON.stringify([Math.round(c.x), Math.round(c.y)]);
    }
    function openIt() { island.open("privacy"); }
    // The rows' names shown in the opened island.
    function names() {
        const out = [];
        const walk = item => {
            if (item.text !== undefined && item.visible && /^App /.test(String(item.text))) out.push(String(item.text));
            for (const child of item.children) walk(child);
        };
        walk(island.mainItem);
        return JSON.stringify(out);
    }
    function peek() { island.peek = true; }
}
"""
# Markup in an app's name, a login's user and Spectacle's time.
TEXT_HARNESS = """import QtQuick
import QtQuick.Layouts
import QtQuick.Window
Window {
    width: 800
    height: 400
    visible: true
    FusionMetrics { id: m }
    RowLayout {
        InUsePanel {
            id: panel
            metrics: m
            dark: true
            microphoneApps: [{ name: "<b>Zoom</b>", muted: false, setMuted: function (v) {} }]
            cameraApps: []
            cameraNames: []
            cameraInUse: false
            portalSessions: [{ key: "k", kind: "screen", app: "<i>Meet</i>", window: true, input: false }]
            logins: [{ id: "1", user: "<u>r</u>", host: "h", ssh: true, since: 0 }]
        }
        ChipRow {
            metrics: m
            dark: true
            capsule: ({ kinds: ["microphone"], tintKind: "microphone" })
            recording: ({ time: "<b>0:42</b>" })
            keepAwakeOn: false
            keepAwakeLeft: ({ hours: 0, minutes: 0, total: 0 })
            panelOpen: false
        }
    }
    TextMetrics { id: measure }
    // Every Text showing markup: drawn as plain text when it is as wide as its text measured as
    // plain text (markup read as such draws only the tagged word).
    property string shown: ""
    function texts() {
        const out = [];
        function walk(item) {
            if (item instanceof Text && item.text.indexOf("<") >= 0) {
                measure.font = item.font;
                measure.text = item.text;
                out.push({ text: item.text, plain: Math.abs(item.implicitWidth - measure.advanceWidth) <= 2 });
            }
            for (const child of item.children) {
                walk(child);
            }
        }
        walk(contentItem);
        shown = JSON.stringify(out);
    }
}
"""
STATUS_HARNESS = """import QtQuick
import "contents/ui/sources"
Item {
    readonly property string portal: JSON.stringify(items.portal.map(s => s.kind + " " + s.app))
    readonly property string recording: items.recording ? items.recording.time : ""
    StatusItems { id: items }
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


class Fake:
    """fake_watcher.py, with its output lines."""

    def __init__(self):
        self.proc = subprocess.Popen([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fake_watcher.py")],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        self.lines = []
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        for line in self.proc.stdout:
            self.lines.append(line.strip())

    def send(self, command):
        self.proc.stdin.write(command + "\n")
        self.proc.stdin.flush()

    def expect(self, line, ms=3000):
        for _ in range(ms // 50):
            if line in self.lines:
                return True
            wait(50)
        return False

    def stop(self):
        self.proc.stdin.close()
        self.proc.wait(timeout=5)


def until(test, ms=3000):
    for _ in range(ms // 50):
        if test():
            return True
        wait(50)
    return test()


def status_items(root, i18n):
    if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        raise SystemExit("the status items part needs a private session bus (dbus-run-session)")
    fake = Fake()
    if not fake.expect("ready"):
        raise SystemExit("fake_watcher.py did not start: %s" % fake.lines)
    # Messages of the widget's own, from here on.
    messages = []

    def handler(mode, context, text):
        if "livechips:" in text:
            messages.append((mode, context.category, text))
    qInstallMessageHandler(handler)
    try:
        engine = QQmlEngine()
        engine.rootContext().setContextObject(i18n)
        component = QQmlComponent(engine, QUrl.fromLocalFile(os.path.join(root, "status_harness.qml")))
        harness = component.create()
        if harness is None:
            raise SystemExit("status harness: " + "; ".join(e.toString() for e in component.errors()))
        wait(300)

        def portal():
            return json.loads(harness.property("portal"))
        # Item 1 unregisters while its properties are read; their reply comes after.
        fake.send("add 1 screen hold")
        check(fake.expect("getall 1"), "a new item is read")
        fake.send("drop 1")
        wait(300)
        fake.send("release 1")
        check(fake.expect("released 1 1"), "its reply goes once it unregistered")
        wait(500)
        check(portal() == [], "an item that unregistered while it was read is not shown (%s)" % portal())
        # Item 2 stays.
        fake.send("add 2 screen")
        check(until(lambda: portal() == ["screen Firefox"]), "an item that stays is shown (%s)" % portal())
        fake.send("drop 2")
        check(until(lambda: portal() == []), "and goes when it unregisters (%s)" % portal())
        # A recording runs on: nothing logged by default.
        fake.send("add 3 recording")
        check(until(lambda: harness.property("recording") == "0:41"), "a recording shows its time (%s)" % harness.property("recording"))
        for _ in range(3):
            fake.send("tick 3")
            wait(150)
        check(until(lambda: harness.property("recording") == "0:44"), "its time runs on (%s)" % harness.property("recording"))
        quiet = [m for m in messages if m[0] not in (QtMsgType.QtWarningMsg, QtMsgType.QtCriticalMsg, QtMsgType.QtFatalMsg)]
        check(quiet == [], "nothing is logged while it runs (%s)" % [m[2] for m in quiet][:3])
        # The debug output the session tests read.
        QLoggingCategory.setFilterRules("org.plasmafusion.livechips.debug=true")
        fake.send("tick 3")
        check(until(lambda: any('"time":"0:45"' in m[2] and m[1] == "org.plasmafusion.livechips" for m in messages)),
              "with the widget's debug output on, the status items are logged")
        QLoggingCategory.setFilterRules("")
        # A recording with sound (Spectacle 6.8's title, "Spectacle is Recording with Sound").
        fake.send("drop 3")
        check(until(lambda: harness.property("recording") == ""), "the recording ends with its item (%s)" % harness.property("recording"))
        fake.send("add 4 sound")
        check(until(lambda: harness.property("recording") == "0:41"),
              "a recording with sound shows its time too (%s)" % harness.property("recording"))
    finally:
        qInstallMessageHandler(None)
        fake.stop()


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
        with open(os.path.join(root, "contents/ui/text_harness.qml"), "w") as f:
            f.write(TEXT_HARNESS)
        with open(os.path.join(root, "status_harness.qml"), "w") as f:
            f.write(STATUS_HARNESS)
        with open(os.path.join(root, "contents/ui/island_harness.qml"), "w") as f:
            f.write(ISLAND_HARNESS)

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

        # ---- names as plain text
        text = QQmlApplicationEngine()
        text.rootContext().setContextObject(i18n)
        text.load(QUrl.fromLocalFile(os.path.join(root, "contents/ui/text_harness.qml")))
        if not text.rootObjects():
            raise SystemExit("text harness failed to load")
        wait(200)
        call(text.rootObjects()[0], "texts")
        shown = json.loads(text.rootObjects()[0].property("shown") or "[]")
        check(sorted(t["text"] for t in shown) == ["<b>0:42</b>", "<b>Zoom</b>", "<i>Meet</i>", "<u>r</u> from h"],
              "the names with markup are on the screen (%s)" % [t["text"] for t in shown])
        check(shown and all(t["plain"] for t in shown), "names and the recording's time are shown as plain text (%s)" % shown)

        # ---- the island
        isl = QQmlApplicationEngine()
        isl.rootContext().setContextObject(i18n)
        isl.load(QUrl.fromLocalFile(os.path.join(root, "contents/ui/island_harness.qml")))
        if not isl.rootObjects():
            raise SystemExit("island harness failed to load")
        h = isl.rootObjects()[0]

        def island():
            return json.loads(QMetaObject.invokeMethod(h, "state", Qt.DirectConnection, Q_RETURN_ARG("QVariant")))
        wait(700)
        s = island()
        check(s["visible"] and s["mode"] == "compact", "the bar hidden, a call: the island shows, compact (%s)" % s)
        bx, by, bw, bh = s["body"]
        check(by == 4 and bh == s["px32"] and bw >= s["px132"], "  4 px from the top, 32 px high, at least 132 wide (%s)" % s["body"])
        check(abs(bx + bw / 2 - 720) <= 1, "  centred on the screen (%s)" % s["body"])
        check(not s["transient"], "  not a pop-up of the bar's window (no transient parent: the bar can hide)")
        h.setProperty("content", {"mode": "compact", "items": ["privacy", "music"], "dots": ["camera", "microphone"]})
        wait(700)
        s = island()
        bx, by, bw, bh = s["body"]
        check(s["bubble"] is not None and s["bubble"][0] == bx + bw + s["px6"] and s["bubble"][1] == s["px32"],
              "two things: the second in a 32 px bubble 6 px beside it (%s)" % s)
        check(abs(bx + bw / 2 - 720) <= 1, "  the island still centred on the screen (%s)" % s["body"])
        check(s["x"] <= bx and s["bubble"][0] + s["bubble"][1] <= s["x"] + s["frame"],
              "  both inside the island's window (%s)" % s)
        h.setProperty("content", {"mode": "compact", "items": ["privacy"], "dots": ["camera", "microphone"]})
        call(h, "openIt")
        wait(900)
        s = island()
        check(s["mode"] == "opened" and s["body"][2] == s["px400"], "a click opens it in place, 400 px wide (%s)" % s)
        check(abs(s["body"][0] + s["body"][2] / 2 - 720) <= 1, "  still centred (%s)" % s["body"])
        at = QMetaObject.invokeMethod(h, "button", Qt.DirectConnection, Q_RETURN_ARG("QVariant"), Q_ARG("QVariant", "Mute"))
        window = h.property("window")
        if at:
            QTest.mouseClick(window, Qt.LeftButton, Qt.NoModifier, QPoint(*json.loads(at)))
            wait(100)
        actions = h.property("actions")
        actions = actions.toVariant() if hasattr(actions, "toVariant") else actions
        check(list(actions or []) == ["mute"], "  Mute asks the app's microphone to mute (%s at %s)" % (actions, at))
        window.requestActivate()
        wait(200)
        QTest.keyClick(window, Qt.Key_Escape)
        wait(900)
        check(island()["mode"] == "compact", "  Esc closes it (%s)" % island()["mode"])
        # Five apps at once: a row for each, none left out.
        h.setProperty("rows", [{"app": "App %d" % i, "kinds": ["microphone"], "action": "mute", "microphones": [i], "session": "", "login": ""}
                               for i in range(1, 6)])
        call(h, "openIt")
        wait(900)
        shown = json.loads(QMetaObject.invokeMethod(h, "names", Qt.DirectConnection, Q_RETURN_ARG("QVariant")))
        check(shown == ["App %d" % i for i in range(1, 6)], "  five apps: a row for each (%s)" % shown)
        QTest.keyClick(window, Qt.Key_Escape)
        wait(900)
        h.setProperty("rows", [{"app": "Firefox", "kinds": ["camera", "microphone"], "action": "mute", "microphones": [0], "session": "", "login": ""}])
        # The window resized from outside (as a platform does when the focus changes its flags; the
        # Dialog then sizes its main item to the window): while it opens, and once it has opened.
        call(h, "openIt")
        wait(100)
        window.resize(QSize(100, 30))
        wait(900)
        s = island()
        check(s["body"][2] == s["px400"] and abs(s["x"] + s["frame"] / 2 - 720) <= 1 and s["frame"] >= s["body"][2],
              "  resized from outside while it opens: opened and centred all the same (%s)" % s)
        window.resize(QSize(100, 30))
        wait(300)
        QTest.keyClick(window, Qt.Key_Escape)
        wait(900)
        call(h, "openIt")
        wait(900)
        s = island()
        check(s["mode"] == "opened" and abs(s["x"] + s["frame"] / 2 - 720) <= 1 and s["frame"] >= s["body"][2],
              "  resized from outside once opened: closed and opened again, its window fits (%s)" % s)
        QTest.keyClick(window, Qt.Key_Escape)
        wait(900)
        h.setProperty("content", {"mode": "dots", "items": [], "dots": ["camera", "microphone"]})
        wait(900)
        s = island()
        check(s["mode"] == "dots" and s["body"][3] == s["px14"] and s["body"][1] == 4, "a full-screen window: the 14 px row of dots (%s)" % s)
        # The pointer on the dots shows the island; full screen ends and comes back: the dots again.
        call(h, "peek")
        wait(600)
        check(island()["mode"] == "compact", "  the pointer on them: the compact island (%s)" % island()["mode"])
        h.setProperty("content", {"mode": "compact", "items": ["privacy"], "dots": ["camera", "microphone"]})
        wait(300)
        h.setProperty("content", {"mode": "dots", "items": [], "dots": ["camera", "microphone"]})
        wait(900)
        check(island()["mode"] == "dots", "  full screen ends and comes back: the dots again (%s)" % island()["mode"])
        h.setProperty("barHidden", False)
        wait(900)
        check(not island()["visible"], "the bar shows: the island goes (%s)" % island())

        # ---- the status items, on a private bus
        status_items(root, i18n)
        del app
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("chips_qml_test: %d checks, %d failed" % (checks, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
