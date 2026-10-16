#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The dock's menu (contents/ui/DockMenu.qml) on Plasma's real menu, for the test hook pick().

QT_QPA_PLATFORM=offscreen python3 packages/plasmoids/org.plasmafusion.dock/tests/menu_test.py
Requires PySide6 and libplasma's org.kde.plasma.extras QML module.

The virtual-session scenarios choose menu entries with the dock's debugAction "pick:TEXT", which
DockMenu.pick() runs. Plasma's menu (libplasma's QMenuProxy) gets KAcceleratorManager, which puts
an "&" into each entry's text when the menu opens, so the text an entry shows is not the text it
was added with. Checked on an open menu: the shown texts did change, and pick() still finds an
entry by the text it was added with and runs its action (one with no action too); a disabled
entry, and a text no entry has, are not picked.
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
Window {
    width: 400; height: 300; visible: true
    property var menu: null
    property string ran: ""
    Item { id: anchor; x: 20; y: 240; width: 40; height: 40 }
    function build() {
        const c = Qt.createComponent(Qt.resolvedUrl("DockMenu.qml"));
        menu = c.createObject(this, { visualParent: anchor });
        menu.addAction("Close", "window-close-symbolic", () => { ran = "Close"; }, {});
        menu.addAction("End Task…", "process-stop-symbolic", () => { ran = "End Task…"; }, {});
        menu.addAction("Cancel", "dialog-cancel-symbolic", null, {});
        menu.addAction("Resize", "", () => { ran = "Resize"; }, { enabled: false });
        menu.openRelative();
    }
    function open() { return menu !== null && menu.status === 1; }
    // The texts the entries show now (an entry of items: {text, item}, or the item itself).
    function texts() { return menu.items.map(e => (e.item || e).text).join(" | "); }
    function pick(text) { return menu.pick(text); }
}
""".encode(), QUrl.fromLocalFile(str(ui / "harness.qml")))
window = component.create()
if window is None:
    sys.exit("could not load the harness: " + "; ".join(e.toString() for e in component.errors()))

window.build()
wait_for(lambda: window.open(), "the menu opens")
shown = window.texts()
print("INFO shown texts:", shown)
check("&" in shown, "the open menu's entries show other texts than they were added with (accelerators)")
check(window.pick("End Task…") is True, "pick() finds an entry by the text it was added with")
wait_for(lambda: window.property("ran") == "End Task…", "the picked entry's action runs")
check(True, "  and runs its action")

window.setProperty("ran", "")
window.build()
wait_for(lambda: window.open(), "the menu opens again")
check(window.pick("Cancel") is True, "an entry with no action is picked (it closes the menu)")
wait_for(lambda: not window.open(), "the menu closes after Cancel")
check(window.property("ran") == "", "  and nothing runs")

window.build()
wait_for(lambda: window.open(), "the menu opens a third time")
check(window.pick("Resize") is False, "a disabled entry is not picked")
check(window.pick("Nothing like it") is False, "a text no entry has is not picked")
QTest.qWait(200)
check(window.property("ran") == "", "  and nothing runs for either")

print(f"dock menu: {checks} checks passed")
