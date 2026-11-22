#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise calendar selection/keyboard/touch layout, the layout control and its menu in the staged real QML.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 calendar_view_test.py STAGE_HOME
"""

import json
import math
import os
from pathlib import Path
import sys
import time

os.environ.setdefault("QT_QUICK_BACKEND", "software")
from PySide6.QtCore import (Property, QDate, QDateTime, QEvent, QObject, QPoint, QPointF, QRectF, QTime, QTimeZone, Qt, QUrl,
                            Slot, qInstallMessageHandler)
from PySide6.QtGui import (QAccessible, QAccessibleActionInterface, QColor, QFontMetricsF, QGuiApplication, QKeyEvent,
                           QWheelEvent)
from PySide6.QtQml import QQmlComponent, QQmlExpression, qmlContext
from PySide6.QtQuick import QQuickItem, QQuickView
from PySide6.QtTest import QTest

# Texts the context gives instead of the source string, for the checks of long translations.
translations = {}


class Context(QObject):
    @Slot(str, result=str)
    def i18n(self, text):
        return text

    @Slot(str, str, result=str)
    @Slot(str, str, str, result=str)
    def i18nc(self, context, text, argument=None):
        text = translations.get(text, text)
        return text if argument is None else text.replace("%1", argument)

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

# The width budget (contents/ui/WidthBudget.qml) evaluates again when the clock's savings change
# while the pill keeps its width: at step 7 the layout control takes no room whether it shows a
# mode or not, but at the steps below only a control that shows a mode does. A stand-in bar around
# the staged budget: a left widget that fits only beside a pill of at most 410 px, two expanding
# spacers and a stand-in clock whose control gives up its label (30 px) from step 4 and 50 px at
# step 7, while the date and the dots give up 100 px at step 7.
BUDGET_FIXTURE = """import QtQuick
import QtQuick.Layouts
Item {
    id: fixture
    width: 1440
    height: 30
    property Item clock: clock
    component Spacer: Item {
        property bool isAppletContainer: true
        property QtObject applet: QtObject {
            property QtObject plasmoid: QtObject {
                property string pluginName: "org.kde.plasma.panelspacer"
                property QtObject configuration: QtObject {
                    property bool expanding: true
                }
            }
        }
        Layout.fillWidth: true
    }
    GridLayout {
        width: fixture.width
        height: fixture.height
        rows: 1
        columnSpacing: 0
        Item {
            property bool isAppletContainer: true
            property QtObject applet: QtObject {}
            readonly property real side: fixture.width / 2 - 205 - budget.gap
            Layout.minimumWidth: side
            Layout.preferredWidth: side
            Layout.maximumWidth: side
        }
        Spacer {}
        Item {
            id: clock
            property bool isAppletContainer: true
            property Item applet: clock
            property int budgetLevel: 0
            property bool controlShown: true
            property real labelSaving: 30
            function budgetSaving(level: int): real {
                return (level >= 7 ? 100 : 0) + (controlShown ? (level >= 7 ? 50 : level >= 4 ? labelSaving : 0) : 0);
            }
            readonly property real pillWidth: 400 + (controlShown ? 50 : 0) - budgetSaving(budgetLevel)
            Layout.preferredWidth: pillWidth
        }
        Spacer {}
    }
    FusionMetrics {
        id: metrics
    }
    WidthBudget {
        id: budget
        clock: clock
        cell: clock
        metrics: metrics
        tablet: false
    }
}
"""
original_size = (view.width(), view.height())
view.resize(1440, max(view.height(), 30))
budget_component = QQmlComponent(view.engine())
budget_component.setData(BUDGET_FIXTURE.encode(), QUrl.fromLocalFile(str(ui / "WidthBudgetFixture.qml")))
bar = budget_component.create()
if bar is None:
    print("the width budget's fixture did not load: " + "; ".join(e.toString() for e in budget_component.errors()))
else:
    bar.setParentItem(view.contentItem())
    fixtures.append((budget_component, bar))
budget_clock = bar.property("clock") if bar is not None else None


def budget_level_reaches(level, ms=2000):
    started = time.monotonic()
    while budget_clock is not None and budget_clock.property("budgetLevel") != level and time.monotonic() - started < ms / 1000:
        QTest.qWait(10)
    return budget_clock is not None and budget_clock.property("budgetLevel") == level


expect(budget_level_reaches(7), "the width budget takes step 7 while the control's room fits at no lower step (%s)"
       % prop(budget_clock, "budgetLevel"))
before_width = prop(budget_clock, "pillWidth")
if budget_clock is not None:
    budget_clock.setProperty("controlShown", False)
expect(prop(budget_clock, "pillWidth") == before_width and budget_level_reaches(0),
       "the control showing no mode at step 7, the width budget steps back though the pill kept its width (%s)"
       % prop(budget_clock, "budgetLevel"))
# Every step's saving, not only the current one's: back at step 7, a saving that only the steps
# below it give up grows (a wider label, 45 px) while the pill and its saving at step 7 stay as they
# were, and step 4 now fits.
if budget_clock is not None:
    budget_clock.setProperty("controlShown", True)
expect(budget_level_reaches(7), "the control showing its mode again, the width budget goes back to step 7 (%s)"
       % prop(budget_clock, "budgetLevel"))
before_width = prop(budget_clock, "pillWidth")
if budget_clock is not None:
    budget_clock.setProperty("labelSaving", 45)
expect(prop(budget_clock, "pillWidth") == before_width and budget_level_reaches(4),
       "a saving only the lower steps give up grown at step 7, the width budget takes step 4 (%s)"
       % prop(budget_clock, "budgetLevel"))
view.resize(*original_size)
print(f"Layout control, read only: {control_checks} checks, {control_failures} failures")
read_only_checks, read_only_failures = control_checks, control_failures

# The interactive control (P6: LayoutControl.qml with `interactive`) and the layout menu it opens
# (LayoutMenu.qml), each in a window of its own, as the menu has its applet pop-up: so that keys
# and the Tab chain see nothing else. The windows share the engine, and with it the context that
# translates. The owner's side - the layout state, the pop-up and the one announcer - is the
# backend test's (main.qml's block); here the two components alone. These checks go on after a
# failure too.
PRESS = QAccessibleActionInterface.pressAction()
GENERIC = "Couldn't change the layout"
CHECK_PATH = "M5 12.5l4.5 4.5L19 7.5"


def window_fixture(window, text, name):
    """A fixture made in `window`, kept with its component, or None when it does not load."""
    component = QQmlComponent(view.engine())
    component.setData(text.encode(), QUrl.fromLocalFile(str(ui / name)))
    made = component.create()
    if made is None:
        print(f"the fixture {name} failed: " + "; ".join(e.toString() for e in component.errors()))
        return None
    made.setParentItem(window.contentItem())
    fixtures.append((component, made))
    QTest.qWait(20)
    return made


def centre(item):
    if item is None:
        return QPoint(0, 0)
    point = item.mapToScene(QPointF(item.width() / 2, item.height() / 2))
    return QPoint(round(point.x()), round(point.y()))


def key(window, code, modifiers=Qt.NoModifier, repeat=False):
    """A press and a release of `code`, or the auto-repeated pair a held key sends."""
    if repeat:
        for kind in (QEvent.KeyPress, QEvent.KeyRelease):
            QGuiApplication.sendEvent(window, QKeyEvent(kind, code, modifiers, "", True))
    else:
        QTest.keyClick(window, code, modifiers)
    QTest.qWait(10)


def accessible_actions(item):
    """The names of the item's accessible actions, and its action interface."""
    interface = QAccessible.queryAccessibleInterface(item) if item is not None else None
    actions = interface.actionInterface() if interface is not None else None
    return (list(actions.actionNames()) if actions is not None else []), actions


def items_of(item):
    found, queue = [], [item] if item is not None else []
    while queue:
        current = queue.pop()
        found.append(current)
        queue.extend(current.childItems())
    return found


def count(fixture, name):
    value = prop(fixture, name)
    return value if isinstance(value, int) else 0


def listed(fixture, name):
    value = prop(fixture, name)
    # A JavaScript array property reaches Python as a QJSValue.
    value = value.toVariant() if hasattr(value, "toVariant") else value
    return list(value or [])


def at(item, owner):
    """The item's top left corner in the owner's coordinates, or None."""
    return item.mapToItem(owner, QPointF(0, 0)) if item is not None and owner is not None else None


def staged_source(name):
    path = ui / name
    return path.read_text(encoding="utf-8") if path.is_file() else None


def near(a, b):
    return a is not None and b is not None and abs(a - b) < 0.01


# Offscreen, a window that loses the activation drops its active focus item until it gets it
# back, and a Plasma tooltip window takes the activation as it shows, a moment after a hover. So
# each window is made the active one before its keys, as the panel's and the pop-up's are while in
# use, and the pointer leaves the control after each press, so that its tooltip never shows.
def take_focus(window):
    window.requestActivate()
    QTest.qWaitForWindowActive(window, 2000)


def pointer_away(window):
    QTest.mouseMove(window, QPoint(window.width() - 1, window.height() - 1))
    QTest.qWait(10)


def transparent(item):
    colour = prop(item, "color")
    return colour is not None and colour.alpha() == 0


INTERACTIVE_FIXTURE = """import QtQuick
Item {
    id: fixture
    width: 480
    height: 48
    property Item control: control
    property var requests: []
    property int dismissals: 0
    property int behind: 0
    property int rightTaps: 0
    property int wheels: 0
    property int parentKeys: 0
    // The keys the control leaves reach its parent, as the panel's would.
    Keys.onPressed: fixture.parentKeys += 1
    WheelHandler {
        onWheel: fixture.wheels += 1
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: fixture.rightTaps += 1
    }
    // What lies under the control: a press that reaches it is one the control let through.
    MouseArea {
        anchors.fill: parent
        onPressed: fixture.behind += 1
    }
    FusionMetrics {
        id: metrics
    }
    FusionAccent {
        id: accent
    }
    LayoutControl {
        id: control
        x: 40
        y: 12
        interactive: true
        mode: "floating"
        metrics: metrics
        accent: accent
        color: "#141827"
        onMenuRequested: by => fixture.requests = fixture.requests.concat([by])
        onMenuDismissed: fixture.dismissals += 1
    }
}
"""
# The read-only fixtures are done with: hidden, they drop the hover the click on the control left,
# and with it the tooltip that would show; and the pointer leaves the place of that click, so that
# a control made there later is not hovered either.
for _, item in fixtures:
    item.setVisible(False)
pointer_away(view)
control_view = QQuickView(view.engine(), None)
control_view.resize(480, 48)
control_view.show()
QTest.qWait(20)
ifixture = window_fixture(control_view, INTERACTIVE_FIXTURE, "LayoutControlInteractiveFixture.qml")
icontrol = prop(ifixture, "control")
itip, icontent = child(icontrol, "layoutTip"), child(icontrol, "layoutContent")
iring, ilook = child(icontrol, "layoutFocusRing"), child(icontrol, "layoutOpenLook")
requests = lambda: listed(ifixture, "requests")
expect(icontrol is not None, "interactive, the layout control loads, with the window's accent")
expect(evaluated(icontrol, "Accessible.role === Accessible.ButtonDropDown") is True
       and evaluated(icontrol, "Accessible.name") == "Dynamic tiling: Floating",
       "interactive, it is a drop-down button, as every opener in the bar, and its name still says the mode")

stops = []
for mode, level in (("floating", 0), ("tiled", 0), ("tiled", 1), ("unknown", 0), ("unavailable", 0), ("floating", 2)):
    if icontrol is not None:
        icontrol.setProperty("mode", mode)
        icontrol.setProperty("level", level)
        QTest.qWait(10)
    stops.append(prop(icontrol, "activeFocusOnTab") is True)
if icontrol is not None:
    icontrol.setProperty("mode", "floating")
    icontrol.setProperty("level", 0)
    QTest.qWait(10)
expect(stops == [True, True, True, False, False, False],
       "interactive, it is a Tab stop while it shows a mode, full or compact, and not while it shows none (%s)" % stops)

unfocused_ring = shown(iring)
take_focus(control_view)
if icontrol is not None:
    icontrol.forceActiveFocus(Qt.TabFocusReason)
    QTest.qWait(10)
ring_at = at(iring, icontrol)
expect(ring_at is not None and not unfocused_ring and shown(iring) and prop(icontrol, "activeFocus") is True
       and abs(ring_at.x() + 4) < 0.01 and abs(ring_at.y() + 4) < 0.01
       and abs(iring.width() - icontrol.width() - 8) < 0.01 and abs(iring.height() - icontrol.height() - 8) < 0.01
       and evaluated(iring, "border.width") == 2 and evaluated(iring, "border.color") == evaluated(icontrol, "accent.focusRing")
       and abs(prop(iring, "radius") - iring.height() / 2) < 0.01,
       "focused, it draws the Fusion ring: 2 px in the focus colour with a 2 px gap outside it, round as the pill")

OPENING_KEYS = (Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Select)
start, parent_keys = len(requests()), count(ifixture, "parentKeys")
for code in OPENING_KEYS:
    key(control_view, code)
expect(requests()[start:] == ["keys"] * 4 and count(ifixture, "parentKeys") == parent_keys,
       "focused, each of Return, Enter, Space and Select asks for the menu once on its press, saying keys, and goes no further (%s)"
       % requests()[start:])
start, parent_keys = len(requests()), count(ifixture, "parentKeys")
for code in OPENING_KEYS:
    key(control_view, code, repeat=True)
expect(icontrol is not None and requests()[start:] == [] and count(ifixture, "parentKeys") == parent_keys,
       "an auto-repeated press of those keys asks for nothing and goes no further (%s)" % requests()[start:])
start, parent_keys = len(requests()), count(ifixture, "parentKeys")
for code in (Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down, Qt.Key_Escape):
    key(control_view, code)
expect(icontrol is not None and count(ifixture, "parentKeys") == parent_keys + 5 and requests()[start:] == [],
       "it takes no arrow and no Escape: they reach its parent, as the panel turns arrows into Tab and leaves on Escape")

names, actions = accessible_actions(icontrol)
start = len(requests())
if actions is not None and PRESS in names:
    actions.doAction(PRESS)
    QTest.qWait(10)
expect(PRESS in names and requests()[start:] == ["accessibility"],
       "its accessible press action asks for the menu once, saying accessibility (%s, %s)" % (names, requests()[start:]))
_, read_only = control_fixture("floating")
read_only_names, _ = accessible_actions(read_only)
expect(read_only is not None and PRESS not in read_only_names,
       "read only, it offers assistive technology no press action, as P4's control (%s)" % read_only_names)

point = centre(icontrol)
start, behind = len(requests()), count(ifixture, "behind")
QTest.mousePress(control_view, Qt.LeftButton, Qt.NoModifier, point)
QTest.qWait(10)
on_press = requests()[start:]
QTest.mouseRelease(control_view, Qt.LeftButton, Qt.NoModifier, point)
QTest.qWait(10)
pointer_away(control_view)
expect(icontrol is not None and on_press == [] and requests()[start:] == ["pointer"] and count(ifixture, "behind") == behind,
       "a press then release on it asks for the menu once, on the release, saying pointer, and nothing under it takes the click")

if icontrol is not None:
    icontrol.setProperty("menuOpen", True)
    QTest.qWait(10)
start, dismissals = len(requests()), count(ifixture, "dismissals")
QTest.mousePress(control_view, Qt.LeftButton, Qt.NoModifier, point)
QTest.qWait(10)
dismissed_on_press = count(ifixture, "dismissals") - dismissals
QTest.mouseRelease(control_view, Qt.LeftButton, Qt.NoModifier, point)
QTest.qWait(10)
pointer_away(control_view)
expect(icontrol is not None and dismissed_on_press == 1 and count(ifixture, "dismissals") == dismissals + 1 and requests()[start:] == [],
       "with its menu open, a press on it is the user's close, on the press, and the click after it asks for nothing")

pill_padding = evaluated(icontrol, "metrics.px(12)")
look_at = at(ilook, icontrol)
expect(look_at is not None and pill_padding is not None and shown(ilook)
       and abs(look_at.x() + pill_padding / 2) < 0.01 and abs(look_at.y()) < 0.01
       and abs(ilook.width() - icontrol.width() - pill_padding) < 0.01 and abs(ilook.height() - prop(icontrol, "cellHeight")) < 0.01
       and abs(prop(ilook, "radius") - ilook.height() / 2) < 0.01 and prop(ilook, "color") == evaluated(icontrol, "accent.soft(0.35)")
       and evaluated(ilook, "border.width") == 1
       and evaluated(ilook, "border.color") == evaluated(icontrol, "Qt.rgba(accent.focusRing.r, accent.focusRing.g, accent.focusRing.b, 0.5)")
       and abs(prop(icontrol, "implicitWidth") - prop(icontrol, "fullWidth")) < 0.01,
       "with its menu open, it alone takes the opener's look: the accent at 35% with a 1 px edge, a capsule of the pill's height "
       "reaching half the pill's padding past each side, and no wider")
tip_while_open = prop(itip, "active")
if icontrol is not None:
    icontrol.setProperty("menuOpen", False)
    QTest.qWait(10)
expect(ilook is not None and not shown(ilook), "with its menu closed, it has no opener's look")
expect(tip_while_open is False and prop(itip, "active") is True,
       "its tooltip stays away while its menu is open, as the date's while the calendar is, and comes back with the menu closed")

start, taps, dismissals = len(requests()), count(ifixture, "rightTaps"), count(ifixture, "dismissals")
QTest.mouseClick(control_view, Qt.RightButton, Qt.NoModifier, point)
QTest.qWait(10)
pointer_away(control_view)
expect(icontrol is not None and count(ifixture, "rightTaps") == taps + 1 and requests()[start:] == []
       and count(ifixture, "dismissals") == dismissals,
       "a right click passes it, to the widget's context menu, and opens nothing")
wheels = count(ifixture, "wheels")
QGuiApplication.sendEvent(control_view, QWheelEvent(QPointF(point), control_view.mapToGlobal(point).toPointF(), QPoint(0, 0),
                                                    QPoint(0, 120), Qt.NoButton, Qt.NoModifier, Qt.NoScrollPhase, False))
QTest.qWait(10)
pointer_away(control_view)
expect(icontrol is not None and count(ifixture, "wheels") == wheels + 1,
       "interactive, a wheel over it still reaches the pill, which switches workspaces (D16)")

width_before = prop(icontrol, "implicitWidth")
if icontrol is not None:
    icontrol.setProperty("pending", True)
# Read at once: the pending look is static, with no animation to wait for.
expect(icontent is not None and abs(prop(icontent, "opacity") - 0.7) < 0.001 and prop(icontrol, "implicitWidth") == width_before
       and evaluated(icontrol, "Accessible.description") == "Waiting for an answer" and prop(itip, "subText") == "Waiting for an answer",
       "a choice awaited with the menu closed, its glyph and label are drawn at 0.7 at once, it is no wider, and its tooltip "
       "and description say it waits for an answer")
if icontrol is not None:
    icontrol.setProperty("pending", False)
expect(icontent is not None and prop(icontent, "opacity") == 1 and prop(itip, "subText") == FLOATING_TIP,
       "the answer in, it is drawn in full again, and its tooltip says the mode's text")


def outcome_text(reason, mode, in_menu):
    return evaluated(icontrol, "outcomeText(%s, %s, %s)" % (json.dumps(reason), json.dumps(mode), "true" if in_menu else "false"))


# D10's texts, each for the reasons and modes it words (the mode the outcome concerns, empty for a
# prepare with no choice queued), in the menu (True) and in the pill (False).
OUTCOME_TEXTS = {
    "": [("", "", True), ("", "tiled", False)],
    "No app window to tile": [("no-target", "", True), ("no-target", "tiled", True), ("no-target", "tiled", False),
                              ("not-eligible", "tiled", True)],
    "Focus an app window first": [("focus-changed", "", True), ("focus-changed", "", False)],
    "Busy, try again": [("busy", "", True), ("busy", "tiled", False), ("busy", "floating", True)],
    "The workspace changed": [("stale-context", "", True), ("stale-context", "tiled", True), ("focus-changed", "floating", True),
                              ("target-departed", "tiled", True), ("view-changed", "floating", False), ("shell-replaced", "tiled", False)],
    "Interrupted, try again": [("interrupted", "tiled", False), ("interrupted", "floating", True)],
    "Couldn't tile this workspace": [("tree-refused", "tiled", True), ("admission-refused", "tiled", False), ("unavailable", "tiled", True)],
    "Cancelled": [("cancelled", "tiled", True), ("cancelled", "floating", False)],
    "No answer yet": [("unconfirmed", "", True), ("unconfirmed", "tiled", True)],
    "Not confirmed": [("unconfirmed", "", False), ("unconfirmed", "floating", False)],
    GENERIC: [("unavailable", "", True), ("unavailable", "floating", True), ("tree-refused", "floating", False),
              ("admission-refused", "floating", True), ("not-eligible", "floating", True), ("no-target", "floating", False),
              ("conflicting-request", "tiled", True), ("stale-request", "floating", False), ("malformed", "", False),
              ("intent", "", True), ("version", "", False), ("output", "", False), ("a-reason-of-tomorrow", "tiled", True)],
}
for text, cases in OUTCOME_TEXTS.items():
    wrong = [(case, outcome_text(*case)) for case in cases if outcome_text(*case) != text]
    expect(icontrol is not None and not wrong, "outcomeText() words %s as %r (wrong: %s)" % ([case[:2] for case in cases], text, wrong))
# The design words focus-changed apart by intent, which an outcome does not carry: a prepare done
# without a target with Tiled queued (T9) and a Tiled set refused so share their arguments. T9's is
# the case the menu shows; a Tiled set is refused so only as the menu closes.
expect(icontrol is not None and outcome_text("focus-changed", "tiled", True) == "Focus an app window first",
       "outcomeText() words focus-changed with Tiled as T9's prepare: focus an app window first")

notice_timer = icontrol.findChild(QObject, "layoutNotice") if icontrol is not None else None
evaluated(icontrol, 'notify("busy", "tiled")')
expect(prop(notice_timer, "interval") == 5000 and prop(notice_timer, "running") is True and prop(itip, "subText") == "Busy, try again"
       and evaluated(icontrol, "Accessible.description") == "Busy, try again",
       "an outcome handed to it shows in its tooltip and description for 5 s, quick settings' refused-state time, worded by outcomeText()")
evaluated(icontrol, 'notify("unavailable", "floating")')
expect(icontrol is not None and prop(itip, "subText") == GENERIC,
       "a later outcome replaces it, worded for its own mode: Floating's unavailable is not Tiled's")
if notice_timer is not None:
    notice_timer.setProperty("interval", 60)
QTest.qWait(200)
expect(icontrol is not None and prop(itip, "subText") == FLOATING_TIP and prop(notice_timer, "running") is False,
       "its time up, the notice clears, and the tooltip says the mode's text again")
if notice_timer is not None:
    notice_timer.setProperty("interval", 5000)
evaluated(icontrol, 'notify("cancelled", "tiled")')
evaluated(icontrol, 'notify("", "tiled")')
expect(icontrol is not None and prop(itip, "subText") == FLOATING_TIP and prop(notice_timer, "running") is False,
       "an empty outcome, a done set's, clears the notice at once")
control_source = staged_source("LayoutControl.qml")
expect(icontrol is not None and control_source is not None and "announce(" not in control_source,
       "the control announces nothing itself: the owner's outcome handler is the one announcer (D10)")

if icontrol is not None:
    evaluated(icontrol, 'notify("busy", "tiled")')
    icontrol.setProperty("pending", True)
    icontrol.setProperty("menuOpen", True)
    icontrol.setProperty("interactive", False)
    QTest.qWait(50)
all_items = items_of(icontrol)
start, behind = len(requests()), count(ifixture, "behind")
QTest.mouseClick(control_view, Qt.LeftButton, Qt.NoModifier, point)
QTest.qWait(10)
pointer_away(control_view)
expect(icontrol is not None and evaluated(icontrol, "Accessible.role === Accessible.StaticText") is True
       and prop(icontrol, "activeFocus") is False and not any(item.property("activeFocusOnTab") for item in all_items)
       and not any(item.inherits("QQuickMouseArea") for item in all_items)
       and requests()[start:] == [] and count(ifixture, "behind") == behind + 1
       and not shown(ilook) and not shown(iring) and prop(icontent, "opacity") == 1 and prop(itip, "subText") == FLOATING_TIP
       and prop(itip, "active") is True,
       "turned read only again, as when the layout actions go, it is P4's control: static text with no focus, a click passing it, "
       "its tooltip as ever, and no pending look, opener's look or notice")
print(f"Layout control, interactive: {control_checks - read_only_checks} checks, {control_failures - read_only_failures} failures")
interactive_checks, interactive_failures = control_checks, control_failures

MENU_FIXTURE = """import QtQuick
import org.kde.plasma.core as PlasmaCore
Item {
    id: fixture
    width: 400
    height: 400
    property Item menu: menu
    property int inputs: 0
    property var choices: []
    property int closes: 0
    LayoutMenu {
        id: menu
        mode: MODE
        touch: TOUCH
        location: PlasmaCore.Types.LOCATION
        onInputReported: fixture.inputs += 1
        onChosen: choice => fixture.choices = fixture.choices.concat([choice])
        onCloseRequested: fixture.closes += 1
    }
}
"""
menu_view = QQuickView(view.engine(), None)
menu_view.resize(400, 400)
menu_view.show()
take_focus(menu_view)
shown_menu = []


def menu_fixture(mode, touch=False, location="TopEdge"):
    """A menu in the menu's window, alone there: the one shown before leaves the window."""
    if shown_menu and shown_menu[-1] is not None:
        shown_menu[-1].setParentItem(None)
    made = window_fixture(menu_view, MENU_FIXTURE.replace("MODE", json.dumps(mode)).replace("TOUCH", "true" if touch else "false")
                          .replace("LOCATION", location), "LayoutMenuFixture.qml")
    shown_menu.append(made)
    return made, prop(made, "menu")


def parts(menu):
    """The menu's rows, labels, checks, fills and rings by mode, and its status line."""
    return ({mode: child(menu, "layoutMenu" + kind + "-" + mode) for mode in ("floating", "tiled")}
            for kind in ("", "Label", "Check", "Fill", "Ring")), child(menu, "layoutMenuStatus")


def focused(menu, rows):
    for mode, row in rows.items():
        if prop(row, "activeFocus") is True:
            return mode
    return "menu" if prop(menu, "activeFocus") is True else None


def in_menu(menu, expression):
    """An expression in the menu's own document (its status line's scope): its metrics `m`, its accent."""
    return evaluated(child(menu, "layoutMenuStatus"), expression)


mfixture, menu = menu_fixture("floating")
(rows, labels, checks, fills, rings), status_line = parts(menu)
expect(menu is not None, "the layout menu loads beside the staged clock")
expect(evaluated(menu, "Accessible.role === Accessible.Pane") is True and evaluated(menu, "Accessible.name") == "Dynamic tiling",
       "its root is a named pane, as the window card's")
row_at = {mode: at(row, menu) for mode, row in rows.items()}
expect(None not in row_at.values() and row_at["floating"].y() < row_at["tiled"].y()
       and all(evaluated(row, "Accessible.role === Accessible.RadioButton") is True and evaluated(row, "Accessible.checkable") is True
               for row in rows.values())
       and evaluated(rows["floating"], "Accessible.name") == "Floating" and evaluated(rows["tiled"], "Accessible.name") == "Tiled"
       and evaluated(rows["floating"], "Accessible.checked") is True and evaluated(rows["tiled"], "Accessible.checked") is False,
       "it holds two radio rows, Floating then Tiled, the confirmed mode's checked")
inset, check_size = in_menu(menu, "m.px(10)"), in_menu(menu, "m.px(16)")
check_at, label_at = at(checks["floating"], rows["floating"]), at(labels["floating"], rows["floating"])
expect(check_at is not None and label_at is not None and inset is not None and shown(checks["floating"]) and not shown(checks["tiled"])
       and prop(checks["floating"], "path") == CHECK_PATH and abs(checks["floating"].width() - check_size) < 0.01
       and abs(check_at.x() + check_size - (rows["floating"].width() - inset)) < 0.01
       and check_at.x() >= label_at.x() + labels["floating"].width(),
       "the confirmed row alone has the check, 16 px through the metrics, at its trailing edge after the label")
soft = in_menu(menu, "accent.soft(accent.dark ? 0.18 : 0.12)")
expect(soft is not None and prop(fills["floating"], "color") == soft and transparent(fills["tiled"])
       and weight(prop(labels["floating"], "font")) == 700 and weight(prop(labels["tiled"], "font")) == 400
       and evaluated(checks["floating"], "color") == prop(labels["floating"], "color"),
       "the confirmed row is drawn in the accent's soft fill at weight 700, its check in its text colour; the other row in neither")
row_height, label_font = in_menu(menu, "m.px(32)"), prop(labels["tiled"], "font")
expect(row_height is not None and label_font is not None and all(near(row.height(), row_height) for row in rows.values())
       and prop(fills["tiled"], "radius") == 8 and near(row_at["tiled"].y() - row_at["floating"].y() - rows["floating"].height(), 1)
       and at(labels["tiled"], rows["tiled"]) is not None and near(at(labels["tiled"], rows["tiled"]).x(), inset)
       and near(label_font.pixelSize(), round(in_menu(menu, "m.font(13)"))) and label_font.family() == in_menu(menu, "m.family"),
       "its rows are the Controls board's menu rows: 32 px, radius 8, 1 px apart, the label 10 px in, Manrope 13 px, through the metrics")
menu_width, text_scale = in_menu(menu, "m.px(236)"), in_menu(menu, "m.ts")
expect(menu is not None and menu_width is not None and abs(menu.width() - menu_width) < 0.01
       and abs(prop(menu, "implicitWidth") - menu_width) < 0.01,
       "it is as wide as the board's menu, 236 px through the metrics, so large text widens it (%s px at text scale %s)"
       % (menu_width, text_scale))

hover = in_menu(menu, "Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)")
QTest.mouseMove(menu_view, centre(rows["tiled"]))
QTest.qWait(30)
tiled_hovered = prop(fills["tiled"], "color")
QTest.mouseMove(menu_view, centre(rows["floating"]))
QTest.qWait(30)
floating_hovered = prop(fills["floating"], "color")
QTest.mouseMove(menu_view, QPoint(395, 395))
QTest.qWait(30)
expect(hover is not None and tiled_hovered == hover and floating_hovered == soft and count(mfixture, "inputs") == 0
       and transparent(fills["tiled"]),
       "hover tints another row with the ink at 7%, leaves the confirmed row's fill, and is no input")

evaluated(menu, "focusConfirmed(false)")
QTest.qWait(10)
by_pointer = (focused(menu, rows), prop(rows["floating"], "visualFocus"), shown(rings["floating"]))
evaluated(menu, "focusConfirmed(true)")
QTest.qWait(10)
by_keys = (focused(menu, rows), prop(rows["floating"], "visualFocus"), shown(rings["floating"]))
expect(by_keys == ("floating", True, True),
       "opened by keys or the accessible press action, the confirmed row takes focus with a keyboard reason, its ring shown (%s)"
       % (by_keys,))
expect(by_pointer == ("floating", False, False),
       "opened by the pointer, the confirmed row takes focus with a mouse reason, and no ring (%s)" % (by_pointer,))
evaluated(menu, "focusConfirmed(false)")
QTest.qWait(10)
expect(focused(menu, rows) == "floating" and prop(rows["floating"], "visualFocus") is False and not shown(rings["floating"]),
       "opened again by the pointer after the keys, the row already focused takes the mouse reason anew, and the ring goes")
ring = rings["floating"]
evaluated(menu, "focusConfirmed(true)")
QTest.qWait(10)
expect(ring is not None and shown(ring) and at(ring, rows["floating"]) is not None and near(at(ring, rows["floating"]).x(), 0)
       and near(ring.width(), rows["floating"].width()) and evaluated(ring, "border.width") == 2
       and evaluated(ring, "border.color") == in_menu(menu, "accent.focusRing") and prop(ring, "radius") == 8,
       "the row's ring is 2 px in the focus colour on the row's own edge, as the window card's, so it covers no neighbour")

inputs = count(mfixture, "inputs")
moves = []
for code in (Qt.Key_Down, Qt.Key_Down, Qt.Key_Up, Qt.Key_Up):
    key(menu_view, code)
    moves.append((focused(menu, rows), prop(rows.get(focused(menu, rows)), "visualFocus")))
expect(moves == [("tiled", True), ("floating", True), ("tiled", True), ("floating", True)],
       "Down and Up move between the rows and wrap, each with the ring (%s)" % moves)
moves = []
for code in (Qt.Key_End, Qt.Key_Home, Qt.Key_End):
    key(menu_view, code)
    moves.append(focused(menu, rows))
expect(moves == ["tiled", "floating", "tiled"], "End and Home go to the last and the first row (%s)" % moves)
moves = []
for code, modifiers in ((Qt.Key_Tab, Qt.NoModifier), (Qt.Key_Tab, Qt.NoModifier), (Qt.Key_Tab, Qt.ShiftModifier),
                        (Qt.Key_Backtab, Qt.NoModifier)):
    key(menu_view, code, modifiers)
    moves.append((focused(menu, rows), prop(rows.get(focused(menu, rows)), "visualFocus")))
expect(moves == [("floating", True), ("tiled", True), ("floating", True), ("tiled", True)],
       "Tab and Backtab move between the rows through Qt's Tab chain and wrap, each with the ring (%s)" % moves)
expect(count(mfixture, "inputs") == inputs + 11 and listed(mfixture, "choices") == [],
       "each press of Up, Down, Home, End, Tab and Backtab reports one input, the first of which prepares, and chooses nothing (%s)"
       % (count(mfixture, "inputs") - inputs))
inputs = count(mfixture, "inputs")
for code in (Qt.Key_Down, Qt.Key_Up, Qt.Key_Home, Qt.Key_End, Qt.Key_Tab, Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Select):
    key(menu_view, code, repeat=True)
expect(menu is not None and count(mfixture, "inputs") == inputs and listed(mfixture, "choices") == [],
       "an auto-repeated press reports no input and chooses nothing, as the Space that opened the menu can repeat into it")
inputs, closes = count(mfixture, "inputs"), count(mfixture, "closes")
key(menu_view, Qt.Key_Escape)
expect(menu is not None and count(mfixture, "closes") == closes + 1 and count(mfixture, "inputs") == inputs,
       "Escape asks to close the menu, the user's close, and is no input")

if rows["floating"] is not None:
    rows["floating"].forceActiveFocus(Qt.TabFocusReason)
inputs = count(mfixture, "inputs")
for code in OPENING_KEYS:
    key(menu_view, code)
floating_choices = listed(mfixture, "choices")
if rows["tiled"] is not None:
    rows["tiled"].forceActiveFocus(Qt.TabFocusReason)
key(menu_view, Qt.Key_Return)
expect(floating_choices == ["floating"] * 4 and listed(mfixture, "choices") == ["floating"] * 4 + ["tiled"]
       and count(mfixture, "inputs") == inputs + 5,
       "on a row, each of Return, Enter, Space and Select reports one input and chooses that row's mode once, Space not twice (%s)"
       % listed(mfixture, "choices"))
inputs, choices = count(mfixture, "inputs"), listed(mfixture, "choices")
QTest.mousePress(menu_view, Qt.LeftButton, Qt.NoModifier, centre(rows["tiled"]))
QTest.qWait(10)
on_press = (count(mfixture, "inputs") - inputs, listed(mfixture, "choices")[len(choices):])
QTest.mouseRelease(menu_view, Qt.LeftButton, Qt.NoModifier, centre(rows["tiled"]))
QTest.qWait(10)
expect(menu is not None and on_press == (1, []) and listed(mfixture, "choices")[len(choices):] == ["tiled"]
       and count(mfixture, "inputs") == inputs + 1,
       "a left press on a row reports one input, and its release chooses that row (%s)" % (on_press,))
inputs, choices = count(mfixture, "inputs"), listed(mfixture, "choices")
QTest.mouseClick(menu_view, Qt.RightButton, Qt.NoModifier, centre(rows["floating"]))
QTest.qWait(10)
expect(menu is not None and count(mfixture, "inputs") == inputs and listed(mfixture, "choices") == choices,
       "a right click on a row reports nothing and chooses nothing")

if menu is not None:
    menu.setProperty("status", "No app window to tile")
    menu.setProperty("tiledBlocked", True)
if rows["floating"] is not None:
    rows["floating"].forceActiveFocus(Qt.TabFocusReason)
moves = []
for code, modifiers in ((Qt.Key_Down, Qt.NoModifier), (Qt.Key_Up, Qt.NoModifier), (Qt.Key_End, Qt.NoModifier),
                        (Qt.Key_Tab, Qt.NoModifier), (Qt.Key_Tab, Qt.ShiftModifier)):
    key(menu_view, code, modifiers)
    moves.append(focused(menu, rows))
text3 = in_menu(menu, 'accent.dark ? "#6f7892" : "#9aa0b2"')
expect(prop(rows["tiled"], "enabled") is False and moves == ["floating"] * 5,
       "a blocked Tiled row is disabled, and Up, Down, End, Tab and Backtab skip it (%s)" % moves)
expect(text3 is not None and prop(labels["tiled"], "color") == QColor(text3)
       and evaluated(rows["tiled"], "Accessible.description") == "No app window to tile",
       "the blocked Tiled row is drawn in the boards' disabled text colour, and its description gives the reason")
if menu is not None:
    menu.setProperty("tiledBlocked", False)
if rows["tiled"] is not None:
    rows["tiled"].forceActiveFocus(Qt.TabFocusReason)
QTest.qWait(10)
before_block = focused(menu, rows)
if menu is not None:
    menu.setProperty("tiledBlocked", True)
QTest.qWait(10)
expect(before_block == "tiled" and focused(menu, rows) == "floating" and prop(rows["floating"], "visualFocus") is True,
       "Tiled blocked while it has focus, Floating takes the active focus with a keyboard reason, not the menu's root (S12)")
# T9: a prepare done with Tiled queued but blocked ends the wait and blocks Tiled in one event, in
# whichever order the two properties change.
landed = []
for order in (("pending", "tiledBlocked"), ("tiledBlocked", "pending")):
    if menu is not None:
        menu.setProperty("tiledBlocked", False)
        QTest.qWait(10)
        rows["tiled"].forceActiveFocus(Qt.TabFocusReason)
        menu.setProperty("choice", "tiled")
        menu.setProperty("pending", True)
        QTest.qWait(10)
        waiting_focus = focused(menu, rows)
        for name in order:
            menu.setProperty(name, name == "tiledBlocked")
        QTest.qWait(10)
        landed.append((waiting_focus, focused(menu, rows), prop(rows["floating"], "visualFocus")))
if menu is not None:
    menu.setProperty("tiledBlocked", False)
    menu.setProperty("choice", "")
expect(landed == [("menu", "floating", True)] * 2,
       "the wait over with Tiled blocked in the same event (T9), Floating takes the focus with a keyboard reason, in either order (%s)"
       % landed)

if menu is not None:
    menu.setProperty("tiledBlocked", False)
    menu.setProperty("status", "")
    menu.setProperty("choice", "tiled")
    menu.setProperty("pending", True)
QTest.qWait(10)
expect(menu is not None and prop(rows["floating"], "enabled") is False and prop(rows["tiled"], "enabled") is False
       and prop(labels["tiled"], "text") == "Tiled…" and prop(labels["floating"], "text") == "Floating"
       and evaluated(rows["tiled"], "Accessible.name") == "Tiled"
       and evaluated(rows["tiled"], "Accessible.description") == "Waiting for an answer"
       and evaluated(rows["floating"], "Accessible.description") == "" and near(menu.width(), menu_width),
       "a choice awaited, both rows are disabled, the chosen row's label gains … and its description says it waits, at the same width")
inputs, choices, closes = count(mfixture, "inputs"), listed(mfixture, "choices"), count(mfixture, "closes")
QTest.mouseClick(menu_view, Qt.LeftButton, Qt.NoModifier, centre(rows["floating"]))
for code in (Qt.Key_Return, Qt.Key_Space, Qt.Key_Down):
    key(menu_view, code)
key(menu_view, Qt.Key_Escape)
expect(menu is not None and count(mfixture, "inputs") == inputs and listed(mfixture, "choices") == choices
       and count(mfixture, "closes") == closes + 1,
       "while it waits, the rows take no press and no key, and Escape still closes the menu")
if menu is not None:
    menu.setProperty("pending", False)
    menu.setProperty("choice", "")

text2 = in_menu(menu, 'accent.dark ? "#a3abc2" : "#4d546a"')
rows_before = {mode: at(row, menu) for mode, row in rows.items()}
height_before = prop(menu, "height")
status_hidden = shown(status_line)
if menu is not None:
    menu.setProperty("status", "Busy, try again")
QTest.qWait(10)
status_at = at(status_line, menu)
expect(status_at is not None and text2 is not None and not status_hidden and shown(status_line)
       and prop(status_line, "text") == "Busy, try again"
       and near(prop(status_line, "font").pixelSize(), round(in_menu(menu, "m.font(11.5)"))) and prop(status_line, "color") == QColor(text2)
       and status_at.y() >= rows_before["tiled"].y() + rows["tiled"].height()
       and all(at(row, menu) == rows_before[mode] for mode, row in rows.items()) and prop(menu, "height") > height_before,
       "in a top bar, the status line sits under the rows in 11.5 px secondary text, growing the menu away from the bar, no row moved")
LONG_STATUS = "A reason long enough that no translation of it could fit on one line of the menu, however short its words"
if menu is not None:
    menu.setProperty("status", LONG_STATUS)
QTest.qWait(10)
expect(menu is not None and status_line is not None and prop(status_line, "lineCount") > 1 and near(menu.width(), menu_width)
       and status_line.width() <= menu.width(),
       "a long status wraps, and the menu keeps its width")
if menu is not None:
    menu.setProperty("status", "")
QTest.qWait(10)
expect(menu is not None and not shown(status_line) and prop(menu, "height") == height_before,
       "with nothing to present, the status line takes no room")
menu_source = staged_source("LayoutMenu.qml")
expect(menu_source is not None and "announce(" not in menu_source,
       "the menu announces nothing itself, nor the reason S12 moves focus for: the owner's outcome handler is the one announcer")

_, tiled_menu = menu_fixture("tiled")
(trows, _, tchecks, _, _), _ = parts(tiled_menu)
evaluated(tiled_menu, "focusConfirmed(true)")
QTest.qWait(10)
expect(focused(tiled_menu, trows) == "tiled" and evaluated(trows["tiled"], "Accessible.checked") is True
       and shown(tchecks["tiled"]) and not shown(tchecks["floating"]),
       "with Tiled confirmed, the Tiled row is the checked one with the check, and it, not the first row, takes focus")

_, bottom_menu = menu_fixture("floating", location="BottomEdge")
(brows, _, _, _, _), bottom_status = parts(bottom_menu)
below = ({mode: prop(bottom_menu, "height") - at(row, bottom_menu).y() for mode, row in brows.items()}
         if bottom_menu is not None and None not in brows.values() else None)
if bottom_menu is not None:
    bottom_menu.setProperty("status", "Busy, try again")
QTest.qWait(10)
status_at = at(bottom_status, bottom_menu)
expect(status_at is not None and below is not None and shown(bottom_status)
       and status_at.y() + bottom_status.height() <= at(brows["floating"], bottom_menu).y()
       and all(near(prop(bottom_menu, "height") - at(row, bottom_menu).y(), below[mode]) for mode, row in brows.items()),
       "in a bottom bar, the status line sits above the rows, and appearing it keeps each row's distance from the bar's side")

translations["Floating"] = "Floating, in a translation long enough to need a second line in the menu"
_, long_menu = menu_fixture("tiled")
translations.clear()
(lrows, llabels, _, _, _), _ = parts(long_menu)
expect(long_menu is not None and row_height is not None and near(long_menu.width(), menu_width)
       and (prop(llabels["floating"], "lineCount") or 0) > 1
       and lrows["floating"].height() > row_height + 1 and near(lrows["tiled"].height(), row_height),
       "a long label wraps and its row grows taller, and the menu keeps its width")

_, touch_menu = menu_fixture("floating", touch=True)
(trows, tlabels, _, _, _), _ = parts(touch_menu)
touch_font = prop(tlabels["tiled"], "font")
expect(touch_menu is not None and touch_font is not None and near(touch_menu.width(), in_menu(touch_menu, "m.px(250)"))
       and all(near(row.height(), in_menu(touch_menu, "m.px(44)")) for row in trows.values())
       and at(tlabels["tiled"], trows["tiled"]) is not None and near(at(tlabels["tiled"], trows["tiled"]).x(), in_menu(touch_menu, "m.px(12)"))
       and near(touch_font.pixelSize(), round(in_menu(touch_menu, "m.font(14.5)") or 0)) and weight(touch_font) == 600
       and weight(prop(tlabels["floating"], "font")) == 700,
       "touch rows are the touch menu's: 44 px, the label 12 px in, 14.5 px at weight 600 (700 confirmed), and 250 px wide")

QGuiApplication.setLayoutDirection(Qt.RightToLeft)
_, rtl_menu = menu_fixture("floating")
(rrows, rlabels, rchecks, _, _), rstatus = parts(rtl_menu)
if rtl_menu is not None:
    rtl_menu.setProperty("status", "Busy, try again")
QTest.qWait(10)
rcheck_at, rlabel_at = at(rchecks["floating"], rrows["floating"]), at(rlabels["floating"], rrows["floating"])
expect(rcheck_at is not None and rlabel_at is not None and near(rcheck_at.x(), in_menu(rtl_menu, "m.px(10)"))
       and rcheck_at.x() + rchecks["floating"].width() <= rlabel_at.x()
       and evaluated(rlabels["floating"], "effectiveHorizontalAlignment === Text.AlignRight") is True
       and evaluated(rstatus, "effectiveHorizontalAlignment === Text.AlignRight") is True,
       "right to left, the check leads on the left, and the labels and the status line keep to the right")
QGuiApplication.setLayoutDirection(Qt.LeftToRight)
print(f"Layout menu: {control_checks - interactive_checks} checks, {control_failures - interactive_failures} failures")

for _, item in fixtures:
    item.deleteLater()
QTest.qWait(20)
print(f"Layout control: {control_checks} checks, {control_failures} failures")
if control_failures:
    sys.exit(1)
