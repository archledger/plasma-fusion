#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The dock's menu (contents/ui/DockMenu.qml) on Plasma's real menu, for the test hook pick:TEXT.

QT_QPA_PLATFORM=offscreen python3 packages/plasmoids/org.plasmafusion.dock/tests/menu_test.py
Requires PySide6 and libplasma's org.kde.plasma.extras QML module.

The virtual-session scenarios choose menu entries with the dock's debugAction "pick:TEXT": the dock
keeps the last menu's actions (DockMenu.actions) and runs the one MenuPick.find() returns
(contents/code/menu-pick.js). They must outlive the menu: in a session no input has reached, Qt
cannot open a grabbing popup and closes the menu at once (qtbase 6.11
qwaylandxdgshellintegration.cpp), and the menu destroys itself when closed. And they must keep the
text they were added with: Plasma's menu gets KAcceleratorManager, which puts an "&" into each
item's text when it opens. Checked: an open menu's items do show other texts; once the menu is
destroyed, as a closed one destroys itself, its kept actions still give the entry added with a text and running it runs
the entry's action (one with no action, such as Cancel, too); a disabled entry, and a text the
menu has not, give nothing.
"""

import os
from pathlib import Path
import sys
import time

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
here = Path(__file__).resolve().parent
ui = here.parent / "contents/ui"

from PySide6.QtCore import QUrl  # noqa: E402
from PySide6.QtQml import QQmlComponent, QQmlEngine  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402
from PySide6.QtWidgets import QApplication  # noqa: E402

checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


def wait_for(predicate, message, seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        QTest.qWait(50)
        if predicate():
            return
    raise AssertionError(message)


# QMenuProxy shows a QMenu: a widget, so a QApplication.
app = QApplication(sys.argv)
engine = QQmlEngine()
component = QQmlComponent(engine)
component.setData("""
import QtQuick
import QtQuick.Window
import "../code/menu-pick.js" as MenuPick
Window {
    width: 400; height: 300; visible: true
    property QtObject menu: null
    // As the dock keeps them (lastMenuActions).
    property var actions: []
    property string ran: ""
    Item { id: anchor; x: 20; y: 240; width: 40; height: 40 }
    function build() {
        const c = Qt.createComponent(Qt.resolvedUrl("DockMenu.qml"));
        menu = c.createObject(this, { visualParent: anchor });
        actions = menu.actions;
        menu.addAction("Close", "window-close-symbolic", () => { ran = "Close"; }, {});
        menu.addAction("End Task…", "process-stop-symbolic", () => { ran = "End Task…"; }, {});
        menu.addAction("Cancel", "dialog-cancel-symbolic", null, {});
        menu.addAction("Resize", "", () => { ran = "Resize"; }, { enabled: false });
        menu.openRelative();
    }
    function open() { return menu !== null && menu.status === 1; }
    function shown() {
        const out = [];
        for (let i = 0; i < menu.content.length; ++i) {
            out.push(menu.content[i].text);
        }
        return out.join(" | ");
    }
    // As a closed menu does (DockMenu destroys itself when its status turns Closed).
    function drop() { menu.destroy(); }
    function gone() { return menu === null; }
    // What the dock's pick:TEXT does: find the action, run it; "none" when there is none.
    function pick(text) {
        const action = MenuPick.find(actions, text);
        if (!action) {
            return "none";
        }
        if (action.run) {
            action.run();
        }
        return "picked";
    }
}
""".encode(), QUrl.fromLocalFile(str(ui / "harness.qml")))
window = component.create()
if window is None:
    sys.exit("could not load the harness: " + "; ".join(e.toString() for e in component.errors()))

window.build()
wait_for(lambda: window.open(), "the menu opens")
shown = window.shown()
print("INFO shown texts:", shown)
check("&" in shown and "End Task…" not in shown.split(" | "),
      "the open menu's items show other texts than they were added with (accelerators)")
window.drop()
wait_for(lambda: window.gone(), "the menu is destroyed")
check(True, "the menu is gone (destroyed)")
check(window.pick("End Task…") == "picked", "its kept actions still give the entry added with that text")
check(window.property("ran") == "End Task…", "  and running it runs the entry's action")
window.setProperty("ran", "")
check(window.pick("Cancel") == "picked", "an entry with no action (Cancel) is found too")
check(window.property("ran") == "", "  and nothing runs for it")
check(window.pick("Resize") == "none", "a disabled entry gives nothing")
check(window.pick("Nothing like it") == "none", "a text the menu has not gives nothing")
check(window.property("ran") == "", "  and nothing runs for either")

print(f"dock menu: {checks} checks passed")
