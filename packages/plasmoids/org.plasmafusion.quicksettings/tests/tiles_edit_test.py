#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The quick settings tiles' edit mode in the staged real QML, offscreen, in a throw-away HOME.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 tiles_edit_test.py STAGE_HOME
(STAGE_HOME: the build's stage, `STAGE=... tools/build.sh quicksettings`.)

The main page (QuickSettingsMain.qml) on the real Backend, whose services find nothing to control
on the private bus; the widget's two settings keys are stand-ins that take what the page writes,
as main.qml does. Checks the grid's order and conditions, the pencil, reordering by mouse drag,
touch drag and keyboard, the Tab order, removing, the tray, adding back, Reset, Done and Escape,
and the tablet posture's pencil and touch targets; and the Do Not Disturb choices behind the tile's
chevron (read when they open, closed with the sheet, a choice counting from the click).
"""

import os
from pathlib import Path
import sys
import tempfile
import time

# The backend loads Plasma's clipboard module, whose Klipper code asks the offscreen platform for
# X11 and crashes on the missing connection (pages_test.py does the same); the services' files
# (Klipper's history, the posture's settings) go to a throw-away HOME.
os.environ["QT_QPA_OFFSCREEN_NO_GLX"] = "1"
os.environ.setdefault("QT_QUICK_BACKEND", "software")
HOME = tempfile.mkdtemp(prefix="pf-tiles-")
for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"):
    os.environ.pop(key, None)
os.environ["HOME"] = HOME

from PySide6.QtCore import QDate, QDateTime, QObject, QPoint, QPointF, Qt, QTime, QUrl, Slot  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQuick import QQuickItem, QQuickView  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402


def fill(text, args):
    for i, a in enumerate(args):
        text = text.replace("%" + str(i + 1), str(a))
    return text


class Context(QObject):
    @Slot(str, result=str)
    @Slot(str, "QVariant", result=str)
    def i18n(self, text, *args):
        return fill(text, args)

    @Slot(str, str, result=str)
    @Slot(str, str, "QVariant", result=str)
    @Slot(str, str, "QVariant", "QVariant", result=str)
    @Slot(str, str, "QVariant", "QVariant", "QVariant", result=str)
    def i18nc(self, context, text, *args):
        return fill(text, args)

    @Slot(str, str, str, "QVariant", result=str)
    @Slot(str, str, str, "QVariant", "QVariant", result=str)
    def i18ncp(self, context, singular, plural, count, *args):
        return fill(singular if count == 1 else plural, (count,) + args)


UI = Path(sys.argv[1]).resolve() / ".local/share/plasma/plasmoids/org.plasmafusion.quicksettings/contents/ui"
if not (UI / "components/FusionMetrics.qml").exists():
    raise SystemExit("Build the quick settings package into the stage first: " + str(UI))

HARNESS = """
import QtQuick
import "%(ui)s"
import "%(ui)s/components"

Item {
    id: root
    width: 324
    height: 900
    // The widget's settings keys and how often the page wrote them.
    property var tileOrder: []
    property var hiddenTiles: []
    property int writes: 0
    // Tablet posture's sizes, as main.qml sets them on the palette.
    property bool tablet: false
    Binding { target: backend.pal; property: "touch"; value: root.tablet }
    Binding { target: backend.pal; property: "tablet"; value: root.tablet }
    Backend {
        id: backend
        objectName: "backend"
        leader: false
        tileOrder: root.tileOrder
        hiddenTiles: root.hiddenTiles
        onTileLayoutRequested: (order, hidden) => {
            root.tileOrder = order;
            root.hiddenTiles = hidden;
            root.writes++;
        }
    }
    FusionMetrics { id: metrics }
    QuickSettingsMain {
        id: page
        objectName: "page"
        width: root.width
        backend: backend
        pal: backend.pal
        metrics: metrics
        // The conditional tiles' conditions are the test's (the private bus has no device).
        tileConditions: ({ "devices": false, "hotspot": false, "chargelimit": false, "tabletmode": false })
    }
}
"""

DEFAULT = ["wifi", "bluetooth", "nightlight", "dnd", "power", "darkstyle", "keepawake"]
checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


def items(item: QQuickItem):
    yield item
    for child in item.childItems():
        yield from items(child)


def find(name, visible=True):
    return next((i for i in items(root) if i.objectName() == name and (i.isVisible() or not visible)), None)


def centre(item):
    p = item.mapToScene(QPointF(item.width() / 2, item.height() / 2))
    return QPoint(round(p.x()), round(p.y()))


def click(item):
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, centre(item))
    QTest.qWait(60)


def key(k, modifiers=Qt.NoModifier):
    QTest.keyClick(view, k, modifiers)
    QTest.qWait(60)


def shown():
    """The tile ids in the grid as drawn: by row, then column."""
    tiles = [i for i in items(find("tileGrid")) if i.objectName().startswith("tile-") and i.isVisible()]
    tiles.sort(key=lambda t: (round(t.y()), round(t.x())))
    return [t.objectName()[5:] for t in tiles]


def stored():
    """The two settings keys as lists."""
    def value(name):
        v = root.property(name)
        v = v.toVariant() if hasattr(v, "toVariant") else v
        return [str(x) for x in (v or [])]
    return value("tileOrder"), value("hiddenTiles")


def focused():
    item = view.activeFocusItem()
    return item.objectName() if item else ""


def touch_step(action):
    sequence = QTest.touchEvent(view, device)
    action(sequence)
    sequence.commit()


def drag(source, target, touch=False, steps=8):
    """Takes `source` (an item) and lets go over `target` (a point), by mouse or touch."""
    start, end = centre(source), target
    if touch:
        touch_step(lambda seq: seq.press(0, start, view))
    else:
        QTest.mousePress(view, Qt.LeftButton, Qt.NoModifier, start)
    for n in range(1, steps + 1):
        p = QPoint(start.x() + (end.x() - start.x()) * n // steps, start.y() + (end.y() - start.y()) * n // steps)
        if touch:
            touch_step(lambda seq: seq.move(0, p, view))
        else:
            QTest.mouseMove(view, p)
        QTest.qWait(20)
    if touch:
        touch_step(lambda seq: seq.release(0, end, view))
    else:
        QTest.mouseRelease(view, Qt.LeftButton, Qt.NoModifier, end)
    QTest.qWait(250)


app = QGuiApplication(sys.argv[:1])
context = Context()
device = QTest.createTouchDevice()
tmp = tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False)
tmp.write(HARNESS % {"ui": UI.as_uri()})
tmp.close()
view = QQuickView()
view.rootContext().setContextObject(context)
view.setSource(QUrl.fromLocalFile(tmp.name))
os.unlink(tmp.name)
if view.status() == QQuickView.Error:
    raise SystemExit("page failed to load: " + "; ".join(e.toString() for e in view.errors()))
root = view.rootObject()
page = root.findChild(QObject, "page")
backend = root.findChild(QObject, "backend")
view.resize(324, 900)
view.show()
view.requestActivate()
QTest.qWait(800)

# ---- The grid in normal mode
check(shown() == DEFAULT, "a new user's grid: the seven tiles in the default order (%s)" % shown())
pencil = find("editTilesButton")
check(pencil is not None and pencil.property("text") == "Edit the tiles", "the header has the pencil, named Edit the tiles")
check(find("tileEditPanel") is None and find("edit-wifi") is None and find("remove-wifi") is None,
      "no edit controls before the pencil")
root.setProperty("tileOrder", ["darkstyle"] + [t for t in DEFAULT if t != "darkstyle"])
QTest.qWait(100)
check(shown()[0] == "darkstyle", "the stored order is the grid's order")
root.setProperty("tileOrder", [])
QTest.qWait(100)

# ---- Conditional tiles keep their conditions
page.setProperty("tileConditions", {"devices": True, "hotspot": False, "chargelimit": False, "tabletmode": False})
QTest.qWait(100)
check(shown() == DEFAULT + ["devices"], "Disks & Devices shows while its condition holds, at its place")
page.setProperty("tileConditions", {"devices": False, "hotspot": False, "chargelimit": False, "tabletmode": False})
QTest.qWait(100)
check("devices" not in shown(), "and not while it does not")

# ---- Edit mode
click(pencil)
check(page.property("editing") and find("tileEditPanel") is not None, "the pencil switches the grid into edit mode")
check(pencil.property("toggleOn"), "the pencil is drawn on while editing")
check(all(find("remove-" + t) is not None and find("edit-" + t) is not None for t in DEFAULT),
      "every tile has a remove badge and is one control")
# The tile's children in Tile.qml's order: background, the body's button, the chevron, ...
body, chevron = find("tile-wifi").childItems()[1:3]
check(not body.isEnabled() and not chevron.isVisible(),
      "the tiles' own actions rest: no toggle, no chevron")
check(find("editReset") is not None and not find("editReset").isEnabled(), "Reset to defaults is there, off while nothing changed")
check(find("add-wifi") is None, "the tray is empty while every tile is shown")

# Mouse drag: Dark style (third row, left) onto Wi-Fi's cell.
writes = root.property("writes")
drag(find("edit-darkstyle"), centre(find("tile-wifi")))
check(shown()[:2] == ["darkstyle", "wifi"], "a mouse drag moves Dark style first (%s)" % shown())
order, hidden = stored()
check(order[:2] == ["darkstyle", "wifi"] and len(order) == 11 and root.property("writes") == writes + 1,
      "the full order is written once, when the tile is let go")
check(find("editReset").isEnabled(), "Reset is offered once the order is the user's")

# Touch drag: Keep awake (last) onto the second cell (the tablet's sizes come later).
drag(find("edit-keepawake"), centre(find("tile-wifi")), touch=True)
check(shown()[:3] == ["darkstyle", "keepawake", "wifi"], "a touch drag moves Keep awake into the second cell (%s)" % shown())

# A drag let go outside the grid lands in the nearest cell: the last one.
drag(find("edit-darkstyle"), QPoint(80, 880))
check(shown()[-1] == "darkstyle", "a drag below the grid puts the tile last")

# Keyboard: Ctrl+arrows move, arrows move the focus, Tab follows the order shown.
find("edit-wifi").forceActiveFocus(Qt.TabFocusReason)
QTest.qWait(50)
before = shown()
at = before.index("wifi")
key(Qt.Key_Right, Qt.ControlModifier)
check(shown().index("wifi") == at + 1 and focused() == "edit-wifi" and view.activeFocusItem().property("visualFocus"),
      "Ctrl+Right moves the tile one place on, the focus stays on it with its ring")
key(Qt.Key_Down, Qt.ControlModifier)
check(shown().index("wifi") == at + 3, "Ctrl+Down moves it a row down")
key(Qt.Key_Home, Qt.ControlModifier)
check(shown()[0] == "wifi", "Ctrl+Home moves it first")
key(Qt.Key_Left, Qt.ControlModifier)
check(shown()[0] == "wifi", "Ctrl+Left on the first tile keeps it first")
key(Qt.Key_Right)
check(focused() == "edit-" + shown()[1] and shown()[0] == "wifi", "Right without Ctrl moves the focus to the next tile")
key(Qt.Key_Tab)
check(focused() == "edit-" + shown()[2], "Tab goes to the tile shown next (%s, %s)" % (focused(), shown()))
key(Qt.Key_Backtab)
key(Qt.Key_Backtab)
check(focused() == "edit-wifi", "Shift+Tab back to the first tile shown")
key(Qt.Key_End, Qt.ControlModifier)
check(shown()[-1] == "wifi", "Ctrl+End moves it last")

# Remove with the badge and with Delete; the tray offers them back.
order_before, _ = stored()
click(find("remove-nightlight"))
order_after, hidden = stored()
check("nightlight" not in shown() and hidden == ["nightlight"], "the badge removes Night light (hidden: %s)" % hidden)
check(order_after == order_before and find("add-nightlight") is not None, "the order is kept and the tray offers Night light")
find("edit-bluetooth").forceActiveFocus(Qt.TabFocusReason)
QTest.qWait(50)
place = shown().index("bluetooth")
key(Qt.Key_Delete)
check("bluetooth" not in shown() and stored()[1] == ["nightlight", "bluetooth"], "Delete removes the focused tile")
check(focused() == "edit-" + shown()[place], "the focus moves to the tile now in its place (%s)" % focused())
tray = [i.objectName() for i in items(find("tileEditPanel")) if i.objectName().startswith("add-") and i.isVisible()]
expected = ["add-" + t for t in stored()[0] if t in ("bluetooth", "nightlight")]
check(sorted(tray) == sorted(expected) and [i for i in items(find("tileEditPanel")) if i.objectName() == expected[0]][0].x() == 0,
      "the tray holds both, in the order (%s)" % tray)
add = find("add-nightlight")
check(add.property("text") == "Night light", "a tray button names its tile")
order_before_add = stored()[0]
click(add)
check("nightlight" in shown() and stored()[1] == ["bluetooth"] and stored()[0] == order_before_add,
      "adding Night light back shows it at its place in the order")

# A hidden conditional tile never shows; the tray offers it only while it applies.
page.setProperty("tileConditions", {"devices": True, "hotspot": False, "chargelimit": False, "tabletmode": False})
QTest.qWait(100)
check("devices" in shown(), "Disks & Devices appears in edit mode while it applies")
click(find("remove-devices"))
check("devices" not in shown() and find("add-devices") is not None, "removed, it waits in the tray")
page.setProperty("tileConditions", {"devices": False, "hotspot": False, "chargelimit": False, "tabletmode": False})
QTest.qWait(100)
check(find("add-devices") is None and "devices" not in shown(), "while it does not apply it is neither in the grid nor the tray")
page.setProperty("tileConditions", {"devices": True, "hotspot": False, "chargelimit": False, "tabletmode": False})
QTest.qWait(100)
check("devices" not in shown(), "hidden, it stays out of the grid when it applies again")

# Done and Escape leave edit mode; the pencil gets the focus back.
find("editDone").forceActiveFocus(Qt.TabFocusReason)
key(Qt.Key_Space)
check(not page.property("editing") and find("tileEditPanel") is None and focused() == "editTilesButton",
      "Done ends edit mode and the focus goes back to the pencil")
check(shown()[-1] == "wifi" and "bluetooth" not in shown(), "the normal grid keeps the new order and hidden tiles")
key(Qt.Key_Space)
check(page.property("editing"), "Space on the pencil starts edit mode again")
find("edit-dnd").forceActiveFocus(Qt.TabFocusReason)
key(Qt.Key_Escape)
check(not page.property("editing") and focused() == "editTilesButton", "Escape ends edit mode")
backend.setProperty("popupOpen", True)
click(pencil)
backend.setProperty("popupOpen", False)
QTest.qWait(50)
check(not page.property("editing"), "closing the sheet ends edit mode")

# Reset to defaults.
click(pencil)
click(find("editReset"))
check(stored() == ([], []) and shown() == DEFAULT + ["devices"] and not find("editReset").isEnabled(),
      "Reset to defaults clears both keys: the default order, every tile")
click(find("editDone"))

# A USB stick plugged in during a drag: Disks & Devices keeps its place and no tile is written twice.
NO_DEVICES = {"devices": False, "hotspot": False, "chargelimit": False, "tabletmode": False}
page.setProperty("tileConditions", NO_DEVICES)
root.setProperty("tileOrder", ["devices"] + DEFAULT)
QTest.qWait(100)
click(pencil)
start, target = centre(find("edit-keepawake")), centre(find("tile-wifi"))
QTest.mousePress(view, Qt.LeftButton, Qt.NoModifier, start)
for n in range(1, 9):
    QTest.mouseMove(view, QPoint(start.x() + (target.x() - start.x()) * n // 8, start.y() + (target.y() - start.y()) * n // 8))
    QTest.qWait(20)
page.setProperty("tileConditions", dict(NO_DEVICES, devices=True))
QTest.qWait(50)
# Still over the first cell, which the new tile takes for the moment.
for n in range(1, 5):
    QTest.mouseMove(view, QPoint(target.x() + n, target.y()))
    QTest.qWait(20)
QTest.mouseRelease(view, Qt.LeftButton, Qt.NoModifier, QPoint(target.x() + 4, target.y()))
QTest.qWait(250)
order = stored()[0]
check(sorted(order) == sorted(set(order)) and "devices" in order and order[0] == "keepawake",
      "a tile that appears during a drag: each tile stored once, Disks & Devices kept (%s)" % order)
check(shown()[:2] == ["keepawake", "devices"], "and the grid shows the drop (%s)" % shown()[:3])
click(find("editDone"))
page.setProperty("tileConditions", NO_DEVICES)
root.setProperty("tileOrder", [])
QTest.qWait(100)

# ---- Do Not Disturb's choices (the tile's chevron): worked out when they open, at the time of
# their own clock, closed with the sheet and on another page; a choice counts from the click.
dnd = backend.property("dnd")
for _ in range(250):
    if dnd.property("available"):
        break
    QTest.qWait(20)
check(dnd.property("available"), "Do Not Disturb is available (the service runs the notification server)")
backend.setProperty("popupOpen", True)
chevron = find("tile-dnd").childItems()[2]  # background, the body's button, the chevron
click(chevron)
check(page.property("dndChoicesOpen") and find("dnd-hour") is not None, "the chevron opens the Do Not Disturb choices")
backend.setProperty("popupOpen", False)
QTest.qWait(50)
backend.setProperty("popupOpen", True)
QTest.qWait(50)
check(not page.property("dndChoicesOpen") and find("dnd-hour") is None,
      "closing the sheet closes them: the next opening works them out again")
click(chevron)
backend.setProperty("page", "display")
QTest.qWait(50)
backend.setProperty("page", "main")
QTest.qWait(50)
check(not page.property("dndChoicesOpen"), "another page closes them too")
click(chevron)
opened = page.property("dndChoicesNow")
check(abs(opened - time.time() * 1000) < 5000, "opened again, they are read at the time they open")
# A Saturday evening on their clock: no "this evening", "Until Monday" offered.
page.setProperty("dndChoicesNow", float(QDateTime(QDate(2026, 10, 17), QTime(21, 0)).toMSecsSinceEpoch()))
QTest.qWait(50)
check(find("dnd-monday") is not None and find("dnd-evening") is None and find("dnd-hour") is not None,
      "they follow their clock (a Saturday at 21:00: Monday, no evening)")
click(find("dnd-hour"))
until = dnd.property("s").property("inhibitedUntil")
until = until.toMSecsSinceEpoch() if isinstance(until, QDateTime) else -1
check(abs(until - (time.time() + 3600) * 1000) < 120 * 1000 and not page.property("dndChoicesOpen"),
      "For 1 hour counts from the click, not from the clock the choices were read at")
backend.setProperty("popupOpen", False)
QTest.qWait(50)

# ---- Tablet posture: the pencil is in the tablet row, the targets have touch sizes.
laptop_height = find("tile-wifi").height()
root.setProperty("tablet", True)
QTest.qWait(150)
if find("tabletRow-rotation") is not None:
    check(find("editTilesButton") is None and find("tabletRow-edit") is not None,
          "tablet posture: the pencil is in the tablet row (the header has no room)")
    click(find("tabletRow-edit"))
else:
    check(find("editTilesButton") is not None, "tablet posture without the tablet row: the pencil stays in the header")
    click(find("editTilesButton"))
badge = find("remove-wifi")
check(page.property("editing") and badge.width() >= 44 and badge.height() >= 44, "the remove badge's target is 44 px in touch mode")
check(find("editDone").height() >= 44 and find("editReset").height() >= 44, "Done and Reset are 44 px tall")
check(find("tile-wifi").height() > laptop_height, "the tiles keep their tablet height (64 px on the board, 60 on the laptop)")
drag(find("edit-power"), centre(find("tile-wifi")), touch=True)
check(shown()[0] == "power", "a touch drag with the tablet metrics moves Power mode first (%s)" % shown())

view.close()
print(f"Quick settings tile editing: {checks} checks, 0 failures")
