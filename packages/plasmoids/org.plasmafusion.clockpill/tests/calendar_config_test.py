#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The Calendar settings page follows enabledCalendarPlugins when it changes from outside
(Defaults, Reset) and after a click. Offscreen, with the native calendar provider manager.
Run: QT_QPA_PLATFORM=offscreen python3 tests/calendar_config_test.py"""
import os
from pathlib import Path
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QMetaObject, QUrl  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlComponent, QQmlEngine  # noqa: E402
from PySide6.QtQuick import QQuickItem  # noqa: E402,F401  (registers the QQuickItem* converter)

PAGE = Path(os.environ.get("PF_CALENDAR_CONFIG_PAGE", Path(__file__).resolve().parent.parent / "contents/ui/ConfigCalendar.qml"))
failures = 0


def check(condition, message):
    global failures
    print(("PASS " if condition else "FAIL ") + message)
    failures += 0 if condition else 1


def delegates(root):
    """The provider check delegates: items with a checked and a text property."""
    found = []

    def walk(item):
        for child in item.childItems():
            if child.metaObject().indexOfProperty("checked") >= 0 and child.property("text"):
                found.append(child)
            walk(child)
    walk(root)
    return found


app = QGuiApplication(sys.argv)
engine = QQmlEngine()
component = QQmlComponent(engine, QUrl.fromLocalFile(str(PAGE)))
page = component.create()
if page is None:
    print("cannot load the page: " + "; ".join(e.toString() for e in component.errors()))
    sys.exit(0 if any("is not installed" in e.toString() for e in component.errors()) else 1)
app.processEvents()
items = delegates(page.property("contentItem") or page)
if not items:
    print("SKIP no calendar providers installed")
    sys.exit(0)
first = items[0]
name = first.property("text")


def enabled():
    return [str(i) for i in (page.property("cfg_enabledCalendarPlugins") or [])]


def checks():
    app.processEvents()
    return {i.property("text"): bool(i.property("checked")) for i in delegates(page.property("contentItem") or page)}


# Reset/Defaults from outside: none, then everything the click below will produce, then none.
page.setProperty("cfg_enabledCalendarPlugins", [])
check(not any(checks().values()), "no provider checked after the key is emptied (Defaults)")
# A click: the delegate toggles, then reports clicked().
target = [i for i in delegates(page.property("contentItem") or page) if i.property("text") == name][0]
target.setProperty("checked", True)
QMetaObject.invokeMethod(target, "clicked")
app.processEvents()
after_click = enabled()
check(len(after_click) == 1, "a click enables that provider in the key (%s)" % after_click)
page.setProperty("cfg_enabledCalendarPlugins", [])
check(not checks().get(name, True), "Defaults after a click unchecks it again (the check follows the model)")
page.setProperty("cfg_enabledCalendarPlugins", after_click)
check(checks().get(name, False), "Reset to the saved value checks it again")
print("calendar config: %d failure(s)" % failures)
sys.exit(1 if failures else 0)
