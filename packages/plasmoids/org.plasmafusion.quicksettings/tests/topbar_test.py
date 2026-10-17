#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Quick settings' top bar (TopBar.qml) in the staged real QML on the real Backend, offscreen, in a
throw-away HOME.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 topbar_test.py STAGE_HOME
(STAGE_HOME: the build's stage, `STAGE=... tools/build.sh quicksettings`.)

The copy-text button (Main board: before the clipboard button, its size, quick settings' copy-text
glyph and name): shown by default, a click asks for copy text from the screen (the bar's
copyTextClicked, which main.qml hands to Backend.session.copyText()), hidden with its option off and
while the bar is compact (tablet posture, the width budget's step 2), whose saving counts it.
"""

import os
from pathlib import Path
import sys
import tempfile

# The backend loads Plasma's clipboard module, whose Klipper code asks the offscreen platform for
# X11 and crashes on the missing connection (pages_test.py does the same); the services' files go
# to a throw-away HOME.
os.environ["QT_QPA_OFFSCREEN_NO_GLX"] = "1"
os.environ.setdefault("QT_QUICK_BACKEND", "software")
HOME = tempfile.mkdtemp(prefix="pf-topbar-")
for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"):
    os.environ.pop(key, None)
os.environ["HOME"] = HOME

from PySide6.QtCore import QMetaObject, QObject, QPoint, QPointF, Q_ARG, Q_RETURN_ARG, Qt, QUrl, Slot  # noqa: E402
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
    width: 900
    height: 34
    // How often the bar asked for copy text from the screen.
    property int copyTexts: 0
    Backend {
        id: backend
        objectName: "backend"
        leader: false
    }
    FusionMetrics { id: metrics }
    TopBar {
        id: bar
        objectName: "bar"
        anchors.right: parent.right
        width: implicitWidth
        height: 34
        backend: backend
        metrics: metrics
        onCopyTextClicked: root.copyTexts++
    }
}
"""

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


def find(name):
    return next((i for i in items(root) if i.objectName() == name and i.isVisible()), None)


def button(text):
    """The visible bar button named `text`."""
    return next((i for i in items(root) if i.property("iconPath") is not None and i.property("text") == text
                 and i.isVisible()), None)


def left(item):
    return item.mapToScene(QPointF(0, 0)).x()


def centre(item):
    p = item.mapToScene(QPointF(item.width() / 2, item.height() / 2))
    return QPoint(round(p.x()), round(p.y()))


def saving(level):
    return QMetaObject.invokeMethod(bar, "budgetSaving", Qt.DirectConnection, Q_RETURN_ARG(float), Q_ARG(int, level))


app = QGuiApplication(sys.argv[:1])
context = Context()
tmp = tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False)
tmp.write(HARNESS % {"ui": UI.as_uri()})
tmp.close()
view = QQuickView()
view.rootContext().setContextObject(context)
view.setSource(QUrl.fromLocalFile(tmp.name))
os.unlink(tmp.name)
if view.status() == QQuickView.Error:
    raise SystemExit("top bar failed to load: " + "; ".join(e.toString() for e in view.errors()))
root = view.rootObject()
backend = root.findChild(QObject, "backend")
bar = root.findChild(QObject, "bar")
view.resize(900, 34)
view.show()
QTest.qWaitForWindowExposed(view)
QTest.qWait(400)

# ---- The copy-text button, as the Main board draws it
glyph = (UI / "components/Icons.js").read_text().split('var copyText = "', 1)[1].split('"', 1)[0]
copy_text = find("copyTextBarButton")
clipboard = button("Clipboard")
check(copy_text is not None and copy_text.property("text") == "Copy text from the screen"
      and copy_text.property("iconPath") == glyph,
      "the bar's copy-text button: shown by default, named, with quick settings' copy-text glyph")
check(clipboard is not None and copy_text.width() == clipboard.width() and copy_text.height() == clipboard.height(),
      "... the clipboard button's size (%gx%g)" % (copy_text.width(), copy_text.height()))
gap = left(clipboard) - (left(copy_text) + copy_text.width())
check(0 < gap <= 8, "... right before the clipboard button, the bar's gap apart (%g px)" % gap)

# A click asks for copy text from the screen.
QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, centre(copy_text))
QTest.qWait(60)
check(root.property("copyTexts") == 1, "a click asks for copy text from the screen")
QMetaObject.invokeMethod(copy_text, "forceActiveFocus", Qt.DirectConnection)
QTest.keyClick(view, Qt.Key_Return)
QTest.qWait(60)
check(root.property("copyTexts") == 2, "... and Return on it")

# ---- Its option, the compact bar and the width budget
with_button = saving(2)
backend.setProperty("showCopyText", False)
QTest.qWait(100)
check(find("copyTextBarButton") is None and button("Clipboard") is not None,
      "its option off: no copy-text button, the clipboard button stays")
check(abs(with_button - saving(2) - (copy_text.width() + gap)) <= 1,
      "the width budget's step 2 gives up its width and gap (%g vs %g)" % (with_button, saving(2)))
backend.setProperty("showCopyText", True)
backend.setProperty("barCompact", True)
QTest.qWait(100)
check(find("copyTextBarButton") is None and button("Clipboard") is None,
      "a compact bar (tablet posture, budget step 2): copy text leaves the bar with the clipboard")
backend.setProperty("barCompact", False)
QTest.qWait(100)
check(find("copyTextBarButton") is not None, "and comes back with it")

view.close()
print(f"Quick settings top bar: {checks} checks, 0 failures")
