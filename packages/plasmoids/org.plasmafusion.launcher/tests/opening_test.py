#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise main.qml's opening handlers on controlled windows, loaders and output replies.

The production QML blocks run unchanged except for their external screen/config/bus objects.
This tests request ownership, not rendering, Kicker's models or real D-Bus transport.
Run: python3 packages/plasmoids/org.plasmafusion.launcher/tests/opening_test.py
"""
import argparse
import json
import os
from pathlib import Path
import sys
import tempfile

os.environ["QT_QPA_PLATFORM"] = "offscreen"
os.environ["QT_QUICK_BACKEND"] = "software"
from PySide6.QtCore import Q_ARG, Q_RETURN_ARG, QMetaObject, QUrl, Qt  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlComponent, QQmlEngine  # noqa: E402

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1] / "contents/ui/main.qml")
source = parser.parse_args().source.read_text()
opening = source.split("    // The card is built on idle;", 1)[1].split("    // BEGIN tablet sheet", 1)[0]
sheet = source.split("    // BEGIN tablet sheet", 1)[1].split("    // END tablet sheet", 1)[0]
expanded = source.split("    // `expanded` mirrors", 1)[1].split("    LauncherWindow {", 1)[0]
# Preserve handlers and control flow; substitute only their external dependencies.
logic = ("    // The card is built on idle;" + opening + "    // BEGIN tablet sheet" + sheet
         + "    // `expanded` mirrors" + expanded)
logic = logic.replace("Qt.application.screens", "root.screens").replace("DBus.SessionBus", "bus")
logic = logic.replace("Plasmoid.configuration", "root.config").replace("Plasmoid.containment", "root.containment")

fixture = r"""
import QtQuick
Item {
    id: root
    property bool tablet: false
    property bool expanded: false
    readonly property bool menuOpen: launcherWindow.visible || sheetWindow.visible
    property var config: ({dimBackground: true, glass: "full"})
    property var containment: ({screen: 0})
    property rect screenGeometry: Qt.rect(0, 0, 1440, 900)
    property rect availableScreenRect: Qt.rect(0, 34, 1440, 866)
    property var screens: [{}]
    property string searchText: ""
    property double lastClosed: 0
    property int framesDrawn: 0
    property string opened: ""
    property var modes: []
    property bool synchronousCard: false
    property bool synchronousSheet: false
    function placeWindows(area) {}
    function screenArea() { return ({x: 0, y: 0, width: 1440, height: 900}); }
    QtObject { id: motion; property int popupIn: 1; property int popupOut: 1 }
    Item { id: backdrop; visible: false; property rect area; property color dimColor }
    Item {
        id: card
        property var pal: ({dark: true})
        function openMode(mode, argument) { root.opened = argument; root.modes.push(mode); }
    }
    Item {
        id: sheetContent
        property real progress: 0
        function reset() {}
        function focusSearch(argument) { root.opened = argument; }
    }
    Item {
        id: launcherWindow
        visible: false
        property var card: null
        property bool cardWanted: false
        signal cardReady()
        function requestActivate() {}
        onCardWantedChanged: if (cardWanted && root.synchronousCard) root.readyCard()
        onVisibleChanged: if (!visible) root.syncExpanded()
    }
    QtObject {
        id: bus
        property var replies: []
        function asyncCall(call, success, failure) { replies.push({success: success, failure: failure}); }
        function finish(index, failed) {
            if (failed) replies[index].failure();
            else replies[index].success({value: ""});
        }
    }
    function readyCard() { launcherWindow.card = card; launcherWindow.cardReady(); }
    function readySheet() { sheetWindow.sheet = sheetContent; sheetWindow.sheetReady(); }
    function exercise(name: string): string {
        if (name.startsWith("output")) { readyCard(); screens = [{}, {}]; }
        if (name.startsWith("sheet")) tablet = true;
        synchronousCard = name === "card-immediate";
        synchronousSheet = name === "sheet-immediate";
        if (name.includes("owned")) expanded = true;
        else if (name.endsWith("expanded")) { expanded = true; expanded = false; }
        else if (name === "card-prewarm") prepareCard();
        else open("search", "old");
        if (name.includes("replace")) open("search", "new");
        else if (name === "sheet-direct-close" || name === "sheet-owned-direct") closeSheet();
        else if (name.endsWith("close") || name.endsWith("error")) close();
        else if (name.endsWith("posture")) tablet = !tablet;
        else if (name.endsWith("switch")) { tablet = !tablet; open("search", "new"); }
        if (name.startsWith("output")) {
            if (name.includes("replace")) bus.finish(1, false);
            bus.finish(0, name.endsWith("error"));
        } else if (name.startsWith("card") && !name.endsWith("immediate")) readyCard();
        else if (!name.startsWith("card") && !name.endsWith("immediate")) readySheet();
        if (name === "card-posture" || name === "card-switch") readySheet();
        if (name === "sheet-switch") readyCard();
        const result = {card: launcherWindow.visible, sheet: sheetWindow.visible,
                        opened: opened, modes: modes, warmed: launcherWindow.cardWanted,
                        sheetWarmed: sheetWindow.sheetWanted};
        if (name.includes("owned")) {
            result.cancelledExpanded = expanded;
            expanded = true;
            if (tablet) readySheet();
            else {
                readyCard();
                if (screens.length > 1) bus.finish(bus.replies.length - 1, false);
            }
            result.nextCard = launcherWindow.visible;
            result.nextSheet = sheetWindow.visible;
            result.nextTablet = tablet;
        }
        return JSON.stringify(result);
    }
    // PRODUCTION_LOGIC
}
""".replace("    // PRODUCTION_LOGIC", logic)

app = QGuiApplication(sys.argv[:1])
failures = []
cases = {"card-close": False, "output-close": False, "output-error": False,
         "sheet-close": False, "sheet-posture": False, "card-posture": False,
         "output-posture": False, "card-replace": True, "output-replace": True,
         "sheet-replace": True, "card-open": True, "output-open": True, "sheet-open": True,
         "card-expanded": False, "output-expanded": False, "sheet-expanded": False,
         "sheet-direct-close": False, "output-replace-error": True, "card-switch": True,
         "sheet-switch": True, "card-prewarm": False, "card-immediate": True, "sheet-immediate": True,
         "card-owned-close": False, "output-owned-close": False, "sheet-owned-close": False,
         "sheet-owned-direct": False, "card-owned-posture": False, "output-owned-posture": False,
         "sheet-owned-posture": False}
with tempfile.TemporaryDirectory(prefix="pf-launcher-opening-") as directory:
    path = Path(directory)
    (path / "SheetWindow.qml").write_text("""import QtQuick
Item {
    property var launcher
    property string glass
    property rect area
    property real topBar
    property int screenNumber
    property bool sheetWanted: false
    onSheetWantedChanged: if (sheetWanted && launcher.synchronousSheet) launcher.readySheet()
    property var sheet: null
    property bool active: false
    signal sheetReady()
    signal closeRequested()
    signal frameSwapped()
    function requestActivate() {}
}
""")
    engine = QQmlEngine()
    component = QQmlComponent(engine)
    component.setData(fixture.encode(), QUrl.fromLocalFile(str(path / "Fixture.qml")))
    if component.isError():
        raise AssertionError("; ".join(error.toString() for error in component.errors()))
    for name, should_open in cases.items():
        root = component.create()
        if root is None:
            raise AssertionError("; ".join(error.toString() for error in component.errors()))
        result = json.loads(QMetaObject.invokeMethod(root, "exercise", Qt.DirectConnection,
                                                    Q_RETURN_ARG(str), Q_ARG(str, name)))
        shown = result["card"] or result["sheet"]
        expected_argument = "new" if "replace" in name or name.endswith("switch") else "old"
        passed = shown == should_open and (not should_open or result["opened"] == expected_argument)
        if should_open:
            expected_sheet = (name.startswith("sheet") and not name.endswith("switch")) or name == "card-switch"
            passed &= result["sheet"] == expected_sheet and result["card"] != expected_sheet
            if not expected_sheet:
                passed &= bool(result["modes"]) and result["modes"][-1] == "search"
        if "owned" in name:
            passed &= (not result["cancelledExpanded"] and result["nextSheet"] == result["nextTablet"]
                       and result["nextCard"] != result["nextTablet"])
        passed &= result["sheetWarmed"] if name.startswith("sheet") else result["warmed"] or name.startswith("output")
        print(("PASS" if passed else "FAIL"), name, json.dumps(result))
        if not passed:
            failures.append(name)
        root.deleteLater()
        app.processEvents()
    del component
    del engine
if failures:
    raise SystemExit("Opening request failures: " + ", ".join(failures))
print(f"Opening requests: {len(cases)} cases passed")
