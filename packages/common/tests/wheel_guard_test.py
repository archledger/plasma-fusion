#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Scroll safety (FusionWheelGuard): a page scroll passing over a wheel control does not change it.

  QT_QPA_PLATFORM=offscreen python3 packages/common/tests/wheel_guard_test.py

1. The rule, with given times: a wheel within 250 ms of entering is ignored with the rest of its
   scroll; the scroll ends after 1.5 s without a wheel or at a wheel 100 ms after the pointer moved
   again; a wheel that starts after the pointer has rested is taken, and so is the rest of it.
2. Real pointer events on a pill-like item (a hover-enabled MouseArea inside, as in the clock):
   a wheel right after the pointer arrives does nothing, one after a pause steps.
3. Every WheelHandler of the clock pill and of quick settings' bar asks a FusionWheelGuard first.
Needs PySide6 (Qt Quick, offscreen).
"""
import re
import sys
from pathlib import Path

from PySide6.QtCore import Q_ARG, Q_RETURN_ARG, QMetaObject, QPoint, QPointF, Qt, QUrl
from PySide6.QtGui import QGuiApplication, QWheelEvent
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[3]
COMMON = ROOT / "packages" / "common"
checks = 0
failures = []


def check(ok, message):
    global checks
    checks += 1
    print(("PASS " if ok else "FAIL ") + message)
    if not ok:
        failures.append(message)


app = QGuiApplication(sys.argv[:1])
guard_file = COMMON / "FusionWheelGuard.qml"
if not guard_file.is_file():
    print("FAIL packages/common/FusionWheelGuard.qml does not exist")
    sys.exit(1)

# ---- 1. The rule with given times
engine = QQmlEngine()
engine.addImportPath(str(COMMON))
unit = QQmlComponent(engine)
# The block's functions through the holder (PySide6 has no converter for a QML-defined type).
unit.setData(b"""import QtQuick
Item {
    FusionWheelGuard { id: guard }
    function pointerEntered(now: real): void { guard.pointerEntered(now); }
    function pointerMoved(now: real): void { guard.pointerMoved(now); }
    function pointerLeft(): void { guard.pointerLeft(); }
    function accept(now: real): bool { return guard.accept(now); }
}""",
             QUrl.fromLocalFile(str(COMMON / "unit.qml")))
holder = unit.create()
if holder is None:
    print("FAIL the block does not load: " + "; ".join(e.toString() for e in unit.errors()))
    sys.exit(1)
g = holder


def call(name, *args):
    if name == "accept":
        ret = QMetaObject.invokeMethod(g, "accept", Q_RETURN_ARG(bool), Q_ARG(float, float(args[0])))
        return ret
    if args:
        QMetaObject.invokeMethod(g, name, Q_ARG(float, float(args[0])))
    else:
        QMetaObject.invokeMethod(g, name)
    return None


def wheels(start, step, count):
    """accept() for count wheel events from start, step ms apart."""
    return [call("accept", start + k * step) for k in range(count)]


call("pointerEntered", 0)
got = wheels(40, 30, 6)
check(got == [False] * 6, "a scroll turning as the pointer arrives (first wheel 40 ms after entering) is ignored: %s" % got)
check(call("accept", 40 + 5 * 30 + 1400) is False, "a pause shorter than 1.5 s keeps ignoring that scroll")
check(call("accept", 40 + 5 * 30 + 1400 + 1600) is True, "after 1.5 s without a wheel, the next wheel counts")

call("pointerEntered", 10000)
wheels(10050, 30, 3)
call("pointerMoved", 10050 + 2 * 30 + 40)   # moved 40 ms after a wheel: part of the scroll
check(call("accept", 10200) is False, "a move within 100 ms of a wheel does not end the passing scroll")
call("pointerMoved", 10200 + 300)           # the wheel paused, the pointer moved again
check(call("accept", 10200 + 300 + 50) is False, "a wheel 50 ms after that move is still the old scroll")
check(call("accept", 10200 + 300 + 150) is True, "a wheel 150 ms after the move counts (Firefox's 100 ms)")

call("pointerEntered", 20000)
got = wheels(20000 + 400, 30, 8)
check(got == [True] * 8, "a scroll started 400 ms after the pointer arrived acts on every notch: %s" % got)
call("pointerLeft")
call("pointerEntered", 30000)
check(call("accept", 30000 + 249) is False and call("accept", 30000 + 249 + 1501 + 250) is True,
      "the settle time is 250 ms; leaving and entering again starts over")
call("pointerLeft")
check(call("accept", 40000) is False, "a wheel with no hover seen first counts as passing over")

# ---- 2. Real events on a pill-like item
view = QQuickView()
view.engine().addImportPath(str(COMMON))
view.setResizeMode(QQuickView.SizeRootObjectToView)
qml = b"""
import QtQuick
Item {
    width: 400; height: 200
    property int steps: 0
    Item {
        id: pill
        x: 100; y: 80; width: 200; height: 30
        // as in the clock pill: a hover-enabled MouseArea over the whole pill
        MouseArea { anchors.fill: parent; hoverEnabled: true }
        FusionWheelGuard { id: wheelGuard }
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                if (wheelGuard.accept(Date.now())) {
                    parent.parent.steps += 1;
                }
            }
        }
    }
}
"""
comp = QQmlComponent(view.engine())
comp.setData(qml, QUrl.fromLocalFile(str(COMMON / "pill.qml")))
root = comp.create()
if root is None:
    print("FAIL the test pill does not load: " + "; ".join(e.toString() for e in comp.errors()))
    sys.exit(1)
view.setContent(QUrl(), comp, root)
view.resize(400, 200)
view.show()
QTest.qWaitForWindowExposed(view)


def wheel_at(x, y, notches=1):
    pos = QPointF(x, y)
    ev = QWheelEvent(pos, QPointF(view.mapToGlobal(QPoint(x, y))), QPoint(0, 0), QPoint(0, 120 * notches),
                     Qt.NoButton, Qt.NoModifier, Qt.NoScrollPhase, False)
    QGuiApplication.sendEvent(view, ev)


QTest.mouseMove(view, QPoint(20, 20))
QTest.qWait(300)
# A page scroll: the wheel turns while the pointer moves from above the pill onto it.
for k, y in enumerate((40, 60, 85, 90, 95)):
    QTest.mouseMove(view, QPoint(150, y))
    wheel_at(150, y)
    QTest.qWait(30)
check(root.property("steps") == 0, "real events: wheel notches as the pointer passes onto the pill change nothing (%d)" % root.property("steps"))
QTest.qWait(1700)
wheel_at(150, 95)
check(root.property("steps") == 1, "real events: after a pause the wheel steps (%d)" % root.property("steps"))
QTest.mouseMove(view, QPoint(20, 20))
QTest.qWait(100)
QTest.mouseMove(view, QPoint(160, 92))
QTest.qWait(400)
for _ in range(3):
    wheel_at(160, 92)
    QTest.qWait(30)
check(root.property("steps") == 4, "real events: pointer rested 400 ms, three notches step three times (%d)" % root.property("steps"))
view.close()

# ---- 3. The pills use it
PILLS = [ROOT / "packages/plasmoids/org.plasmafusion.clockpill/contents/ui/main.qml",
         ROOT / "packages/plasmoids/org.plasmafusion.quicksettings/contents/ui/TopBar.qml"]
for f in PILLS:
    text = f.read_text(encoding="utf-8")
    guards = set(re.findall(r"FusionWheelGuard\s*\{\s*id:\s*(\w+)", text))
    handlers = [m.start() for m in re.finditer(r"\bWheelHandler\s*\{", text)]
    unguarded = 0
    for start in handlers:
        body = text[start:start + 600]
        if not any(re.search(r"\b%s\.accept\(" % re.escape(gid), body) for gid in guards):
            unguarded += 1
    check(handlers and unguarded == 0,
          "%s: %d wheel handler(s), every one asks a FusionWheelGuard (%d do not)" % (f.relative_to(ROOT), len(handlers), unguarded))

print(f"Wheel guard: {checks} checks, {len(failures)} failures")
sys.exit(1 if failures else 0)
