#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Privacy details in the real Plasma tooltip, without a desktop session.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 privacy_hover_test.py STAGE_HOME [FONT_POINTS]
"""
import json
from pathlib import Path
import shutil
import sys
import tempfile

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from chips_qml_test import I18n, call, wait


HARNESS = """import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.core as PlasmaCore
Window {
    id: harness
    width: 800; height: 600
    visible: true
    property string appName: "Sound Recorder"
    property bool muted: false
    property bool camera: false
    property bool microphone: true
    property string state: ""
    FusionMetrics { id: m; area: Qt.rect(0, 0, 800, 600) }
    readonly property var apps: microphone ? [{name: appName, muted: muted,
        setMuted: function(value) { harness.muted = value; }}] : []
    PlasmaCore.ToolTipArea {
        id: tip
        x: 20; y: 20; width: 30; height: 30
        interactive: true
        timeout: -1
        location: PlasmaCore.Types.TopEdge
        mainItem: InUsePanel {
            id: hoverPanel
            hover: true
            metrics: m; dark: true
            microphoneApps: harness.apps
            cameraApps: harness.camera ? [harness.appName] : []
            cameraNames: []; cameraInUse: harness.camera
            portalSessions: []; logins: []
        }
    }
    RowLayout {
        x: 20; y: 200
        InUsePanel {
            id: clickPanel
            metrics: m; dark: true
            microphoneApps: harness.apps
            cameraApps: harness.camera ? [harness.appName] : []
            cameraNames: []; cameraInUse: harness.camera
            portalSessions: []; logins: []
        }
    }
    function showHover() { tip.showToolTip(); }
    function hideHover() { tip.hideToolTip(); }
    function inspect() {
        function panelState(panel) {
            const texts = [];
            function walk(item) {
                if (item instanceof Text && item.visible) {
                    const position = item.mapToItem(panel, 0, 0);
                    texts.push({text: item.text, truncated: item.truncated,
                        format: item.textFormat, plain: Text.PlainText,
                        x: position.x, y: position.y, width: item.width, height: item.height});
                }
                for (const child of item.children) walk(child);
            }
            walk(panel);
            return {width: panel.width, implicitWidth: panel.implicitWidth,
                    height: panel.height, rows: panel.rows, texts: texts};
        }
        state = JSON.stringify({hover: panelState(hoverPanel), click: panelState(clickPanel),
                                expectedWidth: m.px(328), textScale: m.ts, shown: hoverPanel.shown});
    }
}
"""


def main():
    package = Path(sys.argv[1]).resolve() / ".local/share/plasma/plasmoids/org.plasmafusion.livechips"
    app = QGuiApplication(sys.argv[:1])
    font_points = float(sys.argv[2]) if len(sys.argv) > 2 else None
    if font_points is not None:
        font = app.font()
        font.setPointSizeF(font_points)
        app.setFont(font)
    failures = []
    checks = 0

    def check(ok, label):
        nonlocal checks
        checks += 1
        print(("PASS " if ok else "FAIL ") + label)
        if not ok:
            failures.append(label)

    with tempfile.TemporaryDirectory(prefix="privacy-hover-") as work:
        root = Path(work) / "package"
        shutil.copytree(package, root)
        fixture = root / "contents/ui/privacy_harness.qml"
        fixture.write_text(HARNESS)
        engine = QQmlApplicationEngine()
        i18n = I18n()
        engine.rootContext().setContextObject(i18n)
        engine.load(QUrl.fromLocalFile(str(fixture)))
        if not engine.rootObjects():
            raise SystemExit("privacy hover fixture failed to load")
        window = engine.rootObjects()[0]

        def inspect():
            call(window, "inspect")
            return json.loads(window.property("state"))

        wait(100)
        call(window, "showHover")
        wait(400)
        state = inspect()
        if font_points is not None:
            expected_scale = max(0.85, min(1.6, font_points / 9.75))
            check(abs(state["textScale"] - expected_scale) < 0.001,
                  f"requested font size changes text scale ({state['textScale']})")
        check(state["shown"], "the real Plasma tooltip shows the privacy panel")
        check(abs(state["hover"]["width"] - state["expectedWidth"]) <= 1,
              f"hover uses the panel's intended width ({state['hover']['width']} vs {state['expectedWidth']})")
        check(abs(state["hover"]["width"] - state["click"]["width"]) <= 1,
              "hover and click allocate the same content width")
        for text in ("Sound Recorder", "Microphone", "Mute"):
            check(any(t["text"] == text and not t["truncated"] for t in state["hover"]["texts"]),
                  f"hover displays {text!r} without truncation")

        window.setProperty("appName", "A recorder with a very long application name <not markup> " * 2)
        wait(100)
        state = inspect()
        for mode in ("hover", "click"):
            title = next(t for t in state[mode]["texts"] if t["text"] == window.property("appName"))
            check(not title["truncated"] and title["format"] == title["plain"],
                  f"{mode}: long application name is complete plain text")
            check(state[mode]["height"] > 100, f"{mode}: rows grow to hold a wrapped name")
            check(all(t["x"] >= -1 and t["y"] >= -1
                      and t["x"] + t["width"] <= state[mode]["width"] + 1
                      and t["y"] + t["height"] <= state[mode]["height"] + 1
                      for t in state[mode]["texts"]), f"{mode}: text stays inside the panel")
        window.setProperty("muted", True)
        window.setProperty("camera", True)
        wait(100)
        state = inspect()
        for mode in ("hover", "click"):
            check(any(t["text"] == "Microphone, muted" and not t["truncated"] for t in state[mode]["texts"]),
                  f"{mode}: microphone state updates while shown")
            check(any(t["text"] == "Camera" for t in state[mode]["texts"]),
                  f"{mode}: a newly active resource appears")
        window.setProperty("camera", False)
        window.setProperty("microphone", False)
        wait(100)
        state = inspect()
        for mode in ("hover", "click"):
            check(state[mode]["rows"] == [], f"{mode}: stopped resources leave no stale rows")
        call(window, "hideHover")
        window.close()
        del engine
    del app
    print(f"privacy hover: {checks} checks, {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
