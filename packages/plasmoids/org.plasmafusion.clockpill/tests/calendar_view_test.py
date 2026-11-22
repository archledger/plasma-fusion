#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise calendar selection/keyboard/touch layout and the layout control in the staged real QML.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 calendar_view_test.py STAGE_HOME
"""

import json
import math
import os
from pathlib import Path
import sys
import time

os.environ.setdefault("QT_QUICK_BACKEND", "software")
from PySide6.QtCore import (Property, QDate, QDateTime, QObject, QPoint, QPointF, QRectF, QTime, QTimeZone, Qt, QUrl, Slot,
                            qInstallMessageHandler)
from PySide6.QtGui import QColor, QFontMetricsF, QGuiApplication, QWheelEvent
from PySide6.QtQml import QQmlComponent, QQmlExpression, qmlContext
from PySide6.QtQuick import QQuickItem, QQuickView
from PySide6.QtTest import QTest


class Context(QObject):
    @Slot(str, result=str)
    def i18n(self, text):
        return text

    @Slot(str, str, result=str)
    def i18nc(self, context, text):
        return text

    @Slot(str, str, str, int, result=str)
    def i18ncp(self, context, singular, plural, count):
        return (singular if count == 1 else plural).replace("%1", str(count))


class PlasmoidContext(QObject):
    @Property("QVariant", constant=True)
    def containment(self):
        return {"availableScreenRect": QRectF(0, 0, 1440, 900)}


app = QGuiApplication(sys.argv[:1])
view = QQuickView()
context, plasmoid = Context(), PlasmoidContext()
view.rootContext().setContextObject(context)
view.rootContext().setContextProperty("Plasmoid", plasmoid)
now = QDateTime(QDate(2026, 10, 8), QTime(12, 0))
view.setInitialProperties({"now": now, "firstDayOfWeek": 1, "dark": False, "open": False})
source = Path(sys.argv[1]).resolve() / ".local/share/plasma/plasmoids/org.plasmafusion.clockpill/contents/ui/CalendarView.qml"
view.setSource(QUrl.fromLocalFile(str(source)))
if view.status() == QQuickView.Error:
    raise SystemExit("Calendar view failed to load: " + "; ".join(e.toString() for e in view.errors()))
root = view.rootObject()
view.resize(round(root.implicitWidth()), round(root.implicitHeight()))
view.show()
root.forceActiveFocus()
QTest.qWait(100)
checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


check(root.property("selectedDate").date() == now.date(), "opens on today's selected day")
QTest.keyClick(view, Qt.Key_Right)
check(root.property("selectedDate").date() == now.date().addDays(1), "Right moves the selected day, not an entire month")
QTest.keyClick(view, Qt.Key_Down)
check(root.property("selectedDate").date() == now.date().addDays(8), "Down moves one week")
QTest.keyClick(view, Qt.Key_Home)
check(root.property("selectedDate").date() == now.date(), "Home returns selection to today")
root.setProperty("shown", QDateTime(QDate(2028, 1, 1), QTime(12, 0)))
root.setProperty("selectedDate", QDateTime(QDate(2028, 1, 31), QTime(12, 0)))
QTest.keyClick(view, Qt.Key_PageDown)
check(root.property("selectedDate").date() == QDate(2028, 2, 29), "month navigation clamps the selected day at leap February")
QTest.keyClick(view, Qt.Key_Home)
QTest.qWait(50)
def visual_items(item: QQuickItem):
    yield item
    for child in item.childItems():
        yield from visual_items(child)


cells = [item for item in visual_items(root) if item.property("eventCount") is not None]
check(len(cells) == 42, "all day cells are interactive")
target = next(item for item in cells if item.property("day").date() == QDate(2026, 10, 12))
point = target.mapToScene(QPointF(target.width() / 2, target.height() / 2))
QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, QPoint(round(point.x()), round(point.y())))
check(root.property("selectedDate").date() == QDate(2026, 10, 12), "clicking a date selects that day's agenda")
root.setProperty("touch", True)
QTest.qWait(50)
check(all(item.height() >= 44 for item in cells), "touch day targets reach 44 pixels")
root.setProperty("open", True)
# The adapter is an asynchronous Loader. It loads in about 30 ms, but its incubation sometimes waits:
# a fixed half second missed it in 4 of 180 runs back to back, so wait for it, up to 10 s.
started = time.monotonic()
while root.property("backend") is None and time.monotonic() - started < 10:
    QTest.qWait(10)
waited = round((time.monotonic() - started) * 1000)
check(root.property("backend") is not None, f"optional native calendar adapter loads when opened ({waited} ms)")
root.setProperty("selectedTimeZones", ["America/New_York", "Europe/London", "Asia/Tokyo"])
QTest.qWait(200)
zones = [item for item in visual_items(root) if item.property("zoneId") is not None]
check(len(zones) == 3, "selected world clocks are created")
for item in zones:
    zone = item.property("zoneId")
    expected = QDateTime.currentDateTimeUtc().toTimeZone(QTimeZone(zone.encode()))
    got = item.property("currentTime")
    check(got.date() == expected.date() and got.time().hour() == expected.time().hour(),
          f"native {zone} clock respects offset, DST and date boundary")
# Closed, the adapter unloads, and quietly: no binding whose write leads to the write of the
# loader's `active` reads the loader's item (otherwise Qt logs a binding loop). A calendar call
# still running keeps the adapter loaded after the close, until the call ends, so that its reply
# still reaches it. Every message is still printed.
messages = []


def keep_message(mode, context, message):
    messages.append(message)
    print(message, file=sys.stderr)


qInstallMessageHandler(keep_message)
try:
    root.setProperty("open", False)
    QTest.qWait(50)
    check(root.property("backend") is None, "closed, the calendar adapter unloads")
    root.setProperty("open", True)
    started = time.monotonic()
    while root.property("backend") is None and time.monotonic() - started < 10:
        QTest.qWait(10)
    check(root.property("backend") is not None, "opened again, the calendar adapter loads again")
    root.property("backend").setProperty("busy", True)
    root.setProperty("open", False)
    QTest.qWait(50)
    check(root.property("backend") is not None, "a calendar call still running keeps the adapter loaded after the close")
    root.property("backend").setProperty("busy", False)
    QTest.qWait(50)
finally:
    qInstallMessageHandler(None)
check(root.property("backend") is None, "the call over, the adapter unloads")
loops = [message for message in messages if "Binding loop" in message]
check(not loops, "the adapter unloads with no binding loop (%s)" % loops)
print(f"Calendar view: {checks} checks, 0 failures")

# The layout control (contents/ui/LayoutControl.qml, P4): the bar's tiling mode, read only. Each
# fixture is a document beside the staged component, so that LayoutControl and the shared
# FusionMetrics resolve as they do for main.qml. These checks go on after a failure, so that one run
# shows them all.
ui = Path(sys.argv[1]).resolve() / ".local/share/plasma/plasmoids/org.plasmafusion.clockpill/contents/ui"
CONTROL_FIXTURE = """import QtQuick
Item {
    id: fixture
    width: 480
    height: 24
    // Typed Item, as PySide has no converter for a type defined in QML.
    property Item control: control
    property int wheels: 0
    property int taps: 0
    LayoutMirroring.enabled: RTL
    LayoutMirroring.childrenInherit: true
    WheelHandler {
        onWheel: fixture.wheels += 1
    }
    TapHandler {
        onTapped: fixture.taps += 1
    }
    FusionMetrics {
        id: metrics
    }
    LayoutControl {
        id: control
        mode: MODE
        level: LEVEL
        metrics: metrics
        color: "#141827"
    }
}
"""
TILED_GLYPH, FLOATING_GLYPH = "M4 5h16v14H4zM12 5v14", "M4 5h16v14H4z"
TILED_TIP = "The dynamic tiler arranges this workspace's windows"
FLOATING_TIP = "The dynamic tiler does not arrange this workspace"
control_checks, control_failures = 0, 0
fixtures = []


def expect(condition, message):
    global control_checks, control_failures
    control_checks += 1
    if condition:
        print("PASS", message)
    else:
        control_failures += 1
        print("FAIL", message)


def control_fixture(mode, level=0, rtl=False):
    """A fixture holding one control, kept with its component (an object dies with it)."""
    component = QQmlComponent(view.engine())
    component.setData(CONTROL_FIXTURE.replace("MODE", json.dumps(mode)).replace("LEVEL", str(level))
                      .replace("RTL", "true" if rtl else "false").encode(),
                      QUrl.fromLocalFile(str(ui / "LayoutControlFixture.qml")))
    fixture = component.create()
    if fixture is None:
        print("the layout control's fixture failed: " + "; ".join(e.toString() for e in component.errors()))
        return None, None
    fixture.setParentItem(view.contentItem())
    fixtures.append((component, fixture))
    QTest.qWait(20)
    return fixture, fixture.property("control")


def child(item, name):
    return item.findChild(QQuickItem, name) if item is not None else None


def prop(item, name):
    return item.property(name) if item is not None else None


def evaluated(item, expression):
    """An expression in the item's own scope (attached properties among them), or None."""
    context = qmlContext(item) if item is not None else None
    if context is None:
        return None
    value, undefined = QQmlExpression(context, item, expression).evaluate()
    return None if undefined else value


def shown(item):
    return item is not None and item.isVisible()


def weight(font):
    value = font.weight() if font is not None else None
    return getattr(value, "value", value)


def span(item, owner):
    """The item's left and right edges in the owner's coordinates."""
    left = item.mapToItem(owner, QPointF(0, 0)).x()
    return left, left + item.width()


def drawn(owner, rtl, level):
    """The glyph and the label as laid out, checked in one direction at one level."""
    glyph_at, label_at = child(owner, "layoutGlyph"), child(owner, "layoutLabel")
    if owner is None or glyph_at is None or label_at is None:
        return False
    g, l, width = span(glyph_at, owner), span(label_at, owner), owner.width()
    if level == 1:
        return abs(g[0]) < 0.01 and abs(g[1] - width) < 0.01
    between = g[0] - l[1] if rtl else l[0] - g[1]
    return (abs(between - prop(owner, "gap")) < 0.01 and abs(label_at.width() - prop(owner, "labelWidth")) < 0.01
            and abs(min(g[0], l[0])) < 0.01 and abs(max(g[1], l[1]) - width) < 0.01)


fixture, control = control_fixture("tiled")
expect(control is not None, "the layout control loads beside the staged clock")
label, glyph, tip = child(control, "layoutLabel"), child(control, "layoutGlyph"), child(control, "layoutTip")
font = prop(label, "font")
glyph_size, gap = evaluated(control, "metrics.px(14)"), evaluated(control, "metrics.px(6)")
label_px = evaluated(control, "metrics.font(13)")
expect(shown(control) and shown(label) and prop(label, "text") == "Tiled"
       and shown(glyph) and prop(glyph, "path") == TILED_GLYPH,
       "tiled, the control shows the frame-and-divider glyph and the label Tiled")
expect(evaluated(control, "Accessible.name") == "Dynamic tiling: Tiled"
       and evaluated(control, "Accessible.role === Accessible.StaticText") is True,
       "tiled, its accessible name says the mode, as static text")
expect(prop(tip, "mainText") == "Tiled" and prop(tip, "subText") == TILED_TIP
       and evaluated(control, "Accessible.description") == TILED_TIP,
       "tiled, its tooltip and accessible description say the dynamic tiler arranges the windows")
expect(glyph_size is not None and prop(control, "glyphSize") == glyph_size and prop(glyph, "width") == glyph_size
       and prop(control, "gap") == gap,
       "the glyph is 14 px and 6 px from its label, both through the metrics (%s, %s)" % (glyph_size, gap))
expect(font is not None and label_px is not None and font.pixelSize() == round(label_px) and weight(font) == 600
       and font.family() == evaluated(control, "metrics.family") and prop(label, "display") is False,
       "the label is the pill's 13 px text at weight 600, not the display family, through the metrics")
expect(drawn(control, False, 0), "drawn, the label is the gap from its glyph, in its own box, and the two fill the control")
expect(evaluated(label, "effectiveHorizontalAlignment === Text.AlignLeft") is True,
       "the label keeps to the glyph's side of its box")
expect(prop(label, "color") == QColor("#141827") and prop(glyph, "color") == QColor("#141827"),
       "the glyph and the label take the pill's text colour")
widest = math.ceil(max(QFontMetricsF(font).horizontalAdvance(text) for text in ("Tiled", "Floating"))) if font else None
full = prop(control, "fullWidth")
expect(widest is not None and glyph_size is not None and full is not None
       and abs(full - (glyph_size + gap + widest)) < 0.01 and abs(prop(control, "implicitWidth") - full) < 0.01,
       "its width is the glyph, the gap and the wider of the two labels (%s)" % full)
expect(prop(control, "available") is True, "tiled is a mode the control shows")

if control is not None:
    control.setProperty("mode", "floating")
    QTest.qWait(20)
expect(shown(control) and prop(label, "text") == "Floating" and prop(glyph, "path") == FLOATING_GLYPH,
       "floating, the control shows the frame glyph and the label Floating")
expect(evaluated(control, "Accessible.name") == "Dynamic tiling: Floating"
       and prop(tip, "mainText") == "Floating" and prop(tip, "subText") == FLOATING_TIP,
       "floating, its accessible name and tooltip say so, and that the tiler does not arrange it")
expect(full is not None and abs(prop(control, "implicitWidth") - full) < 0.01,
       "a change of mode does not change its width")

for mode in ("unknown", "unavailable"):
    if control is not None:
        control.setProperty("mode", mode)
        QTest.qWait(20)
    expect(control is not None and not control.isVisible() and prop(control, "implicitWidth") == 0
           and prop(control, "available") is False,
           "%s, the control shows nothing and takes no room" % mode)
expect(full is not None and prop(control, "fullWidth") == full and prop(control, "compactWidth") == glyph_size,
       "hidden, it still reports its widths for the width budget")

if control is not None:
    control.setProperty("mode", "tiled")
    control.setProperty("level", 1)
    QTest.qWait(20)
expect(shown(control) and shown(glyph) and not shown(label)
       and prop(control, "implicitWidth") == prop(control, "compactWidth") == glyph_size,
       "compact (level 1), only the glyph shows, and the control is as wide as it")
expect(evaluated(control, "Accessible.name") == "Dynamic tiling: Tiled",
       "compact, its accessible name still says the mode")
expect(drawn(control, False, 1), "compact, the glyph fills the control")
if control is not None:
    control.setProperty("level", 2)
    QTest.qWait(20)
expect(control is not None and not control.isVisible() and prop(control, "implicitWidth") == 0
       and prop(control, "fullWidth") == full,
       "level 2, the control shows nothing and takes no room")

if control is not None:
    control.setProperty("level", 0)
    QTest.qWait(20)
    before = prop(fixture, "wheels")
    centre = control.mapToScene(QPointF(control.width() / 2, control.height() / 2))
    QGuiApplication.sendEvent(view, QWheelEvent(centre, view.mapToGlobal(centre.toPoint()).toPointF(), QPoint(0, 0),
                                                QPoint(0, 120), Qt.NoButton, Qt.NoModifier, Qt.NoScrollPhase, False))
    QTest.qWait(20)
expect(control is not None and prop(fixture, "wheels") == before + 1,
       "a wheel over the control reaches the pill behind it, which switches workspaces")
if control is not None:
    tapped = prop(fixture, "taps")
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, centre.toPoint())
    QTest.qWait(20)
expect(control is not None and prop(fixture, "taps") == tapped + 1,
       "a click on the control reaches what is behind it, as it takes no click yet")
items = []
pending = [control] if control is not None else []
while pending:
    item = pending.pop()
    items.append(item)
    pending.extend(item.childItems())
expect(bool(items) and not any(item.property("activeFocusOnTab") for item in items),
       "it offers no action, so nothing of it takes keyboard focus")
# The click above reaches the fixture's TapHandler, whose grab is passive: a tap handler of the
# control's own would act on the same click unseen. So nothing of the read-only control handles a
# click itself: no pointer handler but a hover one, and no mouse area.
handlers = [obj.metaObject().className() for item in items for obj in item.children()
            if obj.inherits("QQuickPointerHandler") and not obj.inherits("QQuickHoverHandler")]
areas = [item.metaObject().className() for item in items if item.inherits("QQuickMouseArea")]
expect(bool(items) and not handlers and not areas,
       "it offers no action, so nothing of it handles a click itself (handlers %s, mouse areas %s)" % (handlers, areas))

_, rtl = control_fixture("tiled", rtl=True)
rtl_glyph, rtl_label = child(rtl, "layoutGlyph"), child(rtl, "layoutLabel")
expect(glyph is not None and label is not None and rtl_glyph is not None and rtl_label is not None
       and glyph.mapToItem(control, QPointF(0, 0)).x() < label.mapToItem(control, QPointF(0, 0)).x()
       and rtl_glyph.mapToItem(rtl, QPointF(0, 0)).x() > rtl_label.mapToItem(rtl, QPointF(0, 0)).x(),
       "the glyph leads the label, on its right in a right-to-left layout")
expect(drawn(rtl, True, 0), "right-to-left, the label is the gap from its glyph, in its own box, and the two fill it")
expect(evaluated(rtl_label, "effectiveHorizontalAlignment === Text.AlignRight") is True,
       "right-to-left, the label keeps to the glyph's side of its box, its right")
if rtl is not None:
    rtl.setProperty("level", 1)
    QTest.qWait(20)
expect(drawn(rtl, True, 1), "right-to-left and compact, the glyph fills the control")

for _, item in fixtures:
    item.deleteLater()
QTest.qWait(20)
print(f"Layout control: {control_checks} checks, {control_failures} failures")
if control_failures:
    sys.exit(1)
