#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Run quick settings' command runner (contents/ui/services/Exec.qml) on Plasma's executable engine.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 tests/exec_test.py
Requires PySide6 and Plasma's plasma5support QML module.

The same command started twice before the first run has finished must run twice and answer each
caller (the start-up of the tablet policy reads the same keys twice); the finished signal names the
command as given.
"""

from pathlib import Path
import sys
import time

from PySide6.QtCore import Q_ARG, QMetaObject, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest

here = Path(__file__).resolve().parent
services = here.parent / "contents/ui/services"
app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
checks = 0

HARNESS = b"""
import QtQuick
Item {
    property var done: []
    property var answers: []
    Exec {
        id: exec
        onFinished: (command, code, out) => done.push(command + "|" + code + "|" + out.trim())
    }
    function twice(command: string) {
        exec.run(command, (code, out) => answers.push("first:" + code + ":" + out.trim()));
        exec.run(command, (code, out) => answers.push("second:" + code + ":" + out.trim()));
    }
    function once(command: string) {
        exec.run(command);
    }
}
"""


def wait_for(predicate, message, seconds=5):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        QTest.qWait(20)
        if predicate():
            return
    raise AssertionError(message)


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


def js_list(item, name):
    value = item.property(name)
    return list(value.toVariant() if hasattr(value, "toVariant") else value or [])


component = QQmlComponent(engine)
# The harness sits next to Exec.qml, so the type resolves from the folder as in the widget.
component.setData(HARNESS, QUrl.fromLocalFile(str(services / "ExecHarness.qml")))
item = component.create()
if item is None:
    raise SystemExit("harness did not load: " + "; ".join(e.toString() for e in component.errors()))

slow = "sh -c 'sleep 0.4; echo done'"
QMetaObject.invokeMethod(item, "twice", Q_ARG(str, slow))
wait_for(lambda: len(js_list(item, "done")) >= 2, "the second identical command did not run", 8)
QTest.qWait(600)
finished = js_list(item, "done")
check(len(finished) == 2, "an identical command started while the first runs runs twice")
check(finished == [slow + "|0|done"] * 2, "the finished signal names the command as given, with its output")
check(sorted(js_list(item, "answers")) == ["first:0:done", "second:0:done"], "each caller gets its own answer")

QMetaObject.invokeMethod(item, "once", Q_ARG(str, "sh -c 'exit 3'"))
wait_for(lambda: len(js_list(item, "done")) >= 3, "a command without a handler did not finish")
check(js_list(item, "done")[2] == "sh -c 'exit 3'|3|", "a run without a handler reports its exit code")
print(f"exec: {checks} checks passed")
